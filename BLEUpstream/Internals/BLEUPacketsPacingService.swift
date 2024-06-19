//
//  PacketsPacingService.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 26.05.2022.
//

import Foundation
import WiliotCore


fileprivate let logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEUPacketsPacingService")

final class BLEUPacketsPacingService {
    #if DEBUG
    private static var refCount:Int = 0 {
        didSet {
            logger.notice("refCount: \(self.refCount)")
        }
    }
    #endif
    private var pacingTimer:DispatchSourceTimer?
    private(set) var packetsSender: any TagPacketsSending
    
    
    private(set) var pacingTimeoutSeconds:TimeInterval// = 10
    private lazy var packetsStore:[UUID:TagPacketData] = [:]
    private var pacingNFPKTCounterPerUUID:[UUID:Int] = [:]
    private lazy var externalTagID_to_UUIDMap:[String:[UUID]] = [:]
    var firstFireDate:Date?
    private lazy var opQueue:OperationQueue = {
        let queue = OperationQueue() //OperationQueueWithCounter(withName: "PacketsPacingService_opQueue")
        queue.name = "PacketsPacingService_opQueue"
        queue.maxConcurrentOperationCount = 1
        
        return queue
    }()
    
    init(with tagPacketsSender: any TagPacketsSending, pacingInterval:Int) {
        #if DEBUG
        Self.refCount += 1
        #endif
        
        self.pacingTimeoutSeconds = TimeInterval(pacingInterval)
        packetsSender = tagPacketsSender
        //printDebug("+ PacketsPacingService INIT -")
        startPacingWithTimeout()
    }
    
    deinit {
        //printDebug("+ PacketsPacingService Deinit +")
        cleanCache()
        stopPacingTimer()
        opQueue.cancelAllOperations()
        
        #if DEBUG
        Self.refCount -= 1
        #endif
    }
    
    /// timeout has limit 0-255 seconds. 0 timeout has no effect, the pacing will not start. Default Value is 10 seconds
    func startPacingWithTimeout(_ timeout:UInt8 = 10) {
        
        if timeout < 1 {
            return
        }
        
        if let _ = pacingTimer {
            stopPacingTimer()
        }
        
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + .seconds(Int(timeout)),
                       repeating: .seconds( Int(timeout)),
                       leeway: .milliseconds(100))
        
        timer.setEventHandler(handler:{[weak self] in self?.pacingTimerFire() })
        self.pacingTimer = timer
        timer.resume()
    }
    
    func stopPacingTimer() {
        opQueue.cancelAllOperations()
        if let timer = pacingTimer {
            timer.setEventHandler(handler: {})
            timer.cancel()
        }
        
        self.pacingTimer = nil
    }
    
    private func cleanCache() {
        packetsStore.removeAll()
        pacingNFPKTCounterPerUUID.removeAll()
    }
    
    private func pacingTimerFire() {
        opQueue.addOperation {[weak self] in
            
            guard let weakSelf = self else {
                return
            }
            
            weakSelf.clearOldPacketsIfFound()

            let packets = weakSelf.preparePacketsToSend()

            if let nonEmptyContainer = NonEmptyCollectionContainer(withArray: packets) {

                logger.notice("_Sending paced payloads (\(nonEmptyContainer.count)): \(nonEmptyContainer.array.map({$0.payload.uppercased()}).joined(separator: ", "))")
                weakSelf.packetsSender.sendPacketsInfo(nonEmptyContainer)
            }
            
            if weakSelf.firstFireDate == nil {
                weakSelf.firstFireDate = Date()
            }
        }
    }
    
    private func preparePacketsToSend() -> [TagPacketData] {
        
        let storeSnapshot:[UUID:TagPacketData] = packetsStore
        let mappingSnapshot:[String:[UUID]] = externalTagID_to_UUIDMap
        let counterNFPKSsnapshot:[UUID:Int] = pacingNFPKTCounterPerUUID
        
        let currentDate = Date()

        guard let startDate = Calendar.current.date(byAdding: .second,
                                                    value: -Int(pacingTimeoutSeconds),
                                                    to: currentDate) else {
            return []
        }
        
        
        let targetTime = startDate.millisecondsFrom1970()
        
        let filteredElements:[UUID:TagPacketData] = storeSnapshot.filter { (tagId, packet) in
            return packet.timestamp > targetTime
        }
        
        var toReturn = [TagPacketData]()
        
        var pairsByExtId:[String:[TagPacketData]] = [:]
          
        
        for (aUUID, tagPacketData) in filteredElements {
            
            let nfpktValueOrZero = counterNFPKSsnapshot[aUUID] ?? 0
            
            let lvMappingPair = mappingSnapshot.first(where: { (extTagId, uuids) in
                uuids.contains(aUUID)
            })
            
            if let mappingPair = lvMappingPair {
                
                let extTagIdKey = mappingPair.key
                
                if let existingArray = pairsByExtId[extTagIdKey] {
                    if nfpktValueOrZero > 0 {
                        var modifiedTagPacketData = tagPacketData
                        modifiedTagPacketData.nfpkt = nfpktValueOrZero
                        let newArray = existingArray + [modifiedTagPacketData]
                        pairsByExtId[extTagIdKey] = newArray
                    }
                    else {
                        let newArray = existingArray + [tagPacketData]
                        pairsByExtId[extTagIdKey] = newArray
                    }
                }
                else {
                    
                    if nfpktValueOrZero > 0 {
                        var modifiedTagPacketData = tagPacketData
                        modifiedTagPacketData.nfpkt = nfpktValueOrZero
                        pairsByExtId[extTagIdKey] = [modifiedTagPacketData]
                    }
                    else {
                        pairsByExtId[extTagIdKey] = [tagPacketData]
                    }
                }
                
            }
            else {
                // no External Tag Id for current TagPackedData
                if nfpktValueOrZero > 0 {
                    var modifiedTagPacketData = tagPacketData
                    modifiedTagPacketData.nfpkt = nfpktValueOrZero
                    toReturn.append(modifiedTagPacketData)
                }
                else {
                    toReturn.append(tagPacketData)
                }
            }
            
            //pacingNFPKTCounterPerUUID[aUUID] = nil
            pacingNFPKTCounterPerUUID.removeValue(forKey: aUUID)
        }
        
        if !pairsByExtId.isEmpty {
            
            if let unknowns = pairsByExtId["unknown"] {
                toReturn.append(contentsOf: unknowns)
            }
            
            pairsByExtId["unknown"] = nil
            
            for tagPacketDatas in pairsByExtId.values {
                
                let sortedByTimestamp = tagPacketDatas.sorted(by: {$0.timestamp < $1.timestamp})
                let latestTagPacketData = sortedByTimestamp.last
                
                if let lastTagPacket = latestTagPacketData {
                    toReturn.append(lastTagPacket)
                }
            }
        }
        
        
        return toReturn
    }
    
//    private func sendPackets(_ packets:[TagPacketData]) {
////        printDebug("PacketsPacingService sending packets Count:\(packets.count)")
//        packetsSender.sendPacketsInfo(packets)
//    }
    
    private func clearOldPacketsIfFound() {
        
        let currentDate = Date()

        guard let hourAgoDate = Calendar.current.date(byAdding: .hour, value: -1, to: currentDate) else {
            return
        }
            
        let storeSnapshot = packetsStore
        let hourAgoIntervalMSEC = hourAgoDate.millisecondsFrom1970()
        let filtered = storeSnapshot.filter { (_, tagPacket) in
            tagPacket.timestamp <= hourAgoIntervalMSEC
        }
        
        if filtered.count > 0 {
            for aKey in filtered.keys {
                packetsStore[aKey] = nil
            }
        }
        
    }
}

//MARK: - PacketsPacing
extension BLEUPacketsPacingService:PacketsPacing {
    
    func receivePacketsByUUID(_ pacingPackets:[UUID : TagPacketData]) {
        
        logger.notice("BLEUPacketsPacingService \(#function) pacingPackets Count: \(pacingPackets.count)")
        
        opQueue.addOperation {[weak self, pacingPackets] in
            guard let weakSelf = self else {
                return
            }
            for (uuid, tagPacketData) in pacingPackets {
                let currentCounter = weakSelf.pacingNFPKTCounterPerUUID[uuid] ?? 0
                
                if let existingTagPacket = weakSelf.packetsStore[uuid],
                   existingTagPacket.payload.suffix(4) == tagPacketData.payload.suffix(4) {
                    continue
                }
                
                weakSelf.packetsStore[uuid] = tagPacketData
                weakSelf.pacingNFPKTCounterPerUUID[uuid] = (currentCounter + 1)
            }
        }
        
    }
    
    func setUUIDToExternalTagIdCorrespondence(_ info:[String:UUID]) {
        
        opQueue.addOperation {[weak self] in
            guard let weakSelf = self else {
                return
            }
            for ( tagExternalId, aUUID) in info {
                if let existingUUIDs = weakSelf.externalTagID_to_UUIDMap[tagExternalId] {
                    let updatedUUIDs = existingUUIDs + [aUUID]
                    weakSelf.externalTagID_to_UUIDMap[tagExternalId] = updatedUUIDs
                }
                else {
                    weakSelf.externalTagID_to_UUIDMap[tagExternalId] = [aUUID]
                }
            }
        }
//        for ( tagExternalId, aUUID) in info {
//            if let existingUUIDs = externalTagID_to_UUIDMap[tagExternalId] {
//                let updatedUUIDs = existingUUIDs + [aUUID]
//                externalTagID_to_UUIDMap[tagExternalId] = updatedUUIDs
//            }
//            else {
//                externalTagID_to_UUIDMap[tagExternalId] = [aUUID]
//            }
//        }
    }
}
