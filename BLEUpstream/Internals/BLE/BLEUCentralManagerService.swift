//
//  BLEService.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 20.05.2022.
//

import Foundation
import CoreBluetooth
import Combine

import WiliotCore  //BLEPacket, BeaconDataReader are there

fileprivate let kCentralManagerUIDString = "com.wiliot.BLEcentralManager.uid"
fileprivate let kConnectableStateBridgeTimeoutSeconds:Int = 32

fileprivate let kRepeatingPacketTimeout:TimeInterval = 300 //3000
fileprivate let kRepeatingPixelPacketTimeout:TimeInterval = 300 //3000

let kServiceUUIDString = "AFFD"
let kBridgePayloadsUUIDString = "FCC6"
let kThirdPartySensorPacketServicUUIDString = "FC90"

fileprivate var logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEUCentralManagerService")

final class BLEUCentralManagerService {
    
    var blePacketsPublisher:AnyPublisher<BLEPacket, Never> {
        _packetPublisher.eraseToAnyPublisher()
    }
    var connectableBridgeIdPublisher:AnyPublisher<String,Never> {
        return _connectableBridgesPassThrough.eraseToAnyPublisher()
    }
    var scanStatePublisher:AnyPublisher<BLEUScanState, Never> {
        return _scanStatePublisher.eraseToAnyPublisher()
    }
    var isBLEScanningPublisher:AnyPublisher<Bool, Never> {
        return _isBLEScanningPublisher.eraseToAnyPublisher()
    }
    var isBLEScanning:Bool = false
    
    private struct K {
        static let eddystoneServiceuid = "FEAA"
        static let wiliotManufactureID = "0500"
        static let serviceDataKey = "kCBAdvDataServiceData"
        static let manufacturerDataKey = "kCBAdvDataManufacturerData"
        static let wiliotServiceuid = "FDAF"
        static let embeddedGatewayServiceUID = kServiceUUIDString //"AFFD"
        static let wiliotBridgeServicUUID = kBridgePayloadsUUIDString //FCC6
        static let thirdPartyServiceUUID = kThirdPartySensorPacketServicUUIDString //FC90
        static let d2p22UID = "05AF"
        static let connectableModeBridgeUUID = "180A"
    }
    
    private struct CBUUIDS {
        static let wiliotCBUUID = CBUUID(string: K.wiliotServiceuid)
        static let wiliotEmbeddedGWCBUUID = CBUUID(string: K.embeddedGatewayServiceUID)
        static let wiliotBridgeCBUUID = CBUUID(string: K.wiliotBridgeServicUUID)
        static let wiliotThirdPartyServiceCBUUID = CBUUID(string: K.thirdPartyServiceUUID)
        static let eddystoneCBUUID = CBUUID(string: K.eddystoneServiceuid)
        static let d2P22UUID = CBUUID(string: K.d2p22UID)
        static let connectableBridgeUUID = CBUUID(string: K.connectableModeBridgeUUID)
    }
    
    private(set) var isInBackgroundMode:Bool = false
    private var bleAdvertiser:BLEAdvertiser
    
    
    
    private let bleCentralManagerOptions:[String:Any] =
        [CBCentralManagerOptionShowPowerAlertKey:true,
         CBCentralManagerOptionRestoreIdentifierKey:kCentralManagerUIDString]
    private let bleQueue = DispatchQueue.global(qos: .utility)
    private var hasToScan = false
    private lazy var bleDelegate = BLECentralDelegate(target:self)
    private lazy var centralManager:CBCentralManager = {
        let cbMan = CBCentralManager(delegate: bleDelegate,
                                     queue: bleQueue,
                                     options:bleCentralManagerOptions)
        return cbMan
    }()
    
    
    private lazy var timeIntervalsByUUID_Suffix:[String: TimeInterval] = [:]
    
    private lazy var sideInfoIDs:[String:TimeInterval] = [:]
    private lazy var timestampsByConnectableBridgeIDs:[String:TimeInterval] = [:]
    private var pendingDispatchWorkItems:[String:DispatchWorkItem] = [:]
    private var currentPendingpayload:Data?
    private lazy var _collectionsAccessQueue:OperationQueue = {
        let queue = OperationQueue()
        queue.name = "BLEUCentralManagerService_collectionsAccessQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    private let dispatchSchedulerQueue:DispatchQueue = DispatchQueue(label: "com.Wiliot.BLEService.scheduler.queue")
    
    private lazy var _packetPublisher:PassthroughSubject<BLEPacket,Never> = .init()
    
   
    private lazy var _connectableBridgesPassThrough:PassthroughSubject<String, Never> = .init()
    
    
    private lazy var _scanStatePublisher:PassthroughSubject<BLEUScanState , Never> = .init()
    private lazy var _isBLEScanningPublisher:CurrentValueSubject<Bool, Never> = .init(false)
    
    private var currentBLEState:CBManagerState = .unknown
    private var lastStateStringSent = ""
    
    struct InternalPayloadInfo {
        let uuid:UUID
        let rssi:Int
        let advData:[String:Any]
    }
    
    private lazy var _payloadsPublisher:PassthroughSubject<InternalPayloadInfo, Never> = .init()
    private var _payloadsSubscription:AnyCancellable?
    private var isScanningSubscription:AnyCancellable?
    
    init() throws {
        logger.notice("+ BLEService INIT -")
        do {
            self.bleAdvertiser = try BLEAdvertiser(advertisementDuration: 1.0, advertisementInterval: 2.0)
        }
        catch {
            logger.error("Failed to create BLEAdvertizer. Error: \(error)")
            throw ValueReadingError.missingRequiredValue("CentralManagerService failed to start with inner error: \(error.localizedDescription)")
        }
    }
    
    deinit {
        logger.notice("+ BLEService deinit +")
    }
    
    //MARK: - Public
    func setScanningMode(inBackground:Bool) {
        
        guard inBackground != self.isInBackgroundMode else {
            return
        }
        
        if CBCentralManager.authorization != .allowedAlways { //fixing spontaneous BLE background work before the permission was granted by user
            return
        }
        
        self.isInBackgroundMode = inBackground
        
        if centralManager.isScanning {
            
            let scanStateChangeSubscription =
            self.centralManager.publisher(for: \.isScanning, options: [NSKeyValueObservingOptions.new]).sink { [weak self] isScanning in
                guard let self else{ return }
                
                if !isScanning && self.hasToScan {
                    self.startScanningPeripherals()
                    self.isScanningSubscription = nil
                }
            }
            self.isScanningSubscription = scanStateChangeSubscription
            
            self._stopListeningBroadcasts(hasToScanAfterStop: true)
        }
    }
    
    /// Starts CBCentranManager scanning
    func startListeningBroadcasts() {
        if CBCentralManager.authorization != .allowedAlways { //fixing spontaneous BLE background work before the permission was granted by user
            return
        }
        
        hasToScan = true
        
        timestampsByConnectableBridgeIDs.removeAll()
        
        if !centralManager.isScanning {
            startScanningPeripherals()
        }
        else {
            centralManager.stopScan()
            startScanningPeripherals()
        }
        self._payloadsSubscription =
        self._payloadsPublisher
//            .throttle(for: 0.05,
//                      scheduler: self.dispatchSchedulerQueue,
//                      latest: false)
            .sink(receiveValue: { [weak self] info in
                
                self?.updateCurrentPackets(with: info.uuid,
                                           rssi: info.rssi,
                                           advData: info.advData)
            })
    }
    
    ///Stops CBCentranManager scanning
    func stopListeningBroadcasts() {
        self.hasToScan = false
        self._stopListening()
    }
    
    //MARK: -
    private func _stopListeningBroadcasts(hasToScanAfterStop: Bool = false) {
        self.hasToScan = hasToScanAfterStop
        self._stopListening()
    }
    
    private func _stopListening() {
        
        if !self.hasToScan, let subscription = self._payloadsSubscription {
            subscription.cancel()
            self._payloadsSubscription = nil
        }
        
        if CBCentralManager.authorization != .allowedAlways { //fixing spontaneous BLE background work before the permission was granted by user
            return
        }
        
        logger.notice("Stopping BLE")
        _collectionsAccessQueue.cancelAllOperations()
        
        bleAdvertiser.stop()
        centralManager.stopScan()
        timeIntervalsByUUID_Suffix.removeAll()
        
        
        sideInfoIDs.removeAll()
        
        timestampsByConnectableBridgeIDs.removeAll()
        
        if !self.pendingDispatchWorkItems.isEmpty {
            self.pendingDispatchWorkItems.keys.lazy.forEach { key in
                self.pendingDispatchWorkItems[key]?.cancel()
            }
            self.pendingDispatchWorkItems.removeAll()
        }
        
        isBLEScanning = false
        _isBLEScanningPublisher.send(false)
        
        let scanState:BLEUScanState = BLEUScanState(managerState: self.currentBLEState, statusString: "stopped")
        
        _scanStatePublisher.send(scanState)
    }
    
    //MARK: - Private
    private func startScanningPeripherals() {
        
        
        
        let scanOpts = [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)]
        
        var services:[CBUUID]?
        
        if self.isInBackgroundMode {
            let wiliotFDAFuid = CBUUIDS.wiliotCBUUID
            let wiliotBridgeFCC6uid = CBUUIDS.wiliotBridgeCBUUID
            let wiliotThirdPartyServiceCBUUID = CBUUIDS.wiliotThirdPartyServiceCBUUID
            let d2p22UID = CBUUIDS.d2P22UUID
            let connectableCBuuuid = CBUUIDS.connectableBridgeUUID
            
            services = [wiliotFDAFuid, d2p22UID, wiliotBridgeFCC6uid, connectableCBuuuid, wiliotThirdPartyServiceCBUUID]
        }

        
        defer {
            isBLEScanning = centralManager.isScanning
            _isBLEScanningPublisher.send(isBLEScanning)
        }
        
        if centralManager.state == .poweredOn {
            if centralManager.delegate == nil {
                centralManager.delegate = self.bleDelegate
            }
            else {
                //print("\(self) \(#function) - BLEScanner STARTing Scanning (services: \(services?.count ?? 0)")
                if centralManager.isScanning {
                    return
                }
                
                logger.notice(" - BLEService \(#function) - BLEScanner STARTing Scanning (services: \(services?.count ?? 0)")
                centralManager.scanForPeripherals(withServices: services, options: scanOpts)
                bleAdvertiser.start()
                self.currentBLEState = .poweredOn
                
                let state = BLEUScanState(managerState: self.currentBLEState, statusString: "scan started")
                
                _scanStatePublisher.send(state)
            }
        }
        else {
            
            logger.notice(" - BLEService \(#function) - BLEScanner Scanning NOT started:  \(self.centralManager.stateString)")
            if centralManager.delegate == nil {
                centralManager.delegate = self.bleDelegate
            }
        }
    }
    
    private func updateCurrentPackets(with uid:UUID, rssi:Int, advData:[String:Any]) {

        let currentTimeInterval = Date().millisecondsFrom1970()
        
        var neededData:Data?
        var isManufacturer = false
        
        if let manufacturerData = advData[K.manufacturerDataKey] as? Data {
            let manufactureIDString = manufacturerData.getManufacturerIdString()

            if manufactureIDString == K.wiliotManufactureID { //"0500"

                neededData = manufacturerData
            }
            isManufacturer = true
        }
        else if let serviceData = advData[K.serviceDataKey] as? [CBUUID: Any] {
            
            let keyFDAF = CBUUIDS.wiliotCBUUID //FDAF
            if let servData = serviceData[keyFDAF] as? Data {
        
                if let prefixData = Data(hexString: K.embeddedGatewayServiceUID) { //add "AFFD" as prefix
                    let dataWithAFFDPrefix = prefixData + servData
                    neededData = dataWithAFFDPrefix
                }
            }
            else if let servDataFromBridge = serviceData[CBUUIDS.wiliotBridgeCBUUID] as? Data {
                // add prefix FCC6
//                printDebug("Pixel With: 'FCC6'")
                let prefixData = Data([UInt8(0xFC), UInt8(0xC6)])
                let dataWithFCC6Prefix = prefixData + servDataFromBridge
                neededData = dataWithFCC6Prefix
            }
            else if let servDataEddystone = serviceData[CBUUIDS.eddystoneCBUUID] as? Data {
//                printDebug("Pixel With: 'FEAA'")
                neededData = servDataEddystone
            }
            else if let servDataD2P22 = serviceData[CBUUIDS.d2P22UUID] as? Data {
//                printDebug("Pixel With: '05AF'")
                if let prefixData05AF = Data(hexString: K.d2p22UID) {
                    let data = prefixData05AF + servDataD2P22
                    neededData = data
                }
            }
            else if let serviceDataThirdPartyInfo = serviceData[CBUUIDS.wiliotThirdPartyServiceCBUUID] as? Data {
                //adding prefix FC90
                let prefixData = Data([UInt8(0xFC), UInt8(0x90)])
                let data = prefixData + serviceDataThirdPartyInfo
                neededData = data
            }
        }
        
        guard let payloadData = neededData else {
            return
        }
        
        if BeaconDataReader.isBeaconDataGWtoBridgeMessage(payloadData) {
//            logger.notice("Bridge To Gateway message: \(payloadData.stringHexEncodedUppercased())")
            return
        }
        
        var makeNewSideInfoPacket = false
        let last4BytesId = payloadData.suffix(4).stringHexEncodedUppercased()
        let sideInfoKey = last4BytesId+uid.uuidString
        
        if !isManufacturer, BeaconDataReader.isBeaconDataSideInfoPacket(payloadData) {
            
            var time:TimeInterval?
            
            let checkOp = BlockOperation {[unowned self] in
                time = self.sideInfoIDs[sideInfoKey]
            }
            
            self._collectionsAccessQueue.addOperations([checkOp], waitUntilFinished: true)
            
            if let time {
                
                let timeDiff = currentTimeInterval - time
                if timeDiff < kRepeatingPacketTimeout {
                    return
                }
            }
            makeNewSideInfoPacket = true
        }
        
        //Side Info from Bridges
        
        if makeNewSideInfoPacket || BeaconDataReader.isBeaconDataCombinedPacket(payloadData) {
            
            self._collectionsAccessQueue.addBarrierBlock {[weak self, sideInfoKey, currentTimeInterval] in
                guard let self else { return }
                self.sideInfoIDs[sideInfoKey] = currentTimeInterval
            }
//            logger.notice(" - BLEService sideInfo payload: \(payloadData.stringHexEncodedUppercased())")
            let blePacket = BLEPacket(isManufacturer: isManufacturer, uid: uid, rssi: rssi, data: payloadData, timeStamp: currentTimeInterval)
            _packetPublisher.send(blePacket)
            
            
            //postpone a cleanup
            self.dispatchSchedulerQueue.asyncAfter(deadline: .now() + .milliseconds(Int(kRepeatingPacketTimeout))) { [weak self] in
                guard let self else { return }
                
                self._collectionsAccessQueue.addBarrierBlock {[weak self, sideInfoKey] in
                    guard let self else { return }
                    self.sideInfoIDs[sideInfoKey] = nil
//                    weakSelf?.sideInfoIDs.removeValue(forKey: sideInfoKey)
                }
            }
            return
        }
        
        //
        
        var makeNewPacket = false
        let suffixAndUUIDkey:String = last4BytesId + uid.uuidString
        
        if let timeInterval = timeIntervalsByUUID_Suffix[suffixAndUUIDkey] {
            
                //detect 'kRepeatingPixelPacketTimeout' milliseconds
                
                if currentTimeInterval - timeInterval < kRepeatingPixelPacketTimeout {
                    //repeated packet transmission
                    return
                }
                else {
                    // new BLE packet
                    makeNewPacket = true
                }
        }
        else {
            //new BLE packet
            makeNewPacket = true
        }
        
        
        if makeNewPacket {
            
            timeIntervalsByUUID_Suffix[suffixAndUUIDkey] = (currentTimeInterval)

            let blePacket = BLEPacket(isManufacturer: isManufacturer, uid: uid, rssi: rssi, data: payloadData, timeStamp: currentTimeInterval)
            logger.notice("blePacket: \(blePacket.data.stringHexEncodedUppercased())")
            _packetPublisher.send(blePacket)
        }
    }
    
    private func handleNewConnectableBridgeId( _ bridgeIdFromConnectableBridge:String) {
        
        let currentDateTimestamp = Date().timeIntervalSince1970 //seconds
        
        if let timeStamp = timestampsByConnectableBridgeIDs[bridgeIdFromConnectableBridge] {
            
            let secondsPassed = currentDateTimestamp - timeStamp
            timestampsByConnectableBridgeIDs[bridgeIdFromConnectableBridge] = currentDateTimestamp
            
            if secondsPassed < TimeInterval(kConnectableStateBridgeTimeoutSeconds) {
                return
            }
            else {
                logger.notice(" - Sending Connectable BridgeId ((\(bridgeIdFromConnectableBridge))) to subscribers (over \(kConnectableStateBridgeTimeoutSeconds) seconds)")
                _connectableBridgesPassThrough.send(bridgeIdFromConnectableBridge)
                postponeConnectableBridgeIdCleanup(for: bridgeIdFromConnectableBridge)
            }
        }
        else {
            logger.notice(" - BLEService Sending Connectable BridgeId \(bridgeIdFromConnectableBridge) to subscribers (new discovered)")
            timestampsByConnectableBridgeIDs[bridgeIdFromConnectableBridge] = currentDateTimestamp //seconds
            _connectableBridgesPassThrough.send(bridgeIdFromConnectableBridge)
            
            
            postponeConnectableBridgeIdCleanup(for: bridgeIdFromConnectableBridge)
            
        }
        
    }
    
    /// postpone cleanup of the Connectable Bridge ID from in-memory storage
    private func postponeConnectableBridgeIdCleanup(for bridgeId:String) {
        
        let item = DispatchWorkItem(flags: DispatchWorkItemFlags.detached, block: { [weak self] in
            guard let self else {
                return
            }
            
//            logger.notice(" - BLESERVICE starts to remove connectable bridge ID Data for '\(bridgeId)'. \(Date().timeStringWithSeconds())")
            self._collectionsAccessQueue.addBarrierBlock ({[weak self] in
                    guard let weakerSelf = self else {
                        return
                    }
                    
                weakerSelf.timestampsByConnectableBridgeIDs[bridgeId] = nil
                weakerSelf.pendingDispatchWorkItems[bridgeId] = nil
            })
            
        })
        
        self.pendingDispatchWorkItems[bridgeId] = item
        
        DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(kConnectableStateBridgeTimeoutSeconds), execute: item)
    }
    
}

//MARK: BLECentralDelegateTarget
extension BLEUCentralManagerService : BLECentralDelegateTarget {
    fileprivate func centralManagerDidUpdateState(_ central: CBCentralManager) {
        #if targetEnvironment(simulator)
        return
        #endif
        let state = central.state
        
        switch state {
        case .unknown:
            logger.warning("BLEservice CentralManagerState: 'Unknown'")
        case .resetting:
            logger.warning("BLEservice CentralManagerState: 'Resetting'")
        case .unsupported:
            logger.error("BLEservice tried to start work on incompatible device")
            fatalError("BLEservice tried to start work on incompatible device")
        case .unauthorized:
            logger.warning("BLEservice tried to start work before BLE permissions acquired")
//            fatalError("BLEservice tried to start work before BLE permissions acquired")
        case .poweredOff:
            logger.warning("BLEService CBCentralManager PoweredOFF");
        case .poweredOn:
            logger.warning("BLEService CBCentralManager PoweredOn");
            if hasToScan {
                startScanningPeripherals()
            }
        default:
            fatalError("BLEService Unhendled BLE CentralManager State")
        }
        self.currentBLEState = state
        self.lastStateStringSent = ""
        let scanState = BLEUScanState(managerState: state, statusString: "")
        _scanStatePublisher.send(scanState)
    }
    
    fileprivate func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        logger.info("BLEService state restortion: \(dict)")
    }
    
    fileprivate func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        if advertisementData["kCBAdvDataLocalName"] != nil {
//            return
//        }
        
        if self.currentBLEState != .poweredOn || lastStateStringSent != "scanning" || self.isBLEScanning != true{
            self.currentBLEState = .poweredOn
            self.isBLEScanning = true
            self.lastStateStringSent = "scanning"
            self._scanStatePublisher.send(BLEUScanState(managerState: self.currentBLEState, statusString: self.lastStateStringSent))
            _isBLEScanningPublisher.send(isBLEScanning)
        }
        
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            //printDebug("Local Name: '\(name)'")
            if let bridgeIdFromConnectableBridge = name.wiliotAdvertizedConnectableBridgeId {
                handleNewConnectableBridgeId(bridgeIdFromConnectableBridge)
                return
            }
        }
        
        if (advertisementData[CBAdvertisementDataIsConnectable] as? Int) ?? 0 != 0 {
            return
        }
        
        if advertisementData[CBAdvertisementDataServiceDataKey] == nil {
            if advertisementData[CBAdvertisementDataManufacturerDataKey] == nil {
                return
            }
        }
     
        
        //filter duplicate channels receiving same transmission
        
        let peripheralUID = peripheral.identifier
        
       // logger.notice("Handlong ADV Data: \(advertisementData)")
        self._payloadsPublisher.send(InternalPayloadInfo(uuid: peripheralUID, rssi: Int(RSSI.int32Value), advData: advertisementData) )
        
//        updateCurrentPackets(with: peripheralUID,
//                             rssi: Int(RSSI.int32Value),
//                             advData: advertisementData)
    }
    
}


//MARK: - BLECentralDelegateTarget
fileprivate protocol BLECentralDelegateTarget:AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any])
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber)
}

@objc fileprivate class BLECentralDelegate:NSObject {
    weak var target:BLECentralDelegateTarget?
    init(target:BLECentralDelegateTarget) {
        self.target = target
    }
}

extension BLECentralDelegate: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        target?.centralManagerDidUpdateState(central)
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        target?.centralManager(central, willRestoreState: dict)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        target?.centralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
}

extension CBCentralManager {
    var stateString:String {
        return self.state.stateString
    }
}

extension CBManagerState {
    var stateString:String {
        switch self {
        case .unknown:
            return "Unknown"
        case .resetting:
            return "Resetting"
        case .unauthorized:
            return "Unauthorized"
        case .unsupported:
            return "Unsupported"
        case .poweredOff:
            return "Powered Off"
        case .poweredOn:
            return "Powered On"
        @unknown default:
            return "Unknown Default"
        }
    }
}


