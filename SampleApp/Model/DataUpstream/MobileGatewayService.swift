

import Foundation
import Combine
import OSLog

#if DEBUG
fileprivate let logger = Logger(subsystem: "Upstream", category: "MobileGatewayService")
#else
fileprivate let logger = Logger(.disabled)
#endif

fileprivate let kSequenceIdMax = Int64.max

class MobileGatewayService  {
    private(set) var authToken:String?
    private(set) var gatewayAccessToken:String?
    private(set) var gatewayRefreshToken:String?
    ///send event outside for interested client (for debug or some UI updates like blink some indicator
    private(set) var sendEventSignal:(()->())?
    var didConnectCompletion:((Bool) ->())?
    /// completio on Did Disconnect message from the MQTTClient
    var didStopCompletion:(()->())?
    var authTokenCallback:((Error?) ->())?
    var gatewayTokensCallBack:((Error?) -> ())?
    var isConnected:Bool = false
    var locationSource:LocationSource?
    
    let gatewayType: String = "Wiliot iPhone"
    var statusPublisher:AnyPublisher<String?, Never> {
        return _statusPassThroughSubject.eraseToAnyPublisher()
    }
    
    private lazy var _statusPassThroughSubject:PassthroughSubject<String?, Never> = .init()
    
    private let currentOwnerId:String
    
    private lazy var gatewayId: String = {
        let anID = Device.deviceId
        return anID
    }()
    
    private var sequenceIdCounter:Int64 = 0
    private var isConnecting = false
    private var mqttClient:MQTTClient?
    private let gatewayRegistrator:GatewayRegistrator
    private let authTokenRequester:AuthTokenRequester
    
    private var lastKnownLoction:Location?
    
    private var queuedCalls:[()->()] = []
    private lazy var operationQueue:OperationQueue = {
        let opQueue = OperationQueue()
        opQueue.name = "com.SampleApp.MobileGatewayService.packetsSendingQueue"
        opQueue.maxConcurrentOperationCount = 1
        return opQueue
    }()
    
    private var queueTimer:DispatchSourceTimer?
    private var queueTimerQueue:DispatchQueue = DispatchQueue(label: "com.SampleApp.MobileGatewayService_timerQueue", qos: DispatchQoS.default, attributes: DispatchQueue.Attributes.initiallyInactive, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem, target: nil)
    
    
    private enum Topic:String {
        case data
        //case status
    }
    
    //MARK: - Init
    
    init(ownerId:String, authTokenRequester: AuthTokenRequester, gatewayRegistrator:GatewayRegistrator) {
        
        self.currentOwnerId = ownerId
        
        self.gatewayRegistrator = gatewayRegistrator
        self.authTokenRequester = authTokenRequester
    }
    
    deinit {
        mqttClient = nil
        #if DEBUG
        print("+ MobileGatewayService deinit +")
        #endif
    }
    
    //MARK: - Authorization

    func obtainAuthToken() {
        
        _statusPassThroughSubject.send("Obtaining auth token")
        
        authTokenRequester.getAuthToken {[weak self] tokenResult in
            
            guard let self = self else {
                return
            }
        
            self._statusPassThroughSubject.send(nil)
            
            switch tokenResult {
            case .failure(let error):
                self.authTokenCallback?(error)
            case .success(let authToken):
                self.authToken = authToken
                self.authTokenCallback?(nil)
            }
        }
    }
    
    func registerAsGateway(userAuthToken token:String, ownerId:String) {
        _statusPassThroughSubject.send("Registering as gateway...")
        gatewayRegistrator.registerGatewayFor(owner: ownerId, gatewayId: gatewayId, authToken: token) { [weak self] gatewayTokensResult in
            guard let self = self else {
                return
            }
            
            switch gatewayTokensResult {
            case .failure(let error):
                self.gatewayTokensCallBack?(error)
            case .success(let tokens):
                self.gatewayAccessToken = tokens.auth
                self.gatewayRefreshToken = tokens.refresh
                self.gatewayTokensCallBack?(nil)
            }
            
        }
    }

    func refreshRegistration(gatewayRefreshToken refreshToken:String) {
        
        _statusPassThroughSubject.send("Refreshing gateway authorization")
        
        gatewayRegistrator.refreshGatewayTokensWith(refreshToken: refreshToken) { [weak self] gatewayTokensResult in
            guard let self = self else {
                return
            }
            
            switch gatewayTokensResult {
            case .failure(let error):
                self.gatewayTokensCallBack?(error)
            case .success(let tokens):
                self.gatewayAccessToken = tokens.auth
                self.gatewayRefreshToken = tokens.refresh
                self.gatewayTokensCallBack?(nil)
            }
        }
    }
    
    //MARK: - Connection
    func startConnection(withGatewayToken gwAuthToken:String) -> Bool {
        
        guard !isConnecting else {
            return false
        }
        _statusPassThroughSubject.send("Connecting...")
        isConnecting = true
        
        do {
            let client = try MQTTClient(clientId: gatewayId,
                                         connectionToken: gwAuthToken,
                                         endpoint: MQTTEndpoint.defaultEndpoint,
                                         delegate: self)
            let started = try client.start()
            self.mqttClient = client
            return started
        }
        catch {
            isConnecting = false
            isConnected = false
            didConnectCompletion?(false)
            return false
        }
    }
    
    func stop() {
        stopMessagesTimer()
        self.mqttClient?.stopAndDisconnect()
        //self.mqttClient = nil
    }
    
    func setSendEventSignal(_ eventHandler: @escaping(()->())) {
        self.sendEventSignal = eventHandler
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
        let workItem = DispatchWorkItem {[weak self] in
                guard let weakSelf = self else {
                    return
                }
            
            logger.notice("Gateway timer tick.")
            if weakSelf.queuedCalls.isEmpty {
                
                return
            }
            
            let nextItem = weakSelf.queuedCalls.removeFirst()
            weakSelf.operationQueue.addOperation {
                nextItem()
            }
        }
        
        return workItem
    }
    
    private func stopMessagesTimer() {
        logger.notice(#function)
        
        if let timer = self.queueTimer,
           !timer.isCancelled {
            timer.cancel()
        }
        
        self.queueTimer = nil
    }
    
    //MARK: - Topic
    private func getTopicString(topic:Topic) -> String? {
        
        guard let clientId = mqttClient?.clientId else {
            return nil
        }
        
        let topicName = topic.rawValue
        let ownerId = currentOwnerId
        
        let toReturn = "\(topicName)/\(ownerId)/\(clientId)"
        return toReturn
    }
    
    //MARK: - MQTT transmissions
    //MARK: TagPacketsSender
}

extension MobileGatewayService:TagPacketsSender {
    func sendPacketsInfo(_ info:[TagPacketData]?) {
        
        if let source = self.locationSource, let lastLoc = source.getLocation() {
            self.lastKnownLoction = lastLoc
        }
        
        if info == nil {
            return
        }
        
        let sendMessageOp = BlockOperation(block: {[weak self] in
            
            #if DEBUG
            if let queue = OperationQueue.current,
               queue == OperationQueue.main {
                print("sendPacketsInfo  Called from the MainQueue")
            }
            #endif
            
            guard let weakSelf = self else {
                return
            }
            
            guard let infoToSend = info else {
                let gatewayPacketsData = GatewayPacketsData(location: weakSelf.lastKnownLoction,
                                                            packets: [TagPacketData]())
                weakSelf.tryToSendGatewayPacketsData(gatewayPacketsData)
                return
            }
            
            if weakSelf.sequenceIdCounter == kSequenceIdMax {
                weakSelf.sequenceIdCounter = 0
            }
            
            let infosWithAddedSequenceId:[TagPacketData] = infoToSend.map { input in
                
                weakSelf.sequenceIdCounter += 1
                let result:TagPacketData = input.fromOtherPacketDataWithSequenceId(weakSelf.sequenceIdCounter)
                return result
            }
            
            let gatewayPacketsData = GatewayPacketsData(location: weakSelf.lastKnownLoction, packets: infosWithAddedSequenceId)
            
            weakSelf.tryToSendGatewayPacketsData(gatewayPacketsData)
            
        })
        
        operationQueue.addOperation(sendMessageOp)
    }
    
    private func tryToSendGatewayPacketsData(_ packetsData:GatewayPacketsData) {
        
        guard gatewayAccessToken == nil else {
            return
        }
        
        guard let topicToPublish = self.getTopicString(topic: .data),
              let client = self.mqttClient else {
            logger.notice(" - No Topic or mqttClient to send packets.")
            return
        }
        
        if client.connectionState.lowercased() != "connected" {
            logger.notice("Will skip message sending: Client is not connected")
            return
        }
            
        do {
            let messageData = try GatewayDataEncoder.encode(packetsData)
            let messageString = try GatewayDataEncoder.encodeDataToString(messageData)
            
            self.queuedCalls.append  {[weak client] in
                guard let mqttClient = client, mqttClient.connectionState.lowercased() == "connected" else {
                    return
                }
                do {
                    logger.notice("actual send Payloads to topic: \(topicToPublish) Message: '\(messageString)'")
                    try mqttClient.sendMessage(messageString, topic: topicToPublish)
                }
                catch {
                    logger.warning(" tryToSendGatewayPacketsData. mqttClient  Error sending message: \(error)")
                }
            }
            
        }
        catch {
            logger.notice("\(#function) Error sending message with encoding:\(error)")
        }
    }
}


//MARK: - MQTTClientDelegate
extension MobileGatewayService:MQTTClientDelegate {
    func mqttClientDidConnect() {
        
        startMessagesTimer()
        self.gatewayAccessToken = nil
        isConnecting = false
        _statusPassThroughSubject.send("Connected")
        self.isConnected = true
        didConnectCompletion?(true)
    }
    
    func mqttClientDidDisconnect() {
        _statusPassThroughSubject.send("Disconnected")
        isConnecting = false
        self.isConnected = false
        self.isConnected = false
        self.mqttClient = nil
        didStopCompletion?()
    }
    
    func mqttClientDidEncounterError(_ error: Error) {
        #if DEBUG
        print("MobileGatewayService mqttClientDidEncounterError() Error:\(error)")
        #endif
        _statusPassThroughSubject.send("mqtt error: \(error.localizedDescription)")
        
        isConnecting = false
        self.isConnected = false
        self.isConnected = false
        
    }
}

//MARK: -
extension MQTTEndpoint {
    static var defaultEndpoint:MQTTEndpoint {
        MQTTEndpoint(host: "mqtt.us-east-2.test.wiliot.cloud",//"mqtt.us-east-2.prod.wiliot.cloud",
                     port: 1883)
    }
}
