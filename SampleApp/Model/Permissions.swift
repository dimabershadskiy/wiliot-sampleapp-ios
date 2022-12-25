//
//  Permissions.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 03.05.2022.
//

import Foundation
import CoreLocation
import CoreBluetooth
import Combine

class Permissions: ObservableObject {
    var isLocationPermissionsErrorNeedManualSetup: Bool = false {
        willSet {
            objectWillChange.send()
        }
    }

    var locationAlwaysGranded: Bool = false
    var locationWhenInUseGranted: Bool = false
    var locationCanBeUsed: Bool = false {
        willSet {
            objectWillChange.send()
        }
    }

    @Published var bluetoothCanBeUsed: Bool = false

    /// to be binded in the toggling the gateway mode
    @Published private(set) var gatewayPermissionsGranted: Bool = false

    var pLocationCanBeUsed: Bool {
        locationAlwaysGranded || locationWhenInUseGranted
    }

    private lazy var cbManager: CBCentralManager = CBCentralManager()
    private lazy var locationManager: CLLocationManager = CLLocationManager()

    private lazy var cbDelegate: CBCentralManagerDelegateObject = CBCentralManagerDelegateObject()
    private lazy var locDelegate: CBLocationManagerDelegateObject = CBLocationManagerDelegateObject()

    init() {

        checkAuthStatus()
    }

    // MARK: - Initialization
    convenience init(bluetoothManager: CBCentralManager? = nil, locationManager: CLLocationManager? = nil) {
        self.init()

        if let bluetoothManager = bluetoothManager {
            self.cbManager = bluetoothManager
        }

        if let locManager = locationManager {
            self.locationManager = locManager
        }
    }
    // MARK: -
    func checkAuthStatus() {

        #if targetEnvironment(simulator)
        locationAlwaysGranded = true
        locationWhenInUseGranted = true
        locationCanBeUsed = true
        bluetoothCanBeUsed = true
        gatewayPermissionsGranted = true
        updateGatewayPermissionsGranted()
        return
        #endif

        let status = locationManager.authorizationStatus

        switch status {

        case .notDetermined:
            locationAlwaysGranded = false
            locationWhenInUseGranted = false
        case .restricted:
            locationAlwaysGranded = false
            locationWhenInUseGranted = false
        case .denied:
            locationAlwaysGranded = false
            locationWhenInUseGranted = false
        case .authorizedAlways:
            locationAlwaysGranded = true
            locationWhenInUseGranted = true
        case .authorizedWhenInUse:
            locationWhenInUseGranted = true
        @unknown default:
            locationAlwaysGranded = false
            locationWhenInUseGranted = false
        }

        locationCanBeUsed = pLocationCanBeUsed

        let btState = CBCentralManager.authorization

        switch btState {
        case .notDetermined:
            bluetoothCanBeUsed = false
        case .restricted:
            bluetoothCanBeUsed = false
        case .denied:
            bluetoothCanBeUsed = false
        case .allowedAlways:
            bluetoothCanBeUsed = true
        @unknown default:
            fatalError()
        }

        updateGatewayPermissionsGranted()
    }

    func requestBluetoothAuth() {
        cbDelegate.delegate = self

        cbManager.delegate = cbDelegate
        cbManager.scanForPeripherals(withServices: nil)
    }

    func requestLocationAuth() {

        let status = locationManager.authorizationStatus
        isLocationPermissionsErrorNeedManualSetup = false
        switch status {
        case .notDetermined:
            locDelegate.delegate = self
            locationManager.delegate = locDelegate
            locationManager.requestAlwaysAuthorization()
        case .restricted:
            isLocationPermissionsErrorNeedManualSetup = true
            return
        case .denied:
            isLocationPermissionsErrorNeedManualSetup = true
            return
        case .authorizedAlways:
            return
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        @unknown default:
            fatalError()
        }
    }

    private func updateGatewayPermissionsGranted() {
        gatewayPermissionsGranted = locationCanBeUsed && bluetoothCanBeUsed

    }
}

extension Permissions: CBCentralManagerStateDelegate {
    func bluetoothDidChangeAuthState(_ state: CBManagerAuthorization) {
        switch state {
        case .notDetermined:
            self.bluetoothCanBeUsed = false
        case .restricted:
            self.bluetoothCanBeUsed = false
        case .denied:
            self.bluetoothCanBeUsed = false
        case .allowedAlways:
            self.bluetoothCanBeUsed = true
        @unknown default:
            fatalError()
        }

        updateGatewayPermissionsGranted()
    }
}

extension Permissions: CBLocationManagerStateDelegate {
    func locationManagerAuthStateDidChange(_ state: CLAuthorizationStatus) {

        switch state {
        case .notDetermined:
            locationWhenInUseGranted = false
            locationAlwaysGranded = false
//            locationCanBeUsed = false
        case .restricted:
            locationWhenInUseGranted = false
            locationAlwaysGranded = false
//            locationCanBeUsed = false
        case .denied:
            locationWhenInUseGranted = false
            locationAlwaysGranded = false
//            locationCanBeUsed = false
        case .authorizedAlways:
            locationAlwaysGranded = true
        case .authorizedWhenInUse:
            locationWhenInUseGranted = true
        @unknown default:
            fatalError()
        }

        locationCanBeUsed = locationWhenInUseGranted || locationAlwaysGranded

        updateGatewayPermissionsGranted()
    }
}

// MARK: - BLE Delegate
protocol CBCentralManagerStateDelegate: AnyObject {
    func bluetoothDidChangeAuthState(_ state: CBManagerAuthorization)
}

@objc class CBCentralManagerDelegateObject: NSObject {
    weak var delegate: CBCentralManagerStateDelegate?
}

extension CBCentralManagerDelegateObject: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

        let overallState = CBCentralManager.authorization
        delegate?.bluetoothDidChangeAuthState(overallState)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let uids: [CBUUID] = (dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID]) ?? [CBUUID]()
        print("Permissions centralManager willRestoreState -> uids: \(uids)")
    }
}

// MARK: - LocationManager Delegate
protocol CBLocationManagerStateDelegate: AnyObject {
    func locationManagerAuthStateDidChange(_ state: CLAuthorizationStatus)
}

@objc class CBLocationManagerDelegateObject: NSObject {
    weak var delegate: CBLocationManagerStateDelegate?
}

extension CBLocationManagerDelegateObject: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        delegate?.locationManagerAuthStateDidChange(manager.authorizationStatus)
    }
}
