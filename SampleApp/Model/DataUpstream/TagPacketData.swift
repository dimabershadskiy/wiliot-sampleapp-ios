//
//  Packet.swift

import Foundation

struct TagPacketData: Encodable {
    let payload: String
    /// timestamp in milliseconds
    let timestamp: TimeInterval
    let location: Location?
    let acceleration: AccelerationData?
    let bridgeId: String?
    let groupId: String?
    let sequenceId: Int?
    let nfpkt: Int?
    let rssi: Int?
}
