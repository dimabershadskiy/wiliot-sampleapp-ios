//
//  BLEPacket.swift

import Foundation
struct BLEPacket {
    let isManufacturer: Bool
    let uid: UUID
    let rssi: Int
    let data: Data
    let timeStamp = Date().milisecondsFrom1970()
}

extension BLEPacket {
    var packetId: String {
        return data.suffix(4).hexEncodedString()
    }

    var rotatingId: String? {
        guard data.count >= 15 else {
            return nil
        }

        let range: Range<Int> = isManufacturer ? 9..<15 : 0..<6
        let rotatingIdData = data.subdata(in: range)
        return rotatingIdData.hexEncodedString()
    }
}
