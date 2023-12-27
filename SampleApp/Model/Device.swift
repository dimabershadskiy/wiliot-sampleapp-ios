

import Foundation
import UIKit

class Device {
    static var deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
}
