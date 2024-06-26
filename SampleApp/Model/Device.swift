

import Foundation
import UIKit

fileprivate let kDeviceIdKey:String = "SampleAppDeviceId"

class Device {
    
    static var deviceId:String {
        if let storedId = UserDefaults.standard.string(forKey: kDeviceIdKey) {
            return storedId
        }
        let newDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        UserDefaults.standard.set(newDeviceId, forKey: kDeviceIdKey)
        UserDefaults.standard.synchronize()
        return newDeviceId
    }
}
