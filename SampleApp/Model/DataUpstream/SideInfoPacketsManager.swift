
import Foundation
import CoreLocation


protocol SideInfoPacketsHandling: AnyObject  {
    var locationCoordinates:CLLocationCoordinate2D? {get set}
    func receiveSideInfoPacket(_ sideInfo:BLEPacket)
    func receiveTagPacket(_ tagPacket:BLEPacket)
    func stop()
}


fileprivate let kCouplingToPacingIntervalSeconds:TimeInterval = 3

final class SideInfoPacketsManager : SideInfoPacketsHandling, BridgePayloadsReceiving {
    
    private(set) var tagPacketsSender:TagPacketsSender
    private (set) var pacingReceiver:PacketsPacing
    /// [String:BLEPacket]
    private var tagPacketsByTagSufixId:[String:[BLEPacket]] = [:]
    
    private var coupledPacketIDs:Set<String> = []

    private var isCollectingToFirstDataSourse:Bool = true
    
    private var packetsToBeSent1:[TagPacketData] = []
    private var packetsToBeSent2:[TagPacketData] = []
    
    private var bridgeMessagePackets1:[BLEPacket] = []
    private var bridgeMessagePackets2:[BLEPacket] = []
    
    var publishMessageIntervalSeconds:Int = 1
    
    var locationCoordinates: CLLocationCoordinate2D?
    
    private var messagePublishTimer:DispatchSourceTimer?
    
    private var timerQueue:DispatchQueue = DispatchQueue(label: "Timer Events queue", qos: .utility)
    private lazy var opQueue:OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.SampleAPp.SideInfoPacketsManager_opQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    init(packetsSenderAgent:TagPacketsSender, pacingReceiver:PacketsPacing) {
//        printDebug("+ SideInfoPacketsManager INIT -")
        self.tagPacketsSender = packetsSenderAgent
        self.pacingReceiver = pacingReceiver
        startSendingTimer()
    }
    
    deinit {
//        printDebug("+ SideInfoPacketsManager Deinit +")
        opQueue.cancelAllOperations()
        stopSendingTimer()
        packetsToBeSent2.removeAll()
        packetsToBeSent1.removeAll()
        bridgeMessagePackets1.removeAll()
        bridgeMessagePackets2.removeAll()
        coupledPacketIDs.removeAll()
    }
    
    //MARK: - SideInfoPacketsHandling
    func receiveSideInfoPacket(_ sideInfo:BLEPacket) {
        
        opQueue.addOperation {[weak self] in
            guard let weakSelf = self else {
                 return
            }
            
            let sideInfoSuffixId = sideInfo.packetId
            
    //        printDebug(" SideInfoPacketsManager recieved sideInfo for suffixId: \(sideInfoSuffixId)")
            
            if let tagPackets = weakSelf.tagPacketsByTagSufixId[sideInfoSuffixId] {
                if BeaconDataReader.isBeaconDataSideInfoThirdPartySensorInfo(sideInfo.data) {
                    for tagPacket in tagPackets {
                        weakSelf.handleThirdPartySensorPacket(sideInfo, forTagPacket:tagPacket)
                    }
                    return
                }
                
                let nfpkt = BeaconDataReader.numberOfPackets(from: sideInfo.data)
                let rssi = BeaconDataReader.rssiValue(from: sideInfo.data)
                let bridgeMAC = BeaconDataReader.bridgeMacAddressFrom(sideInfoData:sideInfo.data)

                var gluedCount = 0
                for aTagPacket in tagPackets {
                    let gluedTagPacket = TagPacketData(payload: aTagPacket.data.hexEncodedString(options: .upperCase),
                                                       timestamp: max(aTagPacket.timeStamp, sideInfo.timeStamp),
                                                       bridgeId: bridgeMAC,
                                                       groupId: nil,
                                                       sequenceId: nil,
                                                       nfpkt: nfpkt,
                                                       rssi: rssi)
                    
                    //tagPacketsByTagSufixId[sideInfoSuffixId] = nil
                    weakSelf.appendGluedPacketData(gluedTagPacket)
                    gluedCount += 1
                }
                
    //            printDebug(" SideInfoPacketsManager appending '\(gluedCount)' glued packets for suffixId: \(sideInfoSuffixId)")
                weakSelf.coupledPacketIDs.insert(sideInfoSuffixId)
            }
        }
        
        
    }
    
    func receiveTagPacket(_ blePacket:BLEPacket) {
//        printDebug(" SideInfoPacketsManager recieved Tag payload: \(blePacket.data.hexEncodedString(options: .upperCase)) - uuid: \(blePacket.uid.uuidString)")
        
        let tagSuffixId = blePacket.packetId
        opQueue.addOperation {[weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.addTagBLEPacketToStore(blePacket, forKey: tagSuffixId)
        }
    }
    
    func receiveBridgeMassagePayloadPacket(_ bridgeMessagePacket:BLEPacket) {
        appendBridgeMessagesPacket(bridgeMessagePacket)
    }
    
    func stop() {
//        printDebug("+ SideInfoPacketsManager stop + .")
        timerQueue.suspend()
        stopSendingTimer()
        timerQueue.resume()
        
        opQueue.cancelAllOperations()
    }
    
    private func postponeMovingToPacingAfterATimeout (_ blePacket:BLEPacket) {
        
        let tagSuffixId = blePacket.packetId
        
        DispatchQueue.global(qos:.default).asyncAfter(deadline: .now() + kCouplingToPacingIntervalSeconds) {[weak self] in
                
            guard let weakSelf = self else {
                return
            }
            
            weakSelf.opQueue.addOperation {[weak weakSelf] in
                guard let weakerSelf = weakSelf else {
                    return
                }
                weakerSelf.removeTagPacketsByTagSufixId(tagSuffixId)
            }
            
        }
    }
    
    private func addTagBLEPacketToStore(_ blePacket:BLEPacket, forKey tagSuffixId:String) {
        
        if let existingArray = tagPacketsByTagSufixId[tagSuffixId] {
            tagPacketsByTagSufixId[tagSuffixId] = existingArray + [blePacket]
        }
        else {
            tagPacketsByTagSufixId[tagSuffixId] = [blePacket]
        }
        
        postponeMovingToPacingAfterATimeout(blePacket)
    }
    
    private func removeTagPacketsByTagSufixId(_ tagSuffixId:String) {
        guard let blePackets = tagPacketsByTagSufixId[tagSuffixId] else {
            return
        }
        
//        printDebug("SideInfoPacketsManager removeTagPackets handling after 3 seconds payload with suffixId: \(tagSuffixId)")
        
        guard !coupledPacketIDs.contains(tagSuffixId) else {
            
            tagPacketsByTagSufixId.removeValue(forKey: tagSuffixId)
            coupledPacketIDs.remove(tagSuffixId)
            
            return
        }
        
//        printDebug("SideInfoPacketsManager removeTagPackets sending to Pacing  payload with suffixId: \(tagSuffixId)")
        //send to pacing if not coupled during 'kCouplingToPacingIntervalMilliseconds' (3 seconds)
        
        var toSendToPacing:[UUID:TagPacketData] = [:]
        
        blePackets.forEach { aBlePacket in
            let tagPacket = TagPacketData(payload: aBlePacket.data.hexEncodedString(options: .upperCase),
                                          timestamp: aBlePacket.timeStamp,
                                          rssi: aBlePacket.rssi)
            toSendToPacing[aBlePacket.uid] = tagPacket
        
        }
        
        if !toSendToPacing.isEmpty {
            pacingReceiver.receivePacketsByUUID(toSendToPacing)
        }
        
        tagPacketsByTagSufixId.removeValue(forKey: tagSuffixId)
        coupledPacketIDs.remove(tagSuffixId)
    }
    
    private func handleThirdPartySensorPacket(_ ble3rdPartyPacket:BLEPacket, forTagPacket tagBLEpacket:BLEPacket) {
        var data = ble3rdPartyPacket.data
        
        data.removeLast(4) //packet id
        data.removeLast(1) //isSensor boolean
        data.removeLast(3) //empty bytes
        
        //RSSI
        var rssiFromData:Int = 0
        if let rssiUInt8Value = data.popLast() {
            rssiFromData = Int(rssiUInt8Value) //always sending values as is (always positive numbers)
        }
//        if let rssiUInt8Value = data.popLast() {
//            //UInt8 stores values from 0 to 255. we need possible negative RSSI value like in Int8 - (from -128 to 127) - indeed -127 -> +127
//            rssiFromData = Int(rssiUInt8Value.signedInt8Value)
//        }
        
        //Sensor ID
        let sensorMACid:Data = Data(data.suffix(6))
        let macIdString = sensorMACid.hexEncodedString(options: .upperCase)
        data.removeLast(6)
        
        //Sensor Service ID
        let sensorServiceId:Data = Data(data.suffix(3))
        let sensorServiceIdString = sensorServiceId.hexEncodedString(options: .upperCase)
        data.removeLast(3)
        
        //Bridge/thirdPartyDevice MAC ID
        let bridgeMACid = Data(data.suffix(6))
        let bridgeMAC_ID_string = bridgeMACid.hexEncodedString(options: .upperCase)
        
        let payloadStringFromTagPacket = tagBLEpacket.data.hexEncodedString(options: .upperCase)
        
        let gluedThirdPartyPacketInfo = TagPacketData(payload: payloadStringFromTagPacket,
                                                      timestamp: max(tagBLEpacket.timeStamp, ble3rdPartyPacket.timeStamp),
                                                      bridgeId: bridgeMAC_ID_string,
                                                      groupId: nil,
                                                      sequenceId: nil,
                                                      nfpkt: nil,
                                                      rssi: rssiFromData,
                                                      isSensor: true,
                                                      sensorServiceId: sensorServiceIdString,
                                                      sensorId: macIdString)
        
        appendGluedPacketData(gluedThirdPartyPacketInfo)
        
    }
    
    private func appendGluedPacketData(_ tpsPacketData:TagPacketData) {
        if isCollectingToFirstDataSourse {
            packetsToBeSent1.append(tpsPacketData)
        }
        else {
            packetsToBeSent2.append(tpsPacketData)
        }
    }
    
    private func appendBridgeMessagesPacket(_ blePacket:BLEPacket) {
        if isCollectingToFirstDataSourse {
            bridgeMessagePackets1.append(blePacket)
        }
        else {
            bridgeMessagePackets2.append(blePacket)
        }
    }
    
    
    private func clearCurrentCollectingDataSource() {
        if isCollectingToFirstDataSourse {
            packetsToBeSent1.removeAll()
            bridgeMessagePackets1.removeAll(keepingCapacity: true)
        }
        else {
            packetsToBeSent2.removeAll()
            bridgeMessagePackets2.removeAll(keepingCapacity: true)
        }
        
    }
    
    private var activeCollectingDataSource:[TagPacketData] {
        isCollectingToFirstDataSourse ? packetsToBeSent1 : packetsToBeSent2
        
    }
    
    private var activeBridgeMessagePackets:[BLEPacket] {
        isCollectingToFirstDataSourse ? bridgeMessagePackets1 : bridgeMessagePackets2
    }
    
    private func startSendingTimer() {
//        printDebug(" + SideInfoPacketsManager startTimer")
        let timer :DispatchSourceTimer = DispatchSource.makeTimerSource()//flags: [], queue: timerQueue)
        timer.schedule(deadline: .now() + .milliseconds(1000 * publishMessageIntervalSeconds + 100),
                       repeating: .milliseconds(1000 * publishMessageIntervalSeconds + 100),
                       leeway: .milliseconds(100))
        
        timer.setEventHandler(handler:{[weak self] in
            guard let weakSelf = self else { return }
            weakSelf.sendMessageTimerFire()
        })
        self.messagePublishTimer = timer
       // timer.resume()
        timer.activate()
    }
    
    private func stopSendingTimer() {
//        printDebug(" + SideInfoPacketsManager stopTimer")
        if let timer = messagePublishTimer, !timer.isCancelled {
            timer.setEventHandler(handler: {})
            timer.cancel()
        }
        messagePublishTimer = nil
    }
    
    private func sendMessageTimerFire() {
        
        opQueue.addOperation {[weak self] in
            guard let weakSelf = self else {
                return
            }
            
            let activeDataSourceSnapshot = weakSelf.activeCollectingDataSource
            let bridgeMessagesSnapshot = weakSelf.activeBridgeMessagePackets
            
            if activeDataSourceSnapshot.isEmpty && bridgeMessagesSnapshot.isEmpty {
                return
            }
            
            weakSelf.clearCurrentCollectingDataSource()
            
            weakSelf.isCollectingToFirstDataSourse.toggle()
            
            let bridgePayloads:[TagPacketData] = bridgeMessagesSnapshot.map { blePacket in
                TagPacketData(payload: blePacket.data.hexEncodedString(options: .upperCase),
                              timestamp: blePacket.timeStamp,
                              rssi: blePacket.rssi)
            }
            
            let combinedArrayOfTagsAndBridgeMessages = activeDataSourceSnapshot + bridgePayloads
            
            weakSelf.tagPacketsSender.sendPacketsInfo(combinedArrayOfTagsAndBridgeMessages)
        }
    }
}


extension UInt8 {
    var signedInt8Value:Int8 {
        
        if self == UInt8.max {
            return 0
        }
        
        if self <= Int8.max {
            #if DEBUG
            print(" * UInt8 * *signedInt8Value* returning initial value: '\(self)'")
            #endif
            return Int8(self)
        }
        
        let nsNumber = NSNumber(value: UInt32(self))
        
        let int8Value = nsNumber.int8Value
        
        return int8Value
    }
}
