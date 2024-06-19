//
//  BLEUPacketsCoupler.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 15.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

import WiliotCore

struct CouplingPacketKey:Hashable, Equatable {
    /// BLEPacket's uuid
    let uid:UUID
    /// 4 last bytes of the BLEPacket's data
    let suffix:String
    
    static func createFrom(blePacket:BLEPacket) -> CouplingPacketKey {
        CouplingPacketKey(uid: blePacket.uid, suffix: blePacket.packetId)
    }
}

fileprivate var logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEUPacketsCoupler")

final class BLEUPacketsCoupler {
    
    private let packetStoreLifetimeMilliseconds:Int = 3000
    private var externalLogger: (any ExternalMessageLogging)?
    let processedPacketsCallback:([TagPacketData], [BLEPacket]) -> Void
    
    init(with processingCallback: @escaping ([TagPacketData], [BLEPacket]) -> Void, externalLogger: (any ExternalMessageLogging)?) {
        self.processedPacketsCallback = processingCallback
        self.externalLogger = externalLogger
    }
    
    private var _tagBLEPacketsByCouplingKey:[CouplingPacketKey:[BLEPacket]] = [:]
    private var _sideInfoBLEPacketsByCouplingKey:[CouplingPacketKey:BLEPacket] = [:]
    
    private var _tagPacketKeysSet:Set<CouplingPacketKey> = []
    private var _sideInfoPacketKeysSet:Set<CouplingPacketKey> = []
    private var _lifetimeForCouplingKeys:[CouplingPacketKey:TimeInterval] = [:]
    
    private var _preparedCoupledPayloads:[TagPacketData] = []
    
    
 
#if DEBUG
    private var _unprocessedSuffixes:Set<String> = []
#endif
    
    private lazy var blePacketsReceivingOperationQueue = {
        let opQueue = OperationQueue()
        opQueue.name = "com.Wiliot.BLEUpstream.BLEUPacketsCoupler.operationQueue"
        opQueue.maxConcurrentOperationCount = 1
        opQueue.qualityOfService = .userInitiated
        return opQueue
    }()
    
    //MARK: - public
    func stop() {
        externalLogger?.logMessage("\(self.self) \(#function)")
        if blePacketsReceivingOperationQueue.isSuspended {
            blePacketsReceivingOperationQueue.cancelAllOperations()
            blePacketsReceivingOperationQueue.isSuspended = false
        }
        else {
            blePacketsReceivingOperationQueue.cancelAllOperations()
        }
    }
    
    func receiveBLEPacketSideInfo(_ sideInfoPacket:BLEPacket) {
        
        blePacketsReceivingOperationQueue.addBarrierBlock { [weak self, sideInfoPacket] in
            
            guard let self else { return }
            
            self.externalLogger?.logMessage("\(self.self) \(#function) blockExecution")
            
            let key:CouplingPacketKey = .createFrom(blePacket: sideInfoPacket)
            
            #if DEBUG
            if self._unprocessedSuffixes.contains(key.suffix) {
                logger.warning("WARNING: Received Meta payload for Pixel data already sent to pacing...")
            }
            #endif
            
//            logger.notice(" received Meta packet for key Suffix:\(key.suffix.uppercased()), UUID: \(key.uid.uuidString) PAYLOAD_Data: \(sideInfoPacket.data.stringHexEncodedUppercased())")
            if self._sideInfoPacketKeysSet.contains(key) {
                return
            }
            
            if self._lifetimeForCouplingKeys[key] == nil {
                self._lifetimeForCouplingKeys[key] = Date().millisecondsFrom1970()
            }
            
            self._sideInfoPacketKeysSet.insert(key)
            
            self._sideInfoBLEPacketsByCouplingKey[key] = sideInfoPacket
            
            if self._tagPacketKeysSet.contains(key) {
                self.prepareCoupledTagPacketDataForCouplingKey(key)
            }
        }
    }
    
    func receiveBLEPacketTag(_ pixelPacket:BLEPacket) {
        
        blePacketsReceivingOperationQueue.addBarrierBlock { [weak self, pixelPacket] in
            guard let self else { return }
            self.externalLogger?.logMessage("\(self.self) \(#function) blockExecution")
            let key:CouplingPacketKey = .createFrom(blePacket: pixelPacket)
            
//            logger.notice(" received Pixel packet for key Suffix:\(key.suffix.uppercased()), UUID: \(key.uid.uuidString) PAYLOAD_Data: \(pixelPacket.data.stringHexEncodedUppercased())")
            
            
            if self._tagPacketKeysSet.contains(key) {
                self.addPixelBLEPacket(pixelPacket, byKey:key)
                if self._sideInfoPacketKeysSet.contains(key) {
                    self.prepareCoupledTagPacketDataForCouplingKey(key)
                }
                return
            }
            
            if self._lifetimeForCouplingKeys[key] == nil {
                self._lifetimeForCouplingKeys[key] = Date().millisecondsFrom1970()
            }
            
            self._tagPacketKeysSet.insert(key)
            self.addPixelBLEPacket(pixelPacket, byKey:key)
            
            if self._sideInfoPacketKeysSet.contains(key) {
                self.prepareCoupledTagPacketDataForCouplingKey(key)
            }
        }
    }
        
    func processAccumulatedPackets() {
        externalLogger?.logMessage("\(self.self) \(#function)")
        let sema = DispatchSemaphore(value: 0)
        
        blePacketsReceivingOperationQueue.addBarrierBlock {[unowned self] in
            let toPacing = self.preparePacedBlePackets()
            
            self.processedPacketsCallback(self._preparedCoupledPayloads, toPacing)
            
            self._preparedCoupledPayloads.removeAll()
            sema.signal()
            
        }
        
        let result = sema.wait(timeout: .now() + 5)
        
        switch result {
        case .success:
            break
        case .timedOut:
            logger.error("Encountered a timeout processing accumulated packets")
        }
        
//        blePacketsReceivingOperationQueue.isSuspended = true
//        
//        defer {
//            blePacketsReceivingOperationQueue.isSuspended = false
//        }
        
        
        
        
    }
    
    //MARK: - private
    private func addPixelBLEPacket(_ blePacket:BLEPacket, byKey key:CouplingPacketKey) {
        externalLogger?.logMessage("\(self.self) \(#function)")
        if var existing = self._tagBLEPacketsByCouplingKey[key] {
            existing.append(blePacket)
            self._tagBLEPacketsByCouplingKey[key] = existing
        }
        else {
            self._tagBLEPacketsByCouplingKey[key] = [blePacket]
        }
    }
    
    
    private func preparePacedBlePackets() -> [BLEPacket] {
        
        externalLogger?.logMessage("\(self.self) \(#function)")
        let difference = TimeInterval(self.packetStoreLifetimeMilliseconds)
        
        let currentTimeInterval = Date().millisecondsFrom1970()
        let keysToPacing:[CouplingPacketKey] = self._lifetimeForCouplingKeys.compactMap { (key: CouplingPacketKey, value: TimeInterval) in
            if (currentTimeInterval - value) > difference {
//                logger.notice("Key to delete by timeout: \(key.suffix.uppercased())")
                return key
            }
            return nil
        }
        
        
        var toPacing:[BLEPacket] = []
        
        if !keysToPacing.isEmpty {
            
            var lvLifetimeForCoupling =  self._lifetimeForCouplingKeys
            
            keysToPacing.forEach({
                
                if let pixelBLEPackets = self._tagBLEPacketsByCouplingKey.removeValue(forKey: $0) {
                    toPacing.append(contentsOf: pixelBLEPackets)
//                    logger.notice("Sending to Pacing by key: \($0.suffix.uppercased())")
                }
                
                lvLifetimeForCoupling.removeValue(forKey: $0)
                self._tagPacketKeysSet.remove($0)
//                logger.notice("Removing side info for key: \($0.suffix.uppercased())")
                self._sideInfoPacketKeysSet.remove($0)
                self._sideInfoBLEPacketsByCouplingKey[$0] = nil
//                if let _ = self._sideInfoBLEPacketsByCouplingKey.removeValue(forKey: $0) {
//                    logger.notice("Removed side info for key: \($0.suffix.uppercased())")
//                }
                
            })
            
            self._lifetimeForCouplingKeys = lvLifetimeForCoupling
        }
        
        return toPacing
    }
    
    private func prepareCoupledTagPacketDataForCouplingKey(_ key:CouplingPacketKey)  {
        
        
//        blePacketsReceivingOperationQueue.addBarrierBlock {[weak self, key] in
            
            
            //guard let self else { return }
            
            guard let _ = self._tagBLEPacketsByCouplingKey[key], let _ = self._sideInfoBLEPacketsByCouplingKey[key] else {
                return
            }
            
//            logger.notice("\(#function) Preparing coupled data for key: \(key.suffix.uppercased()), \(key.uid.uuidString)")
            
            if let pixelPackets = self._tagBLEPacketsByCouplingKey[key], //.removeValue(forKey: key),
               let metaPacket = self._sideInfoBLEPacketsByCouplingKey[key] {
                
                self._tagPacketKeysSet.remove(key)
                self._tagBLEPacketsByCouplingKey[key] = nil
                
                var preparedTagPacketDatas = [TagPacketData]()
                if BeaconDataReader.isBeaconDataSideInfoThirdPartySensorInfo(metaPacket.data) {
                    let thirdPartyCoupled = coupleThirdPartySensorPacket(metaPacket, forTagBLEPackets: pixelPackets)
                    preparedTagPacketDatas.append(contentsOf: thirdPartyCoupled)
                }
                else {
                    pixelPackets.forEach { pxPacket in
                        let coupled = self.couple(sideInfo: metaPacket, withTag: pxPacket)
                        preparedTagPacketDatas.append(coupled)
                    }
                    
                    self._preparedCoupledPayloads.append(contentsOf: preparedTagPacketDatas)
                }
            }
//        }
    }
    
    private func couple(sideInfo:BLEPacket, withTag tag:BLEPacket) -> TagPacketData {
//        logger.notice("Coupling Meta with Tag: \(sideInfo.data.stringHexEncodedUppercased()) with \(tag.data.stringHexEncodedUppercased())")
        let payloadStr = tag.data.stringHexEncodedUppercased()
        let nfpkt:Int = BeaconDataReader.numberOfPackets(from: sideInfo.data) ?? 0
        let rssi:Int = BeaconDataReader.rssiValue(from: sideInfo.data) ?? 0
        let bridgeMACStr:String = BeaconDataReader.bridgeMacAddressFrom(sideInfoData: sideInfo.data)
        
        let coupled:TagPacketData = TagPacketData(payload: payloadStr,
                                                  timeStamp:max(tag.timeStamp, sideInfo.timeStamp),
                                                  nfpkt: nfpkt,
                                                  rssi: rssi,
                                                  bridgeId: bridgeMACStr)
        
        return coupled
    }
    
    private func coupleThirdPartySensorPacket(_ ble3rdPartyPacket:BLEPacket, forTagBLEPackets tagBLEpackets:[BLEPacket]) -> [TagPacketData] {
        logger.notice(" - \(#function) - 3rd party side packet: \(ble3rdPartyPacket.data.stringHexEncodedUppercased())")
        
        var data = ble3rdPartyPacket.data
        
        let stringHex = data.stringHexEncodedUppercased()
        if stringHex.hasPrefix("FCC60000EB") || stringHex.hasPrefix("AFFD0000EB") || stringHex.hasPrefix("FC900000EB") {
            data.removeFirst(5) //remove prefix like FCC6, AFFD, FC90 and group id 0000EB
        }
        
        //Bridge/thirdPartyDevice MAC ID
        let bridgeMACid:Data = Data(data.prefix(6))
        let bridgeMAC_ID_string = bridgeMACid.stringHexEncodedUppercased()
        data.removeFirst(6)
        
        
        // nfpkt counter
        let nfpkt2Bytes:Data = data.prefix(2)
        let nfpktValueUInt16:UInt16 = nfpkt2Bytes.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt16.self)
        }
        let nfpktValueInt = Int(nfpktValueUInt16)
        
        
        //RSSI
        var rssiFromData:Int = 0
        if let rssiUInt8Value = data.popFirst() {
            rssiFromData = Int(rssiUInt8Value) //always sending values as is (always positive numbers)
        }
        
        //not sent according to scheme
        
        //if 'globalPacingGroup' will be sent uncomment previous piece of commented code and comment out the next line
        data.removeFirst()
        
        
        //Sensor Mac ID
        let sensorMACid:Data = Data(data.prefix(6))
        let macIdString = sensorMACid.stringHexEncodedUppercased()
        data.removeFirst(6)
        
        // data.removeFirst(1) //sensor ad type
        
        //Sensor Service ID
        let sensorServiceId:Data = Data(data.prefix(3))
        let sensorServiceIdString = sensorServiceId.stringHexEncodedUppercased()
        data.removeFirst(3)
        
        data.removeLast(4) //packtid
        
        guard let lastByte:UInt8 = data.popLast() else {
            return []
        }
        //isSensor boolean
        let isSensor:Bool = ((lastByte & 0b00000001) != 0)
        let isSensorEmbedded:Bool = ((lastByte & 0b00000010) != 0)
        let isScrambled:Bool = ((lastByte & 0b00000100) != 0)
        /*
         let apiVersion:UInt8 = lastByte >> 4 //not sent according to scheme here:
         https://wiliot.atlassian.net/wiki/spaces/EDGE/pages/2881028168/External+Sensor+data+flow
         */
        
        var gluedThirdPartyPacketInfos:[TagPacketData] = []
        
        tagBLEpackets.forEach { tagBLEpacket in
            let payloadStringFromTagPacket:String = tagBLEpacket.data.stringHexEncodedUppercased()
            logger.info("Coupled 3rd patry payload: \(payloadStringFromTagPacket)")
            let gluedThirdPartyPacketInfo = TagPacketData(payload: payloadStringFromTagPacket,
                                                          timeStamp: max(tagBLEpacket.timeStamp, ble3rdPartyPacket.timeStamp),
                                                          bridgeId: bridgeMAC_ID_string,
                                                          nfpkt: nfpktValueInt,
                                                          rssi: rssiFromData,
                                                          isSensor: isSensor,
                                                          sensorServiceId: sensorServiceIdString,
                                                          sensorId: macIdString,
                                                          isScrambled: isScrambled,
                                                          isEmbedded: isSensorEmbedded)
            gluedThirdPartyPacketInfos.append(gluedThirdPartyPacketInfo)
        }
        
        return gluedThirdPartyPacketInfos
        
    }
}

