//
//  MobileGatewayService.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 04.05.2022.
//

import Foundation
//import UIKit
import Combine

import WiliotCore



fileprivate let logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEUMobileGatewayService")

enum BLEUMobileGatewayConnectionState: Equatable {
    
    case disconnecting
    case disconnected
    case connecting
    case connected
    case disconnectedWithError(String)
    
    public static func ==(lhs:BLEUMobileGatewayConnectionState, rhs:BLEUMobileGatewayConnectionState) -> Bool {
        
        
        switch lhs {
        case .disconnecting:
            if case .disconnecting = rhs {
                return true
            }
        case .disconnected:
            if case .disconnected = rhs {
                return true
            }
        case .connecting:
            if case .connecting = rhs {
                return true
            }
        case .connected:
            if case .connected = rhs {
                return true
            }
        case .disconnectedWithError(let lhsMessage):
            if case .disconnectedWithError(let rhsMessage) = rhs {
                return lhsMessage == rhsMessage
            }
        }
        
        return false
    }
}

fileprivate let kSequenceIdMax = Int64.max

extension BLEUMobileGatewayService : CustomStringConvertible {
    var description: String {
        return "MobileGatewayService. connectionState: \(self.connectionState), ownerId: \(gatewayConfig.accountId.string)"//, stage:\(cloudStage)"
    }
}

final class BLEUMobileGatewayService  {
    #if DEBUG
    fileprivate static var refCount:Int = 0 {
        didSet {
            logger.notice("refCount: \(self.refCount)")
        }
    }
    #endif
    static let pacingInterval:Int = 10
    
    private enum Topic:String {
        case data
        case status
        //case bridgeStatus = "bridge-status"
    }
    
    var connectionState:BLEUMobileGatewayConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                _connectionStatePublisher.send(connectionState)
            }
        }
    }
    
    var connectionStatePublisher: AnyPublisher<BLEUMobileGatewayConnectionState, Never> {
        self._connectionStatePublisher.eraseToAnyPublisher()
    }
    
    private lazy var _connectionStatePublisher:PassthroughSubject<BLEUMobileGatewayConnectionState, Never> = .init()

    
    private(set) var preferredConnectionType:PreferredConnectionType = .wirelessOrEthernet {
        didSet {
            if networkConnectionTypeChangeIsAffecting {
                handleConnectionTypeChanged(from: oldValue, to:preferredConnectionType)
            }
        }
    }
    private var networkConnectionTypeChangeIsAffecting:Bool = false
    
    var gatewayId:String {
        self.gatewayConfig.gatewayId.string
    }
    
    
    private var isRestartAfterStopNeeded:Bool = false

    let gatewayType: String = "mobile"

    private var sequenceIdCounter:Int64 = 0
    
    
    private var tempGWToken:String?
    private var lastKnownLocation:WLTLocation?
    
    private var mqttClient:BLEUMQTTClient?
    private let coordinatesContainer:LocationCoordinatesContainer
    private var shouldBeDeallocated:Bool = false
    
    private var currentCancellable:AnyCancellable?
    
    private lazy var operationQueue:OperationQueue = {
        let opQueue = OperationQueue() //OperationQueueWithCounter(withName: "com.MobileGatewayService.packetsSendingQueue")
        opQueue.name = "com.Wiliot.BLEUMobileGatewayService.packetsSendingQueue"
        opQueue.maxConcurrentOperationCount = 1
        return opQueue
    }()
    
    
    
    private var queueTimerQueue:DispatchQueue = DispatchQueue(label: "MobileGatewayService_timerQueue", qos: DispatchQoS.default, attributes: DispatchQueue.Attributes.initiallyInactive, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem, target: nil)
    
    private var queuedCalls:[()->()] = []
    private var queueTimer:DispatchSourceTimer?
    
    //MARK: - Init
    static func withDummies() -> BLEUMobileGatewayService {
        logger.warning("MobileGatewayService Dummy is initializing...")
        
        let dummyConfig = BLEUMobileGatewayConfig(locationSource: LocationCoordinatesContainerDummy(),
                                                  endpoint: BLEUpstreamEndpoint.test(),
                                                  accountId: NonEmptyCollectionContainer("Test_Owner_ID")!,
                                                  appVersion: NonEmptyCollectionContainer("3.4.3-2")!,
                                                  gatewayId: NonEmptyCollectionContainer("Dummy_UUID_string")!, 
                                                  connectionToken: NonEmptyCollectionContainer("Not_a_real_token")!)
        
        let service = BLEUMobileGatewayService(config: dummyConfig)
        return service
    }
   
    private (set) var gatewayConfig:BLEUMobileGatewayConfig
    
    init(config:BLEUMobileGatewayConfig) {
        #if DEBUG
        Self.refCount += 1
        #endif
        //self.applicationVersionString = config.appVersion
        
        logger.notice("+ MobileGatewayService init for - owner:\(config.accountId.string)")
       
        self.gatewayConfig = config
        self.coordinatesContainer = config.locationSource
        self.tempGWToken = config.connectionToken.string
        
        //self.preferredConnectionType = connectionType
    }

    deinit {
        #if DEBUG
        Self.refCount -= 1
        #endif
        
        let _ = forceStopClient()
        
        queuedCalls.removeAll()
        
        if operationQueue.isSuspended {
            operationQueue.isSuspended = false
        }
        
        operationQueue.cancelAllOperations()
        
        if let _ = self.queueTimer {
            self.stopMessagesTimer()
        }

    }

    //MARK: - Connection
    func startConnection() throws {
        logger.info(" + \(#function) ..")
        
        guard let nonEmptyGWToken = self.tempGWToken, !nonEmptyGWToken.isEmpty else {
            logger.notice("No gateway Token to start connection")
            throw ValueReadingError.missingRequiredValue("No connection token")
        }
        guard connectionState != .connecting else {
            logger.notice(" + \(#function) will not start Connection (in progress)")
            throw ValueReadingError.invalidValue("already establishing connection")
        }
        
        if (self.mqttClient?.connectionState ?? "Unknown") == "connected" {
            logger.notice(" + \(#function) will not start Connection (is Connected)")
            throw ValueReadingError.invalidValue("already connected")
        }
        
        let gatewayId:String = self.gatewayConfig.gatewayId.string
        
        logger.notice(" + \(#function) Creating new client with gatewayID: \(gatewayId)")
        
        connectionState = .connecting
        
        let isStopping = forceStopClient()
        
        if isStopping {
            //introduce a delay
            let sema = DispatchSemaphore(value: 0)
            
            let _ = sema.wait(timeout: DispatchTime.now() + .milliseconds(500))
            //proceed after delay
        }
        
        try startNewClientWith(token: nonEmptyGWToken)
    }
    
    private func forceStopClient() -> Bool {
        guard let client = self.mqttClient else {
            return false
        }
        
        logger.notice(#function)
        
        client.removeConnectionStateDelegate()
        client.stopAndDisconnect()
        self.mqttClient = nil
        return true
    }
    
    private func startNewClientWith(token:String) throws {
        logger.notice("\(#function)")
        
        let client = try BLEUMQTTClient(clientId: self.gatewayConfig.gatewayId.string,
                                        userName: self.gatewayConfig.accountId.string,
                                        connectionToken: token,
                                        endpointInfo: self.gatewayConfig.endpoint,
                                        delegate: WeakObjectContainer(self))
        
        //            logger.notice(" + \(#function) will START connection to stage: \(stage.upperCaseValue)")
        self.mqttClient = client
        
        let started = try client.start()
        
        logger.notice(" + \(#function) Started connection: \(started)")
       
        
    }
    
    func prepareToBeDeallocated() {
        shouldBeDeallocated = true
    }
    
    func stop() {
        logger.notice(#function)
        
        guard let client = self.mqttClient else {
            logger.notice("No MQTT connection returning early")
            connectionState = .disconnected
            return
        }
        
        self.operationQueue.cancelAllOperations()
        self.queuedCalls.removeAll()
        
        if !isRestartAfterStopNeeded {
            self.stopMessagesTimer()
        }
        
        else {
            self.queueTimer?.suspend()
            self.queueTimer?.setEventHandler(handler: {})
            self.queueTimer?.resume()
        }
        
        if client.connectionState == "connected" {
            self.connectionState = .disconnecting
        }
        
        client.stopAndDisconnect()
    }
    
    private func addStatusGatewayConfigMessageToMessagesQueue() {
        
        logger.notice(#function)

        guard let client = self.mqttClient,
              let topicString = makeTopicString(topic: Topic.status) else {
            return
        }
        
        #if DEBUG
        let versionString = self.gatewayConfig.appVersion.string + "-debug"
        #else
        let versionString = self.gatewayConfig.appVersion.string
        #endif
        
        let capabilitiesMessage:GatewayCapabilitiesMessage = GatewayCapabilitiesMessage.createWith(applicationVersion: versionString, pacingPeriod: Self.pacingInterval)
        
        
        do {
            let messageStr:String = try GatewayDataEncoder.tryEncodeToString(capabilitiesMessage)
            self.queuedCalls.append  {[weak client] in
                guard let mqttClient = client, mqttClient.connectionState.lowercased() == "connected" else {
                    logger.warning("Failing to senf Capabilities message: 'ConnectionState' appears to be not 'connected'")
                    return
                }
                
                do {
                    #if DEBUG
                    let data = messageStr.data(using: .utf8)!
                    let json = try! JSONSerialization.jsonObject(with: data)
                    let prettyData = try! JSONSerialization.data(withJSONObject: json, options: JSONSerialization.WritingOptions.prettyPrinted)
                    let prettyString = String(data: prettyData, encoding: .utf8)!
                    logger .notice("Trying to send Capabilities message: \(prettyString)")
                    #endif
                    try mqttClient.sendMessage(messageStr, topic: topicString)
                }
                catch {
                    logger.warning("Send Gateway Capabilities message. mqttClient Error sending message: \(error)")
                }
            }
        }
        catch {
            logger.warning("Failed to encode Capabiliries message for sending: \(error)")
           // Crashlytics.crashlytics().log("Failed to send Gateway Capabilities status message")
        }
    }
    
    private func startMessagesTimer() {
        logger.notice(#function)
        
        let workItem = self.timerEventHandler()
        
        guard self.queueTimer == nil else {
            self.queueTimer?.setEventHandler(handler: workItem)
            return
        }
        
        let aQueueTimer = DispatchSource.makeTimerSource(queue: queueTimerQueue)
        
        aQueueTimer.setEventHandler(handler: workItem)
        self.queueTimer = aQueueTimer
        
        self.queueTimerQueue.activate()
        aQueueTimer.schedule(deadline: .now() + .seconds(1), repeating: 1)
        aQueueTimer.activate()
        
        if operationQueue.isSuspended {
            operationQueue.isSuspended = false
        }
    }
    
    private func timerEventHandler() -> DispatchWorkItem {
        let workItem = DispatchWorkItem {
            [weak self] in
                guard let weakSelf = self else {
                    return
                }
            
            //logger.notice("Gateway timer tick.")
            if weakSelf.queuedCalls.isEmpty ||  weakSelf.shouldBeDeallocated {
                return
            }
            
            
            let nextItem = weakSelf.queuedCalls.removeFirst()
            weakSelf.operationQueue.addBarrierBlock {
                nextItem()
            }
//            weakSelf.operationQueue.addOperation {
//                nextItem()
//            }
        }
        
        return workItem
    }
    
    private func stopMessagesTimer() {
        logger.notice(#function)
        
        if let timer = self.queueTimer,
           !timer.isCancelled {
            timer.suspend()
            timer.setEventHandler(handler: {})
            timer.resume()
            timer.cancel()
        }
        
        self.queueTimer = nil
    }
    
    //MARK: -
    
    func setPreferredConnectionType(_ connType:PreferredConnectionType) {
        guard self.preferredConnectionType != connType else {
            return
        }
        
        if self.connectionState == .connected {
            self.networkConnectionTypeChangeIsAffecting = true
        }
        self.preferredConnectionType = connType
    }
    
    func setNewGatewayAuthToken(_ tokenContainer:NonEmptyCollectionContainer<String>) {
        logger.notice("\(#function) with Token: \(tokenContainer.string)")
                      
        self.isRestartAfterStopNeeded = true
        
        if connectionState == .connected {
            self.tempGWToken = tokenContainer.string
            self.stop()
        }
        else {
            self.tempGWToken = tokenContainer.string
            do {
                try self.startConnection()
            }
            catch {
                self.connectionState = .disconnectedWithError(error.localizedDescription)
            }
        }
    }
    
    
    
    //MARK: -
    private func handleConnectionTypeChanged(from oldValue: PreferredConnectionType, to currentValue:PreferredConnectionType) {
        precondition(oldValue != currentValue, "Error: handling change to the same connection type")
        logger.notice("\(#function) \(oldValue.description) -> \(currentValue.description)")
        if oldValue < currentValue { //e.g. cellular -> WiFi_or_Ethernet
            self.stop()
        }
        else {
            self.stop()
        }
    }
    
    //MARK: - Topic
    private func makeTopicString(topic:Topic) -> String? {
        
        let clientId = gatewayId
        
        let topicName = topic.rawValue //"data", "status"
//        if topic == .data, cloudStage == .prodLegacy {
//            topicName.append("-prod")
//        }
        let ownerId = gatewayConfig.accountId.string
        
        let toReturn = "\(topicName)/\(ownerId)/\(clientId)"
        
        return toReturn
    }
    
    private func tryToSendGatewayPacketsData(_ packetsData: GatewayPacketsData) {
        
        guard tempGWToken == nil else {
            return
        }
        
        guard let topicToPublish = self.makeTopicString(topic: .data),
              let client = self.mqttClient else {
            logger.notice(" - No Topic or mqttClient to send packets.")
            return
        }
        
        if client.connectionState.lowercased() != "connected" {
            logger.notice("Will skip message sending: Client is not connected")
            return
        }
            
        do {

            let messageStr = try GatewayDataEncoder.tryEncodeToString(packetsData)
            self.queuedCalls.append  {[weak client] in
                guard let mqttClient = client, mqttClient.connectionState.lowercased() == "connected" else {
                    return
                }
                do {
                    //logger.notice("actual send Payloads to topic: \(topicToPublish), message: \(messageStr)")
//                    #if DEBUG
//                    do{
//                        let data:Data = messageStr.data(using: String.Encoding.utf8)!
//                        
//                        let object = try JSONSerialization.jsonObject(with: data)
//                        let prettyData = try JSONSerialization.data(withJSONObject: object, options: .prettyPrinted)
//                        let prettyString = String(data: prettyData, encoding: .utf8)!
//                        
//                        logger.info("Sending payload message: \n\(prettyString)")
//                    }
//                    catch {
//                        
//                    }
//                    #endif
                    
                    try mqttClient.sendMessage(messageStr, topic: topicToPublish)
                }
                catch {
                    logger.warning(" tryToSendGatewayPacketsData. mqttClient  Error sending message: \(error)")
                }
            }
            
        }
        catch {
            logger.warning("MobileGatewayService tryToSendGatewayPacketsData. Error sending message with encoding:\(error)")
        }
    }
    
}

//MARK: TagPacketsSender
extension BLEUMobileGatewayService:TagPacketsSending {
    
    func sendPacketsInfo(_ infoContainer: NonEmptyCollectionContainer<[TagPacketData]>) {
        
        if let coord = coordinatesContainer.currentLocationCoordinates {
            self.lastKnownLocation = WLTLocation(coordinate: coord)
        }
        
        let tagPackets:[TagPacketData] = infoContainer.array
        
//        operationQueue.addOperation({[weak self, tagPackets] in
                
                if let queue = OperationQueue.current,
                   queue == OperationQueue.main {
                    logger.warning("sendPacketsInfo  Called from the MainQueue")
                }
                
//                guard let self = self else {
//                    return
//                }
                
                if self.sequenceIdCounter == kSequenceIdMax {
                    self.sequenceIdCounter = 0
                }
                
                let infosWithAddedSequenceId:[TagPacketData] = tagPackets.map { input in
                    
                    self.sequenceIdCounter += 1
                    let result:TagPacketData = input.fromOtherPacketDataWithSequenceId(self.sequenceIdCounter)
                    return result
                }
                
                let gatewayPacketsData = GatewayPacketsData(location: self.lastKnownLocation,
                                                            gatewayId: self.gatewayConfig.gatewayId.string,
                                                            packets: infosWithAddedSequenceId)
                
            self.tryToSendGatewayPacketsData(gatewayPacketsData)
//        })
    }
}


extension BLEUMobileGatewayService:TagPacketsPayloadLogSender {
    
    func sendLogPayloads(_ payloadsContainer: NonEmptyCollectionContainer<[String]>) {
        
        if let coord = coordinatesContainer.currentLocationCoordinates {
            self.lastKnownLocation = WLTLocation(coordinate: coord)
        }
        
        
        let payloads:[String] = payloadsContainer.array
        
        let preparedLogData:GatewayTagPacketsLogData = GatewayTagPacketsLogData(location: lastKnownLocation,
                                                                                gatewayId: gatewayConfig.gatewayId.string,
                                                                                gatewayLogs: payloads)
        
        guard let topic = makeTopicString(topic: .status),
              let mClient = mqttClient else {
            return
        }
        
        do {
//            let data = try GatewayDataEncoder.encode(preparedLogData)
//            let string = try GatewayDataEncoder.encodeDataToString(data)
            let msgString = try GatewayDataEncoder.tryEncodeToString(preparedLogData)
            logger.notice(" attempting to send log payloads")
            try mClient.sendMessage(msgString, topic:topic) //(string, topic: topic)
            
        }
        catch {
            logger.warning("\(#function) Error sending message:\(error)")
        }
    }
}

//MARK: - MQTTClientDelegate
extension BLEUMobileGatewayService: WiliotMQTTClientDelegate {
    func mqttClientIsConnecting() {
        logger.notice(" \(#function)")
        connectionState = .connecting
    }
    
    func mqttClientDidConnect() {
        logger.notice(" \(#function) ")
    
        connectionState = .connected
        addStatusGatewayConfigMessageToMessagesQueue()
        startMessagesTimer()
        if tempGWToken != nil {
            tempGWToken = nil
        }
    }
    
    func mqttClientDidDisconnect() {
        logger.notice(" \(#function)")
        
        if isRestartAfterStopNeeded {
            isRestartAfterStopNeeded = false
            if let authToken = self.tempGWToken {
                self.tempGWToken = authToken
                
                do {
                    try startConnection()
                    logger.notice("Started new connection")
                }
                catch {
                    logger.warning("isRestartAfterStopNeeded failed: \(error)")
                    connectionState = .disconnectedWithError(error.localizedDescription)
                }
                
            }
            else {
                connectionState = .disconnectedWithError("No Gateway Auth Token Found for restart")
            }
        }
        else {
            
                        
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {[weak self] in
                guard let self else { return }
                
                if self.shouldBeDeallocated {
                    if let client = self.mqttClient {
                        
                        client.removeConnectionStateDelegate()
                        
                        do {
                            try client.close()
                        }
                        catch {
                            logger.notice("Failed to close mqtt client: \(error)")
                        }
                        self.mqttClient = nil
                    }
                }
                
                self.connectionState = .disconnected
                

            }
        }
        
    }
    
    func mqttClientDidEncounterError(_ error: Error, willAttemptToReconnect willAtempt:Bool) {
        logger.notice(" \(#function) willReconnect: \(willAtempt)" )
        
        if let mqttError = error as? WiliotMQTTClientError {
            
            if isRestartAfterStopNeeded {
                isRestartAfterStopNeeded = false
            }
            
            switch mqttError {
            case .expiringToken:
                logger.notice(" \(#function)  mqttError:\(mqttError)")
            case .invalidTokenUsername:
                logger.notice(" \(#function)  mqttError:\(mqttError)")
            case .mttClientInitializationCredentialsError(let initError):
                logger.notice(" \(#function)  mqttError:'\(mqttError)'. Failed to Initialize client with error: '\(initError)'")
            }
            
            
            if !willAtempt {
                
                
                connectionState = .disconnectedWithError(error.localizedDescription)
                let _ = forceStopClient()
            }

        }
        else {
            logger.notice(" \(#function)  Error:\(error)")
            //Crashlytics.crashlytics().record(error: StateError.failureWitMessageAndOptionalError("mqttClientDidEncounterError", error))
            
            if willAtempt {
                connectionState = .disconnected
            }
            else {
                connectionState = .disconnectedWithError(error.localizedDescription)
            }
        }
    }
    
    
}



