//
//  BLEService.swift

import Foundation
import CoreBluetooth
import Combine

private let kCentralManagerUIDString = "com.wiliot.BLEcentralManager.uid"

private typealias TailIdAndMilliseconds = (id: String, millis: TimeInterval)

class BLEService {

    private struct K {

        static let serviceDataKey = "kCBAdvDataServiceData"
        static let manufacturerDataKey = "kCBAdvDataManufacturerData"
        static let wiliotServiceuid = "FDAF" // "AFFD"

    }

    private struct CBUUIDS {
        static let wiliotCBUUID = CBUUID(string: K.wiliotServiceuid)
    }

    private(set) var isInBackgroundMode: Bool = false

    private let bleCentralManagerOptions: [String: Any] =
        [CBCentralManagerOptionShowPowerAlertKey: true,
         CBCentralManagerOptionRestoreIdentifierKey: kCentralManagerUIDString]
    private let bleQueue = DispatchQueue.global(qos: .utility)
    private var hasToScan = false
    private lazy var bleDelegate = BLECentralDelegate(target: self)
    private lazy var centralManager: CBCentralManager = CBCentralManager(delegate: bleDelegate,
                                                                queue: bleQueue,
                                                                options: bleCentralManagerOptions)

    private lazy var currentScannedUIDs: [UUID: TailIdAndMilliseconds] = [:]

    private lazy var sideInfoIDs: [String: TimeInterval] = [:]
    private var currentPendingpayload: Data?
    private lazy var cleanupQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var packetPublisher: AnyPublisher<BLEPacket, Never> {
        _packetPublisher.eraseToAnyPublisher()
    }
    private lazy var _packetPublisher: PassthroughSubject<BLEPacket, Never> = .init()

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

        let uid = CBUUIDS.wiliotCBUUID

        let scanOpts = [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)]
        let services: [CBUUID]? = isInBackgroundMode ? [uid] : nil

        if centralManager.state == .poweredOn {
            if centralManager.delegate == nil {
                centralManager.delegate = self.bleDelegate
            } else {
                if centralManager.isScanning {
                    return
                }
                centralManager.scanForPeripherals(withServices: services, options: scanOpts)

            }
        } else {

            print("\(self) \(#function) - BLEScanner Scanning NOT started:  \(centralManager.stateString)")
            if centralManager.delegate == nil {
                centralManager.delegate = self.bleDelegate
            }
        }
    }

    private func updateCurrentPackets(with uid: UUID, rssi: Int, advData: [String: Any]) {

        let currentTimeInterval = Date().milisecondsFrom1970()

        var neededData: Data?

        if let serviceData = advData[K.serviceDataKey] as? [CBUUID: Any] {

            if let servData = serviceData[CBUUIDS.wiliotCBUUID] as? Data {

                if let prefixData = Data(hexString: K.wiliotServiceuid) {
                    let data = prefixData + servData
                    neededData = data
                }
            }
        }

        guard let payloadData = neededData else {
            return
        }

        var makeNewPacket = false
        var makeNewSideInfoPacket = false
        let last4BytesId = payloadData.suffix(4).hexEncodedString(options: .upperCase)

        if Data(payloadData.subdata(in: 0..<5)).hexEncodedString() == "FDAF0000EC".lowercased() {
            if let time = sideInfoIDs[last4BytesId] {
                let millisecondsPassed = currentTimeInterval - time
                // print(" - milliseconds passed: \(millisecondsPassed)")
                if millisecondsPassed < 200 {
                    return
                }
            }
            makeNewSideInfoPacket = true
        }

        // Side Info from Bridges

        if makeNewSideInfoPacket {

            sideInfoIDs[last4BytesId] = currentTimeInterval

            let blePacket = BLEPacket(isManufacturer: false, uid: uid, rssi: rssi, data: payloadData)
            _packetPublisher.send(blePacket)

            DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let weakSelf = self else {
                    return
                }

                weakSelf.cleanupQueue.addOperation {[weak self] in
                    self?.sideInfoIDs[last4BytesId] = nil
                }
            }
            return
        }

        //
        if let existingInfo = currentScannedUIDs[uid] {
            if existingInfo.id == last4BytesId {
                // detect 200 milliseconds
                let timeScannedBefore: TimeInterval = existingInfo.millis
                let millisecondsFromLastPacket = currentTimeInterval - timeScannedBefore
                if millisecondsFromLastPacket < 300 {
                    // repeated packet transmission
                    return
                } else {
                    // new BLE packet
                    makeNewPacket = true
                }
            } else {
                // new BLE packet
                makeNewPacket = true
            }
        } else {
            // new BLE packet
            makeNewPacket = true
        }

        if makeNewPacket {
            currentScannedUIDs[uid] = (id: last4BytesId, millis: currentTimeInterval)
            let blePacket = BLEPacket(isManufacturer: false, uid: uid, rssi: rssi, data: payloadData)
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
    }

    fileprivate func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {

    }

    fileprivate func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
//        if advertisementData["kCBAdvDataLocalName"] != nil {
//            return
//        }

        if (advertisementData["kCBAdvDataIsConnectable"] as? Int) ?? 0 != 0 {
            return
        }

        if advertisementData[CBAdvertisementDataServiceDataKey] == nil && advertisementData[CBAdvertisementDataManufacturerDataKey] == nil {
            return
        }

        // filter duplicate channels receiving same transmission

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
