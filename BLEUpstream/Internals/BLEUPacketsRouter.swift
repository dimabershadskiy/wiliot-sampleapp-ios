//
//  BLEPacketsManager.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 20.05.2022.
//

import Foundation
import Combine


fileprivate var logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEUPacketsRouter")


import WiliotCore

final class BLEUPacketsRouter {
    
    private var externalPixelsRSSIUpdater: (any ExternalPixelRSSIUpdatesReceiver)?
    private var externalResolvedPacketsInfoReceiver: (any ExternalResolvedPacketReceiver)?
    private var externalBridgesPacketsReceiver: (any ExternalBridgePacketsReceiver)?
    private var externalPixelPacketsResolver: (any ExternalPixelResolver)?
    
    private var coordinatesContainer: any LocationCoordinatesContainer
    
//    var pacingReceiver:PacketsPacing?
    let tagPacketsReceiver: any TagPacketsReceiving
    let sideInfoPacketsReceiver: any SideInfoPacketsReceiving
    let combinedPacketsReceiver: any CombinedPacketsReceiving
    let bridgeMessagePacketsReceiver: any BridgePayloadsReceiving
    let thirdPartyDataPacketsReceiver: any ThirdPartyPacketsReceiving
    
    private lazy var cancellables = Set<AnyCancellable>()
    private lazy var resolveTagCancellables = [UUID:AnyCancellable]()
//    private lazy var accelerationService:MotionAccelerationService = {
//        let service = MotionAccelerationService(accelerationUpdateInterval: 1.0)
//        return service
//    }()
    
    
    
    
//    private lazy var retransmittedPackets:[UUID:TagPacket] = [:]
    
    
    private lazy var resolvedPackets:[UUID:ResolvedPacket] = [:]
    
    private lazy var blePacketUUIDsToSkipResolving:Set<UUID> = []
    
    private lazy var blePacketsByUUID:[UUID:BLEPacket] = [:]
    
    private lazy var pendingResolvedTagIDEndings = Set<String>()
    private lazy var pendingResolvedUIDS = Set<UUID>()
    
    private var resolvedPacketsResponseQueue = DispatchQueue(label: "com.Wiliot.ResolveResponseListrning")
    
    private var isCleaningAfterClaim:Bool = false
    private var cleanClaimingQueue:DispatchQueue?
    private var tagPayloadsReceiver:TagPayloadByUUIDReceiver?
    
    //MARK: -
    init(routerConfiguration config:BLEUPacketsRouterConfiguration) {
            
        self.coordinatesContainer = config.coordinatesContainer
            
        self.externalPixelsRSSIUpdater = config.externatOutputs.pixelsRSSIUpdater
        self.externalResolvedPacketsInfoReceiver = config.externatOutputs.resolvedPacketsInfoReceiver
        self.externalPixelPacketsResolver = config.externatOutputs.blePixelResolver
        self.externalBridgesPacketsReceiver = config.externatOutputs.bridgesUpdater
        
        
        self.tagPacketsReceiver = config.tagPacketsReceiver
        self.combinedPacketsReceiver = config.combinedPacketsReceiver
        self.sideInfoPacketsReceiver = config.sideInfoPacketsReceiver
        self.bridgeMessagePacketsReceiver = config.bridgeMessagesPacketsReceiver
        self.thirdPartyDataPacketsReceiver = config.thirdPartyDataPacketsReceiver
        
        if let sender = config.tagPacketsLogsSender {
            let loggingService = BLEUTagPacketsPayloadsLogService(logsSender: sender)
            self.tagPayloadsReceiver = loggingService
            loggingService.startHandlingPayloads()
        }
        
    }
    
    //MARK: Deinit
    
    func setTagsPayloadsLogsSender(_ sender:TagPacketsPayloadLogSender?) {
        guard let sender else {
            self.tagPayloadsReceiver?.stopHandlihgPayloads()
            self.tagPayloadsReceiver = nil
            return
        }
        
        let loggingService = BLEUTagPacketsPayloadsLogService(logsSender: sender)
        self.tagPayloadsReceiver = loggingService
        loggingService.startHandlingPayloads()
    }
    
    //MARK: -
    func subscribeToBLEpacketsFrom(publisher:AnyPublisher<BLEPacket,Never>) {
        publisher.sink {[weak self] packet in
            self?.handleBLEPacket(packet)
        }.store(in: &cancellables)
    }
     
    //MARK: - Handling BLE
    private func handleBLEPacket(_ blePacket:BLEPacket) {
        let data:Data = blePacket.data
        
        if BeaconDataReader.isBeaconDataGWtoBridgeMessage(data) {
            return
        }
        
        if isCleaningAfterClaim {
            //printDebug(" +++ Ignoring BLEPacket -> isCleaningAfterClaim")
            return
        }
        
        if BeaconDataReader.isBeaconDataBridgeToGWmessage(data) {
            self.handleBridgeCommandPacket(blePacket)
        }
        else if BeaconDataReader.isBeaconDataCombinedPacket(data) {
            self.handleCombinedBridgePacket(blePacket) //BLEPacketsManager
        }
        else if BeaconDataReader.isBeaconDataSideInfoPacket(data) {
            self.sideInfoPacketsReceiver.receiveSideInfoPacket(blePacket) //BLEPacketsManager
        }
        else if BeaconDataReader.isBeaconDataThirdPartyDataPayload(data) {
            self.handleTrirdPartyDataPacket(blePacket)
        }
        else {
            self.handlePixelPacket(blePacket)
        }
    }
    
    
    private func handleBridgeCommandPacket(_ packet:BLEPacket) {
        //bridge to gateway command packets (e.g. config containing packet)
        bridgeMessagePacketsReceiver.receiveBridgeMessagePayloadPacket(packet) //BLEPacketsManager
        
        guard let externalReceiver = externalBridgesPacketsReceiver else {
            return
        }
        
        if packet.isHeartbeatPacket() {
            logger.info("Heartbeat packet from data: \(packet.data.stringHexEncodedUppercased())")
            let sourceMAC = packet.data.subdata(in: 8..<14).stringHexEncodedUppercased()
            let uid = packet.uid
            let container = UUIDWithIdContainer(id: sourceMAC, uuid: uid)
            
            externalReceiver.receiveBridgePackets([container])
        }
        else if packet.is_ModuleIFV_Packet() {
            
            //WMB-1465 task
            let sourceMAC = packet.data.subdata(in: 8..<14).stringHexEncodedUppercased()
            let uid = packet.uid
            let container = UUIDWithIdContainer(id: sourceMAC, uuid: uid)
            
            externalReceiver.receiveBridgePackets([container])
        }
    }
    
    private func handleCombinedBridgePacket(_ packet:BLEPacket) {
//        #if DEBUG
//        logger.notice("\(#function) -> \(packet.data.stringHexEncodedUppercased())")
//        #endif
        
        self.combinedPacketsReceiver.receiveCombinedPacket(packet)
    }
    
    private func handleTrirdPartyDataPacket(_ packet:BLEPacket) {
        self.thirdPartyDataPacketsReceiver.receiveThirdPartyDataPacket(packet)
    }
    
    private func handlePixelPacket(_ blePacket:BLEPacket, isReResolving:Bool = false) {
        
        //logger.notice("\(#function) \(blePacket.uid.uuidString), payload: \(blePacket.data.stringHexEncodedUppercased())")
        
        //var directlyToInternalPacing = false
        
//        let first2Bytes = blePacket.data.subdata(in: 0..<2)
        
//        if first2Bytes == Data([UInt8(0xAF), UInt8(0xFD)]) || first2Bytes == Data([UInt8(0xFC), UInt8(0xC6)])  {
            self.tagPacketsReceiver.receiveTagPacket(blePacket)
//        }
//        else {
//            directlyToInternalPacing = true
//        }
        
        blePacketsByUUID[blePacket.uid] = blePacket
        
//        let accelerationData = self.accelerationService.currentAcceleration
        var location:WLTLocation?
        if let clCoord = self.coordinatesContainer.currentLocationCoordinates {
            location = WLTLocation(coordinate: clCoord)
        }
        
        let payloadStr:String = blePacket.data.stringHexEncodedUppercased()
        let bleUUID:UUID = blePacket.uid
        let bleRSSI:Int = blePacket.rssi
        
        
//        if directlyToInternalPacing {
//            pacingReceiver?.receivePacketsByUUID([bleUUID : packet])
            //log service. can be disabled
//            tagPayloadsReceiver?.receiveTagPayloadsByUUID([bleUUID : payloadStr]) //log service if needed
//        }
        
        
        
        if isCleaningAfterClaim {
            return
        }
        
        if pendingResolvedTagIDEndings.contains(blePacket.packetId) {
            return
        }
        else if pendingResolvedUIDS.contains(bleUUID) {
            if let updater = self.externalPixelsRSSIUpdater, let resolvedInfo = self.resolvedPackets[bleUUID], resolvedInfo.externalId.hasSuffix("registered") {
//                logger.notice("Updating counter while resolve pending  from uuid: \(bleUUID.uuidString) as sufix: \(resolvedInfo.externalId)")
                updater.receivePixelPacketRSSI(blePacket.rssi, forTagExtId: resolvedInfo.externalId)
            }
            return
        }
        else if blePacketUUIDsToSkipResolving.contains(bleUUID) {
//            logger.warning("Encountered BLE transmission of the pixel which is forbidden to be resolved. Skipping resolving. UUID: \(bleUUID.uuidString), Payload: \(payloadStr)")
            return
        }
        
        if !isReResolving, let updater = self.externalPixelsRSSIUpdater, let resolvedInfo = self.resolvedPackets[bleUUID] {
            //only update the latest pixel's RSSI value
//            logger.notice("Updating counter from uuid: \(bleUUID.uuidString) as sufix: \(resolvedInfo.externalId)")
            updater.receivePixelPacketRSSI(blePacket.rssi, forTagExtId: resolvedInfo.externalId)
            return
        }
        
        
        guard let externalPixelPacketsResolver else {
            return
        }
        
        let pendingPacketId = blePacket.packetId
        pendingResolvedUIDS.insert(bleUUID)
        pendingResolvedTagIDEndings.insert(pendingPacketId)
        
        
        if isReResolving {
            logger.notice(" -+ BLEPacketsmanager Re-Resolving...")
        }
        
        let container:PayloadContainer = .init(payload: payloadStr, timestamp:blePacket.timeStamp)
        
        do {
            let info:ResolveInfo = try ResolveInfo.defaultWith(payloads:[container], location:location)
            let shortTimeUUUID = UUID()
            
//            logger.notice("Sending To Resolve: \(payloadStr.uppercased()) from uuid: \(bleUUID.uuidString)")
            
            let publisher = externalPixelPacketsResolver.resolve(info: info)
            
            let cancellable = publisher
                .subscribe(on: resolvedPacketsResponseQueue)
                .receive(on: resolvedPacketsResponseQueue)
                .sink {[weak self, bleUUID] completion in
                //cleanup memory after request finishes
                    guard let weakSelf = self else {
                        return
                    }
                    
                    weakSelf.pendingResolvedUIDS.remove(bleUUID)
                    weakSelf.pendingResolvedTagIDEndings.remove(pendingPacketId)
                switch completion {
                    case.failure(let error):
                    if let pxError = error as? PixelResolverError {
                        switch pxError {
                        case .badStatusCode(let statusCode):
                            logger.warning("Received bad resolve response: Code: \(statusCode)")
                        case .badStatusCodeWithMessage(let statusCode, let message):
                            logger.warning("Received bad resolve response: Code: \(statusCode), message: \(message)")
                        case .resolveDenied:
                            logger.warning("Received 400 response for uuid: \(bleUUID.uuidString), payload: \(payloadStr)")
                            weakSelf.blePacketUUIDsToSkipResolving.insert(bleUUID)
                        @unknown default:
                            break
                        }
                    }
                        break
                    case .finished:
                        break
                }
                    
                weakSelf.resolveTagCancellables[shortTimeUUUID] = nil
                    
            } receiveValue: {[weak self, bleRSSI] resolvedPacket in
                
                guard let weakSelf = self else {
                    return
                }
                
                weakSelf.handleResolvedPacket(resolvedPacket,
                                           withUID: bleUUID,
                                              forSourceInfoRSSI: bleRSSI)
                
                
                weakSelf.pendingResolvedUIDS.remove(bleUUID)
                weakSelf.pendingResolvedTagIDEndings.remove(pendingPacketId)
                weakSelf.resolveTagCancellables[shortTimeUUUID] = nil
                
            }
            
            resolveTagCancellables[shortTimeUUUID] = cancellable //store while network request is in progresss
        }
        catch {
            logger.warning("Failed to create ResolveInfo: \(error)")
        }
        
        
        

    }
    
    private func handleResolvedPacket(_ resolvedPacket:ResolvedPacket, withUID uuid:UUID, forSourceInfoRSSI  sourceInfoRSSI:Int) {
        
        self.resolvedPackets[uuid] = resolvedPacket
        
//        if resolvedPacket.externalId.hasSuffix("registered") {
//            logger.notice("Not Registered from uuid: \(uuid.uuidString)")
//        }
        
        self.externalPixelsRSSIUpdater?.receivePixelPacketRSSI(sourceInfoRSSI, forTagExtId: resolvedPacket.externalId)
        self.externalResolvedPacketsInfoReceiver?.receiveResolvedPacketInfo(resolvedPacket)
    }
            
}
