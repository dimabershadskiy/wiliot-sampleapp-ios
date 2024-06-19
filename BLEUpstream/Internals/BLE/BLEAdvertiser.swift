//
//  BLEAdvertiser.swift
//  Wiliot
//

import CoreBluetooth
import CoreLocation
import Foundation
import WiliotCore

fileprivate let logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEAdvertiser")

final class BLEAdvertiser: NSObject {
    // MARK: - Variables
    private lazy var peripheralManager: CBPeripheralManager = CBPeripheralManager(delegate: self, queue: bgQueue)
    private var cbServiceConfiguration: CBMutableService? = nil//createService()

//    private var advertisementIntervalTimer: Timer?
//    private var advertisementDurationTimer: Timer?

    private var advertisementDuration: Double
    private var advertisementInterval: Double
    
    private let bgQueue = DispatchQueue(label: "com.wiliot.wiliotapp.BLEAdvertiser", qos: .utility)
    private lazy var dispatchSource: DispatchSourceTimer? = nil
    private var shouldInitiateWithManagerStateChange = false

    // MARK: - Life Cycle

    init(advertisementDuration: Double, advertisementInterval: Double) throws {
        guard advertisementDuration >= 0.001, advertisementInterval >= 0.001 else {
            throw ValueReadingError.invalidValue("Advertizement timings too low")
        }
        
        self.advertisementDuration = advertisementDuration
        self.advertisementInterval = advertisementInterval
        super.init()
//        peripheralManager.add(cbServiceConfiguration)
        logger.notice(" + BLEAdvertizer INIT -")
    }
    
    deinit {
        logger.notice(" + BLEAdvertizer deinit +")
        stop()
        if let serviceConfig = cbServiceConfiguration {
            peripheralManager.remove(serviceConfig)
        }
        cbServiceConfiguration = nil
        dispatchSource = nil
    }

    // MARK: - Functions

    func set(advertisementDuration: Double, advertisementInterval: Double) {
        guard advertisementDuration > 0 else {
            return
        }
        
        //suspend()
        self.shouldInitiateWithManagerStateChange = false
        self._stopAdvertising()
        self.advertisementDuration = advertisementDuration
        self.advertisementInterval = advertisementInterval
        self.shouldInitiateWithManagerStateChange = true
        self._startAdvertising()
//        resume()
    }

    // start whole cycle here, init services, validate state
    func start() {
        logger.notice(" \(#function) - starting advertising.")
        
        shouldInitiateWithManagerStateChange = true
        
        if cbServiceConfiguration == nil {
            let serviceConfig = createService()
            cbServiceConfiguration = serviceConfig
            peripheralManager.add(serviceConfig)
        }
    }

    func stop() {
        shouldInitiateWithManagerStateChange = false
        if peripheralManager.isAdvertising {
            logger.notice(" \(#function) -  stoping advertising.")
            self._stopAdvertising()
        }
        
        
    }

    // MARK: - Private functions
    
//    private func suspend() {
////        dispatchSource?.setEventHandler {}
//        dispatchSource?.cancel()
//    }
//    
//    private func resume() {
//        if nil == dispatchSource || true == dispatchSource?.isCancelled {
//            let aDispatchSource = DispatchSource.makeTimerSource(queue: bgQueue)
//            aDispatchSource.setEventHandler {[weak self] in
//                self?._startAdvertising()
//            }
//            self.dispatchSource = aDispatchSource
//            aDispatchSource.schedule(deadline: .now() + .seconds(1), repeating: advertisementInterval)
//            aDispatchSource.activate()
//        }
//    }

    private func createService() -> CBMutableService {
        let cbuuid = CBUUID(string: "1818")
        let data = Data(count: 100)
        let characteristic = CBMutableCharacteristic(type: cbuuid,
                                                     properties: CBCharacteristicProperties.read,
                                                     value: data, permissions: .readable)
        let serviceCBUUID = CBUUID(string: "0500")
        let service = CBMutableService(type: serviceCBUUID, primary: true)
        service.characteristics = [characteristic]

        return service
    }

    // MARK: - Selectors
    
    @objc private func _startAdvertising() {
        if false == peripheralManager.isAdvertising, let serviceConfig = cbServiceConfiguration {
//            logger.info("\(self) \(#function)")
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [serviceConfig.uuid],
                CBAdvertisementDataLocalNameKey: "Charger",
            ])
            
            self.postponeAdvertizingCancellation()
        }
    }

    func postponeAdvertizingCancellation() {
        let millisecondsToStop = Int(self.advertisementDuration * 1000)
        
        self.bgQueue.asyncAfter(deadline: .now() + .milliseconds(millisecondsToStop), execute: {[weak self] in
            guard let self else {
                return
            }
            self._stopAdvertising()
            
        })
    }
    
    @objc func _stopAdvertising() {
        if true == peripheralManager.isAdvertising {
//            logger.info("\(self) \(#function)")
            peripheralManager.stopAdvertising()
        }
        
        if self.shouldInitiateWithManagerStateChange {
            let millisecondsToRestart = Int(self.advertisementInterval * 1000)
            self.bgQueue.asyncAfter(deadline: .now() + .milliseconds(millisecondsToRestart), execute: {[weak self] in
                guard let self else { return }
                self._startAdvertising()
            })
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEAdvertiser: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .unknown:
            logger.notice(" - BLEAdvertiser \(#function) state unknown")
        case .resetting:
            logger.notice(" - BLEAdvertiser \(#function) state resetting")
        case .unsupported:
            logger.notice(" - BLEAdvertiser \(#function) state unsupported")
        case .unauthorized:
//            suspend()
            logger.notice(" - BLEAdvertiser \(#function) state unauthorized")
        case .poweredOff:
            logger.notice(" - BLEAdvertiser \(#function) state poweredOff")
//            suspend()
        case .poweredOn:
            if shouldInitiateWithManagerStateChange {
                _startAdvertising()
            }
            logger.notice(" - BLEAdvertiser \(#function) state poweredOn")
        @unknown default:
            return
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        //        printDebug("\(self) \(#function)")
        if let error = error {
            logger.notice("\(self) \(#function) Error:\(error)")
            stop()
        } else {
            logger.notice("\(self) \(#function) NO ERROR")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        logger.notice("\(self) \(#function)")
        logger.notice("\(peripheral.description)")
        logger.notice("\(service.description)")
    }
}
