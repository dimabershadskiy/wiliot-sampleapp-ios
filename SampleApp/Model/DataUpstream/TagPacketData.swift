//
//  Packet.swift


import Foundation

struct TagPacketData : Encodable {
    let payload: String
    ///timestamp in milliseconds
    var timestamp: TimeInterval = Date().milisecondsFrom1970()
    var bridgeId: String?
    var groupId: String?
    var sequenceId: Int64?
    var nfpkt:Int?
    var rssi:Int?
    var isSensor:Bool? //for thirdParty glued packets otherwise - nil
    var sensorServiceId:String? //for thirt party glued packets
    var sensorId:String? //for thirdparty glued packets
    var isScrambled:Bool? //for thirdparty glued packets
    var isEmbedded:Bool?
    
    enum CodingKeys: CodingKey {
        case payload
        case timestamp
        case bridgeId
        case groupId
        case sequenceId
        case nfpkt
        case rssi
        case isSensor
        case sensorServiceId
        case sensorId
        case isScrambled
        case isEmbedded
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.payload, forKey: .payload)
        try container.encode(self.timestamp, forKey: .timestamp)
        try container.encodeIfPresent(self.bridgeId, forKey: .bridgeId)
        try container.encodeIfPresent(self.groupId, forKey: .groupId)
        try container.encodeIfPresent(self.sequenceId, forKey: .sequenceId)
        try container.encodeIfPresent(self.nfpkt, forKey: .nfpkt)
        try container.encodeIfPresent(self.rssi, forKey: .rssi)
        try container.encodeIfPresent(self.isSensor, forKey: .isSensor)
        try container.encodeIfPresent(self.sensorServiceId, forKey: .sensorServiceId)
        try container.encodeIfPresent(self.sensorId, forKey: .sensorId)
        try container.encodeIfPresent(self.isScrambled, forKey: .isScrambled)
        try container.encodeIfPresent(self.isEmbedded, forKey: .isEmbedded)
    }
}


extension TagPacketData {
    func fromOtherPacketDataWithSequenceId(_ sequenceId:Int64) -> TagPacketData {
        return TagPacketData(payload: self.payload,
                             timestamp: self.timestamp,
                             bridgeId: self.bridgeId,
                             groupId: self.groupId,
                             sequenceId: sequenceId,
                             nfpkt: self.nfpkt,
                             rssi: self.rssi,
                             isSensor: self.isSensor,
                             sensorServiceId: self.sensorServiceId,
                             sensorId: self.sensorId,
                             isScrambled: self.isScrambled,
                             isEmbedded: self.isEmbedded)
    }
}

