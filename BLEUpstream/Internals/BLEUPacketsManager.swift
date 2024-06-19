//
//  BLEJudgeBuffer.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 05.07.2022.
//

import Foundation
import CoreLocation

import WiliotCore

fileprivate let logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEUPacketsManager")

final class BLEUPacketsManager {
    
    #if DEBUG
    fileprivate static var refCount:Int = 0 {
        didSet {
            logger.notice("refCount: \(self.refCount)")
        }
    }
    
    #endif
    
    
    private var externalLogger: (any ExternalMessageLogging)?
    private(set) var tagPacketsSender: any TagPacketsSending
    private(set) var pacedPacketsReceiver: (any PacketsPacing)?
    private lazy var packetsCoupler:BLEUPacketsCoupler = BLEUPacketsCoupler(with: { [unowned self] processedTagPacketDatas, unprocessedBLEPackets in
        
        if !processedTagPacketDatas.isEmpty {
            self.appendPreparedPacketDatas(processedTagPacketDatas)
        }
        
        if !unprocessedBLEPackets.isEmpty, let pacingReceiver = self.pacedPacketsReceiver {
            var toPacing = [UUID:TagPacketData]()
            
            for blePacket in unprocessedBLEPackets {
                let hexString = blePacket.data.stringHexEncodedUppercased()
                toPacing[blePacket.uid] = TagPacketData(payload: hexString,
                                                        timeStamp: blePacket.timeStamp,
                                                        rssi: blePacket.rssi)
            }
            
            pacingReceiver.receivePacketsByUUID(toPacing)
        }
          
    }, externalLogger: self.externalLogger)
  
    private var preparedPacketsToBeSent:[TagPacketData] = []
    
    var publishMessageIntervalSeconds:Int = 1
    
    private(set) var locationCoordinates: CLLocationCoordinate2D?
    
    private var messagePublishTimer:DispatchSourceTimer?
    
    private var timerQueue:DispatchQueue = DispatchQueue(label: "Timer Events queue", qos: .utility)
    
    let setHandlngQueue:DispatchQueue = DispatchQueue(label: "com.wiliot.BLEUPacketsManager.setHandlingQueue", qos:.default, attributes: .concurrent)
    
    private lazy var opQueue:OperationQueue = {
        let queue = OperationQueue()
        queue.name = "BLEUPacketsManager_opQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    private lazy var workerDispatchQueue:DispatchQueue = {
        DispatchQueue(label: "BLEUPacketsManager.workerQueue", qos: .default)//, attributes: .concurrent)
    }()
    
    private var pendingWorkItems:[Date:DispatchWorkItem] = [:]
    private var pendingWorkItemsQueue:DispatchQueue = DispatchQueue(label: "com.wiliot.BLEUpstream.BLEUPacketsManager", attributes: DispatchQueue.Attributes.concurrent)
    //MARK: -
    
    init(packetsSenderAgent: any TagPacketsSending, pacedPacketsReceiver: (any PacketsPacing)? , externalLogger: (any ExternalMessageLogging)?) { //}, pacingReceiver: any PacketsPacing) {

        #if DEBUG
        Self.refCount += 1
        #endif
        
        self.tagPacketsSender = packetsSenderAgent
        self.pacedPacketsReceiver = pacedPacketsReceiver
        self.externalLogger = externalLogger
    }
    
    //MARK: Deinit
    deinit {

        #if DEBUG
        Self.refCount -= 1
        #endif
        
        opQueue.cancelAllOperations()
        stopSendingTimer()

        preparedPacketsToBeSent.removeAll()
    }
    
    //MARK: - SideInfoPacketsHandling
    
    func setLocationCoordinates(_ coord: CLLocationCoordinate2D?) {
        self.locationCoordinates = coord
    }
  
    func start() throws {
        try startSendingTimer()
    }
    
    func stop() {
        logger.notice(#function)
        
        timerQueue.suspend()
        stopSendingTimer()
        timerQueue.resume()
        
        opQueue.cancelAllOperations()

        preparedPacketsToBeSent.removeAll()
        packetsCoupler.stop()
        logger.notice("\(#function) pending tasks: \(self.pendingWorkItems.count)")
        
        pendingWorkItemsQueue.async(flags: .barrier) {[weak self] in
            guard let self else { return }
            
            logger.notice("\(#function) cancelling pendingWorkItems tasks")
            
            self.pendingWorkItems.indices.forEach { index in
                self.pendingWorkItems[index].value.cancel()
            }
            
            self.pendingWorkItems.removeAll()
        }
        
    }
    
//    private func postponeDeletingSideInfoAfterTimeout (_ key:CouplingPacketKey) {
//
//        let date = Date()
//        
//        let workItem = DispatchWorkItem(block: {[weak self, key, date] in
//            guard let self else { return }
//
//            pendingWorkItemsQueue.async(flags: .barrier) {[weak self, date] in
//                guard let self else { return }
//                self.pendingWorkItems.removeValue(forKey: date)
//            }
//            
//        })
//        
//        
//        pendingWorkItemsQueue.async(flags: .barrier) {[weak self] in
//            self?.pendingWorkItems[date] = workItem
//        }
//        
//        workerDispatchQueue.asyncAfter(deadline: .now() + .milliseconds(packetStoreLifetimeMilliseconds), execute: workItem)
//        
//    }
    
//    private func postponeRemovingTagBLEPacketAfterTimeout (_ key:CouplingPacketKey) {
//        //logger.notice("\(#function) '\(key.uid.uuidString)_\(key.suffix)'")
//        let date = Date()
//        let workItem:DispatchWorkItem = DispatchWorkItem(block: {[weak self, key, date] in
//            guard let self else { return }
////            logger.notice("\(#function) '\(key.uid.uuidString)_\(key.suffix)'")
//            
//            self.pendingWorkItemsQueue.async(flags: .barrier) {[weak self, date] in
//                guard let self else { return }
//                self.pendingWorkItems.removeValue(forKey: date)
//            }
//        })
//        
//        
//        self.pendingWorkItemsQueue.async(flags: .barrier) {[weak self, date] in
//            guard let self else { return }
//            self.pendingWorkItems[date] = workItem
//        }
//        
//        workerDispatchQueue.asyncAfter(deadline: .now() + .milliseconds(packetStoreLifetimeMilliseconds), execute: workItem)
//    }
    
//    private func addBridgeBLEPacketToStore(_ blePacket:BLEPacket) {
//
//        //let bridgeMac:String = BeaconDataReader.bridgeMacAddressFrom(sideInfoData: blePacket.data)
//        
//        //logger.notice("Adding SideInfo to be sent: \(blePacket.data.hexEncodedString(options: .upperCase))")
//        
//        let bridgeSideInfoAsTagPacket:TagPacketData = TagPacketData(payload: blePacket.data.stringHexEncodedUppercased(),
//                                                                    timeStamp: blePacket.timeStamp,
//                                                                    rssi: blePacket.rssi)
//    }
    
    private func addBridgeCombinedPacketToStore(_ combinedBlePacket:BLEPacket) {
        let uuidString = combinedBlePacket.uid.uuidString
        //logger.notice("Combined Packet with UUID: \(uuidString)")
        let combinedWithUUID:TagPacketData = TagPacketData(payload: combinedBlePacket.data.stringHexEncodedUppercased(),
                                                                    timeStamp: combinedBlePacket.timeStamp,
                                                                    rssi: combinedBlePacket.rssi,
                                                                    aliasBridgeId: uuidString)
        
        self.appendPreparedPacketDatas([combinedWithUUID])
    }
  
    private func appendBridgeMessagesPacket(_ blePacket:BLEPacket) {
        
        let tagPacketData:TagPacketData
        
//       // #WMB-1460  adding alias bridge ID for Heart_beat packets
//        if blePacket.isHeartbeatPacket(), blePacket.firmwareAPIversionFromHeartbeat() >= 7 {
//            logger.notice("sending bridge message with payload: \(blePacket.data.stringHexEncodedUppercased()) and alias: \(blePacket.uid.uuidString)")
            tagPacketData = TagPacketData(payload: blePacket.data.stringHexEncodedUppercased(),
                                             timeStamp: blePacket.timeStamp,
                                             rssi: blePacket.rssi,
                                             aliasBridgeId: blePacket.uid.uuidString)
//        }
//        else {
//            //logger.notice("sending bridge message with payload: \(blePacket.data.stringHexEncodedUppercased())")
//            tagPacketData  = TagPacketData(payload: blePacket.data.stringHexEncodedUppercased(),
//                                             timeStamp: blePacket.timeStamp,
//                                             rssi: blePacket.rssi)
//        }
         
        
        
        appendPreparedPacketDatas([tagPacketData])
    }
    
    //MARK: -
    private func appendPreparedPacketDatas(_ tpsPacketDatas:[TagPacketData]) {
        precondition(!tpsPacketDatas.isEmpty, "tried to append empty array of TagPacketData")
        self.preparedPacketsToBeSent.append(contentsOf: tpsPacketDatas)
    }
    
    //MARK: - Timer
    private func startSendingTimer() throws {
        
        guard self.messagePublishTimer == nil else {
            throw ValueReadingError.invalidValue("Previous timer is present")
        }
        
        let timer:DispatchSourceTimer = DispatchSource.makeTimerSource()//flags: [], queue: timerQueue)
        timer.schedule(deadline: .now() + .milliseconds(1000 * publishMessageIntervalSeconds + 100), //1100milliseconds
                       repeating: .milliseconds(1000 * publishMessageIntervalSeconds + 100),
                       leeway: .milliseconds(100))
        self.messagePublishTimer = timer
        
        timer.setEventHandler(handler:{[weak self] in
            guard let weakSelf = self else { return }
            weakSelf.sendMessageTimerFire()
        })
    
        timer.activate()
    }
    
    private func stopSendingTimer() {

        if let timer = messagePublishTimer, !timer.isCancelled {
            timer.setEventHandler(handler: {})
            timer.cancel()
        }
        messagePublishTimer = nil
    }
    
    private func sendMessageTimerFire() {

        self.packetsCoupler.processAccumulatedPackets()
        
        let activeDataSourceSnapshot:[TagPacketData] = self.preparedPacketsToBeSent
        
        if activeDataSourceSnapshot.isEmpty {
            return
        }
        
        opQueue.addOperation {[weak self, activeDataSourceSnapshot] in
            guard let self else {
                return
            }
            
            let nonEmptyArrayContainer:NonEmptyCollectionContainer<[TagPacketData]>? =
                    NonEmptyCollectionContainer(withArray: activeDataSourceSnapshot)
            
            if let container = nonEmptyArrayContainer {
                self.tagPacketsSender.sendPacketsInfo(container)
            }
            
            self.preparedPacketsToBeSent.removeAll()
        }
    }
    
    
    
    
}


//MARK: - TagPacketsReceiving

extension BLEUPacketsManager: TagPacketsReceiving {
    func receiveTagPacket(_ blePacket:BLEPacket) {
        self.packetsCoupler.receiveBLEPacketTag(blePacket)
    }
}

//MARK: - ThirdPartyPacketsReceiving
extension BLEUPacketsManager: ThirdPartyPacketsReceiving {
    func receiveThirdPartyDataPacket(_ thirdPartyDataPacket: BLEPacket) {
        self.packetsCoupler.receiveBLEPacketTag(thirdPartyDataPacket)
    }
}

//MARK: - SideInfoPacketsReceiving
extension BLEUPacketsManager: SideInfoPacketsReceiving {
    
    func receiveSideInfoPacket(_ sideInfo:BLEPacket) {
        self.packetsCoupler.receiveBLEPacketSideInfo(sideInfo)
    }
}

//MARK: - BridgePayloadsReceiving
extension BLEUPacketsManager: BridgePayloadsReceiving {
    
    func receiveBridgeMessagePayloadPacket(_ bridgeMessagePacket:BLEPacket) {
        self.appendBridgeMessagesPacket(bridgeMessagePacket)
    }
}

//MARK: - CombinedPacketsReceiving
extension BLEUPacketsManager: CombinedPacketsReceiving {
        
    func receiveCombinedPacket(_ combinedPacket: BLEPacket) {
        
        opQueue.addOperation({[weak self, combinedPacket] in
            guard let self else { return }
            self.addBridgeCombinedPacketToStore(combinedPacket)
        })
    }
}


