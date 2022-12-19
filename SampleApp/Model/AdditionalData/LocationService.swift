//
//  LocationService.swift

import Foundation
import CoreLocation
import Combine

class LocationService {
    private var locationManager: CLLocationManager = CLLocationManager()
    private lazy var locDelegate: LocationManagerDelegate = {
        let delegate = LocationManagerDelegate(target: self)
        return delegate
    }()
    private lazy var beacon: iBeacon = iBeacon()
    private lazy var targetBeaconsUUIDs: [UUID] = [beacon.targetUUID]
    var lastLocation: CLLocation?

    deinit {
        print("+ LocationService deinit +")
    }

}

extension LocationService {

    var currentLocation: CLLocation? {
        locationManager.location
    }
    func startLocationUpdates() {
        if locationManager.delegate == nil {
            locationManager.delegate = self.locDelegate
        }

        locationManager.startUpdatingLocation()
        if let currentLoc = locationManager.location {
            lastLocation = currentLoc
        }
    }

    func stopLocationUpdates() {

        print("LocationService stopLocationUpdates ")

        if locationManager.delegate == nil {
            locationManager.delegate = self.locDelegate
        }

        locationManager.stopUpdatingLocation()
    }

    func startRanging() {

        if locationManager.delegate == nil {
            locationManager.delegate = self.locDelegate
        }

        let region: CLBeaconRegion = beacon.clBeaconRegion
        locationManager.startMonitoring(for: region)
        locationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: region.uuid))

        startedRangingForBeacons(manager: locationManager)
        startedMonitoringForBeacons(manager: locationManager)
    }

    func stopRanging() {
        if locationManager.delegate == nil {
            locationManager.delegate = self.locDelegate
        }

        let region: CLBeaconRegion = beacon.clBeaconRegion
        locationManager.stopMonitoring(for: region)
        locationManager.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: region.uuid))

    }

    private func startedRangingForBeacons(manager: CLLocationManager) {
        print("\(self) \(#function) Turning on ranging beacons...")

        if !CLLocationManager.locationServicesEnabled() {
            print("Couldn't turn on ranging: Location services are not enabled.")
            return
        }

        if !CLLocationManager.isRangingAvailable() {
            print("Couldn't turn on ranging: Ranging is not available.")
            return
        }

        if !manager.rangedBeaconConstraints.isEmpty {
            print("Didn't turn on ranging: Ranging already on.")
            return
        }
    }

    private func startedMonitoringForBeacons(manager: CLLocationManager) {
        print("\(self) \(#function) Turning on monitoring for beacons...")

        if !CLLocationManager.locationServicesEnabled() {
            print("\(self) \(#function) Couldn't turn on monitoring: Location services are not enabled.")
            return
        }

        if !CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) {
            print("\(self) \(#function) Couldn't turn on region monitoring: Region monitoring is not available for CLBeaconRegion class.")
            return
        }
    }
}

// MARK: - Location Region
extension LocationService: LocationManagerDelegateTarget {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {

        let locationAuthState = manager.authorizationStatus

        switch locationAuthState {
        case .authorizedWhenInUse:
            startRanging()
        case .notDetermined:
            stopRanging()
#if targetEnvironment(simulator)
break
#endif
//            fatalError("LocationService tried to use CLLocationManager before acquired Location_Permissions")
        case .restricted:
            stopRanging()
#if targetEnvironment(simulator)
break
#endif
//            fatalError("LocationService tried to use CLLocationManager before acquired Location_Permissions")
        case .denied:
            stopRanging()
#if targetEnvironment(simulator)
break
#endif
//            fatalError("LocationService tried to use CLLocationManager before acquired Location_Permissions")
        case .authorizedAlways:
#if targetEnvironment(simulator)
break
#endif
            startRanging()

        @unknown default:
            fatalError("LocationService Unhandled 'authorizationStatus' in Location Authorization status")
        }
    }

    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        print(" -> did range beacons. in region <- ")
    }

    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {

        if beacons.isEmpty {
            return
        }

        let receivedUUIDS = Set(beacons.map({$0.uuid}))
        let intersection = Set(targetBeaconsUUIDs).intersection(receivedUUIDS)
        if !intersection.isEmpty {
            print(" -> did range beacons. constraint(s): \(intersection.map({$0.uuidString})) <- ")

        }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        var readable = ""
        switch state {
        case .unknown:
            readable = "UNKNOWN"
        case .outside:
            readable = "OUTSIDE"
        case .inside:
            readable = "INSIDE"
        default:
            break
        }
        print(" --> didDetermineState : \(readable) <--")
        if state == .inside {

        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print(" -> did Fail monitoring: \(error) <- ")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        print(" -> did Pause location updates. lastKnownLocation: \(String(describing: manager.location)) <- ")
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        print(" -> did Pause resume location updates <- ")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print(" -> did exit region. in region <- ")
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print(" -> did enter region. in region <- ")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

}

// MARK: - Ranging,Location, iBeacon

private protocol LocationManagerDelegateTarget: AnyObject {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion)
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint)
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion)
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error)
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager)
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
}

@objc private class LocationManagerDelegate: NSObject {
    weak var target: LocationManagerDelegateTarget?
    init(target: LocationManagerDelegateTarget) {
        self.target = target
    }
}

extension LocationManagerDelegate: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if !locations.isEmpty {
            target?.locationManager(manager, didUpdateLocations: locations)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        target?.locationManagerDidChangeAuthorization(manager)
    }

    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        if beacons.isEmpty {
            return
        }

        target?.locationManager(manager, didRangeBeacons: beacons, in: region)
    }

    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        if beacons.isEmpty {
            return
        }

        target?.locationManager(manager, didRange: beacons, satisfying: beaconConstraint)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        target?.locationManager(manager, didEnterRegion: region)

    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        target?.locationManager(manager, didExitRegion: region)
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        target?.locationManagerDidPauseLocationUpdates(manager)
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        target?.locationManagerDidResumeLocationUpdates(manager)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        target?.locationManager(manager, monitoringDidFailFor: region, withError: error)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        target?.locationManager(manager, didDetermineState: state, for: region)

    }
}
