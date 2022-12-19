//
//  Packet.swift

import Foundation

struct TagPacketData: Encodable {
    let payload: String
    /// timestamp in milliseconds
    var timestamp: TimeInterval = Date().milisecondsFrom1970()
    var location: Location?
    var acceleration: AccelerationData?
    var bridgeId: String?
    var groupId: String?
    var sequenceId: Int?
    var nfpkt: Int?
    var rssi: Int?
}
