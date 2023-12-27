//
//  BLEService.swift

import Foundation
import CoreBluetooth
import Combine

private let kCentralManagerUIDString = "com.wiliot.BLEcentralManager.uid"

let kServiceUUIDString = "AFFD"
let kBridgePayloadsUUIDString = "FCC6"
fileprivate let kRepeatingPacketTimeout:TimeInterval = 3000
fileprivate let kRepeatingPixelPacketTimeout:TimeInterval = 3000


class BLEService {

    
    var isBLEScanningPublisher:AnyPublisher<Bool, Never> {
        return _isBLEScanningPublisher.eraseToAnyPublisher()
    }
    
    var isBLEScanning:Bool = false
    
    var scanStatePublisher:AnyPublisher<(CBManagerState, String), Never> {
        return _scanStatePublisher.eraseToAnyPublisher()
    }
    
    
    private struct K {
        static let eddystoneServiceuid = "FEAA"
        static let wiliotManufactureID = "0500"
        static let serviceDataKey = "kCBAdvDataServiceData"
        static let manufacturerDataKey = "kCBAdvDataManufacturerData"
        static let wiliotServiceuid = "FDAF"
        static let embeddedGatewayServiceUID = kServiceUUIDString //"AFFD"
        static let wiliotBridgeServicUUID = kBridgePayloadsUUIDString
        static let d2p22UID = "05AF"
        static let connectableModeBridgeUUID = "180A"
    }

    private struct CBUUIDS {
        static let wiliotCBUUID = CBUUID(string: K.wiliotServiceuid)
        static let wiliotEmbeddedGWCBUUID = CBUUID(string: K.embeddedGatewayServiceUID)
        static let wiliotBridgeCBUUID = CBUUID(string: K.wiliotBridgeServicUUID)
        static let eddystoneCBUUID = CBUUID(string: K.eddystoneServiceuid)
        static let d2P22UUID = CBUUID(string: K.d2p22UID)
        static let connectableBridgeUUID = CBUUID(string: K.connectableModeBridgeUUID)
    }
    
    
    private(set) var isInBackgroundMode:Bool = false
    
    private let bleCentralManagerOptions:[String:Any] =
        [CBCentralManagerOptionShowPowerAlertKey:true,
         CBCentralManagerOptionRestoreIdentifierKey:kCentralManagerUIDString]
    private let bleQueue = DispatchQueue.global(qos: .utility)
    private var hasToScan = false
    private lazy var bleDelegate = BLECentralDelegate(target: self)
    private lazy var centralManager: CBCentralManager = CBCentralManager(delegate: bleDelegate,
                                                                queue: bleQueue,
                                                                options:bleCentralManagerOptions)
    
    private let dispatchSchedulerQueue:DispatchQueue = DispatchQueue(label: "com.Wiliot.BLEService.scheduler.queue")
    private lazy var currentScannedUIDs:[String: TimeInterval] = [:]
    private lazy var _scanStatePublisher:PassthroughSubject<(CBManagerState, String) , Never> = .init()
    private lazy var _isBLEScanningPublisher:PassthroughSubject<Bool, Never> = .init()
    private var currentBLEState:CBManagerState = .unknown
    private lazy var sideInfoIDs:[String:TimeInterval] = [:]
    private var currentPendingpayload:Data?
    private lazy var cleanupQueue:OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var packetPublisher: AnyPublisher<BLEPacket, Never> {
        _packetPublisher.eraseToAnyPublisher()
    }
    
    private lazy var _packetPublisher:PassthroughSubject<BLEPacket,Never> = .init()
       
    deinit {
        print("+ BLEService deinit +")
    }

    // MARK: - Public
    func setScanningMode(inBackground: Bool) {

        guard inBackground != self.isInBackgroundMode else {
            return
        }

        self.isInBackgroundMode = inBackground

        if centralManager.isScanning {
            stopListeningBroadcasts()
            startScanningPeripherals()
        }
    }

    /// Starts CBCentranManager scanning
    func startListeningBroadcasts() {
        hasToScan = true

        if !centralManager.isScanning {
            startScanningPeripherals()
        } else {
            centralManager.stopScan()
            startScanningPeripherals()
        }
    }

    /// Stops CBCentranManager scanning
    func stopListeningBroadcasts() {
        hasToScan = false

        centralManager.stopScan()
        currentScannedUIDs.removeAll()
    }

    // MARK: - Private
    private func startScanningPeripherals() {
        
        
        let wiliotFDAFuid = CBUUIDS.wiliotCBUUID
        let wiliotBridgeFCC6uid = CBUUIDS.wiliotBridgeCBUUID
        let d2p22UID = CBUUIDS.d2P22UUID
        let connectableCBuuuid = CBUUIDS.connectableBridgeUUID
        let scanOpts = [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)]
        let services:[CBUUID]? = isInBackgroundMode ? [wiliotFDAFuid, d2p22UID, wiliotBridgeFCC6uid, connectableCBuuuid] : nil

        
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
                #if DEBUG
                print(" - BLEService \(#function) - BLEScanner STARTing Scanning (services: \(services?.count ?? 0)")
                #endif
                
                centralManager.scanForPeripherals(withServices: services, options: scanOpts)
                
                self.currentBLEState = .unknown
                _scanStatePublisher.send((CBManagerState.unknown, "scan started"))
            }
        }
        else {
            #if DEBUG
            print(" - BLEService \(#function) - BLEScanner Scanning NOT started:  \(centralManager.stateString)")
            #endif
            
            if centralManager.delegate == nil {
                centralManager.delegate = self.bleDelegate
            }
        }
    }
    
    private func updateCurrentPackets(with uid:UUID, rssi:Int, advData:[String:Any]) {
        
        let currentTimeInterval = Date().milisecondsFrom1970()
        
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
            
            if let servData = serviceData[CBUUIDS.wiliotCBUUID] as? Data {
                
                
                if let prefixData = Data(hexString: K.embeddedGatewayServiceUID) { //add "AFFD" as prefix
                    let dataWithAFFDPrefix = prefixData + servData
                    neededData = dataWithAFFDPrefix
                }
            }
            else if let servDataFromDridge = serviceData[CBUUIDS.wiliotBridgeCBUUID] as? Data {
                // add prefix FCC6
                let prefixData = Data([UInt8(0xFC), UInt8(0xC6)])
                let dataWithFCC6Prefix = prefixData + servDataFromDridge
                neededData = dataWithFCC6Prefix
            }
            else if let servDataEddystone = serviceData[CBUUIDS.eddystoneCBUUID] as? Data {
                neededData = servDataEddystone
            }
            else if let servDataD2P22 = serviceData[CBUUIDS.d2P22UUID] as? Data {
                if let prefixData05AF = Data(hexString: K.d2p22UID) {
                    let data = prefixData05AF + servDataD2P22
                    neededData = data
                }
            }
        }

        guard let payloadData = neededData else {
            return
        }
        
        if BeaconDataReader.isBeaconDataGWtoBridgeMessage(payloadData) {
            return
        }
        
        var makeNewSideInfoPacket = false
        let last4BytesId = payloadData.suffix(4).hexEncodedString(options: .upperCase)
        let sideInfoKey = last4BytesId+uid.uuidString
        
        if !isManufacturer, BeaconDataReader.isBeaconDataSideInfoPacket(payloadData) {
            if let time = sideInfoIDs[sideInfoKey] {
                
                let timeDiff = currentTimeInterval - time
                if timeDiff < kRepeatingPacketTimeout {
                    return
                }
            }
            makeNewSideInfoPacket = true
        }

        // Side Info from Bridges

        if makeNewSideInfoPacket {
            sideInfoIDs[sideInfoKey] = currentTimeInterval
            
//            printDebug(" - BLEService sideInfo payload: \(payloadData.hexEncodedString(options: .upperCase))")
            let blePacket = BLEPacket(isManufacturer: isManufacturer, uid: uid, rssi: rssi, data: payloadData, timeStamp: currentTimeInterval)
            _packetPublisher.send(blePacket)
            
            
            //postpone a cleanup
            dispatchSchedulerQueue.asyncAfter(deadline: .now() + .milliseconds(Int(kRepeatingPacketTimeout))) { [weak self] in
                guard let weakSelf = self else {
                    return
                }
                
                weakSelf.cleanupQueue.addOperation {[weak weakSelf] in
//                    weakSelf?.sideInfoIDs[sideInfoKey] = nil
                    weakSelf?.sideInfoIDs.removeValue(forKey: sideInfoKey)
                }
            }
            return
        }
        
        var takeTimeoutIntoAccount = true
        if BeaconDataReader.isBeaconDataBridgeToGWmessage(payloadData) {
//            printDebug(" - Brg to GW. TimeStamp: \(currentTimeInterval), hex: \(payloadData.wiliotEdgeDeviceMACstring)")
            takeTimeoutIntoAccount = false
        }
        
        
        //
        
        var makeNewPacket = false
        let tagPacketKey:String = last4BytesId + uid.uuidString
        
        if let timeInterval = currentScannedUIDs[tagPacketKey] {
            
                //detect 3000 milliseconds
                
                if currentTimeInterval - timeInterval < kRepeatingPixelPacketTimeout {
                    //repeated packet transmission
                    return
                } else {
                    // new BLE packet
                    makeNewPacket = true
                }
        }
        else {
            //new BLE packet
            makeNewPacket = true
        }

        if makeNewPacket {
            if takeTimeoutIntoAccount {
                currentScannedUIDs[tagPacketKey] = (currentTimeInterval)

            }
            
            let blePacket = BLEPacket(isManufacturer: isManufacturer, uid: uid, rssi: rssi, data: payloadData, timeStamp: currentTimeInterval)
            _packetPublisher.send(blePacket)
        }
    }

}

// MARK: BLECentralDelegateTarget
extension BLEService: BLECentralDelegateTarget {
    fileprivate func centralManagerDidUpdateState(_ central: CBCentralManager) {
        #if targetEnvironment(simulator)
        return
        #endif
        let state = central.state

        switch state {
        case .unknown:
            print("BLEservice CentralManagerState: 'Unknown'")
        case .resetting:
            print("")
        case .unsupported:
            fatalError("BLEservice tried to start work on incompatible device")
        case .unauthorized:
            print("BLEservice tried to start work before BLE permissions acquired")
//            fatalError("BLEservice tried to start work before BLE permissions acquired")
        case .poweredOff:
            print("")
        case .poweredOn:
            if hasToScan {
                startScanningPeripherals()
            }
        default:
            fatalError("BLEService Unhendled BLE CentralManager State")
        }
        
        self.currentBLEState = state
        _scanStatePublisher.send((state, ""))
    }

    fileprivate func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {

    }
    
    fileprivate func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        if (advertisementData[CBAdvertisementDataIsConnectable] as? Int) ?? 0 != 0 {
            return
        }
        
        if advertisementData[CBAdvertisementDataServiceDataKey] == nil {
            if advertisementData[CBAdvertisementDataManufacturerDataKey] == nil {
                return
            }
        }
        
        let peripheralUID = peripheral.identifier
        
        updateCurrentPackets(with: peripheralUID,
                             rssi: Int(RSSI.int32Value),
                             advData: advertisementData)
    }

}

private protocol BLECentralDelegateTarget: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any])
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
}

@objc private class BLECentralDelegate: NSObject {
    weak var target: BLECentralDelegateTarget?
    init(target: BLECentralDelegateTarget) {
        self.target = target
    }
}

extension BLECentralDelegate: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        target?.centralManagerDidUpdateState(central)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        target?.centralManager(central, willRestoreState: dict)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        target?.centralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
}

extension CBCentralManager {
    var stateString: String {
        switch state {
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
