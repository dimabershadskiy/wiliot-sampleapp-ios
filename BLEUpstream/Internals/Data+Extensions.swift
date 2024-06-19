//
//  Data+Extensions.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 12.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
extension Data {
    func getManufacturerIdString() -> String {
        let manufactureID = UInt16(self[0]) + UInt16(self[1]) << 8
        let manufactureIDString = String(format: "%04X", manufactureID)
        return manufactureIDString
    }
    
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
