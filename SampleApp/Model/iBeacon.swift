//
//  iBeacon.swift

import Foundation
import CoreLocation

class iBeacon {

    private enum K {
        static let uid = "416C0120-5960-4280-A67C-A2A9BB166D0F"
        static let identifier = "com.wiliotbeacon.identifier"
    }

    var clBeaconRegion: CLBeaconRegion {
        let uid = UUID(uuidString: K.uid)!
        let identifier = K.identifier
        let region = CLBeaconRegion(uuid: uid, identifier: identifier)
        region.notifyEntryStateOnDisplay = true
        region.notifyOnExit = true
        region.notifyOnEntry = true
        return region
    }

    var targetUUID: UUID {
        return clBeaconRegion.uuid
    }
}
