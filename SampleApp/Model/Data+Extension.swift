//
//  Data+Extension.swift

import Foundation

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
        static let spaceSeparated = HexEncodingOptions(rawValue: 1 << 1)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined(separator: options.contains(.spaceSeparated) ? " " : "")
    }

    func getManufacturerIdString() -> String {
        let manufactureID = UInt16(self[0]) + UInt16(self[1]) << 8
        let manufactureIDString = String(format: "%04X", manufactureID)
        return manufactureIDString
    }
}

public extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

extension Data {
    static func dummyDataOfLength(_ count: Int) -> Data {
        let dummy = [UInt8](repeating: 0x0, count: count)
        let dummyData = Self(bytes: dummy, count: count)
        return dummyData
    }
}
