//
//  Packet.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 19.05.2022.
//

import Foundation

public struct TagPacketData : Encodable {
    public let payload: String
    ///timestamp in milliseconds
    public var timestamp: TimeInterval = Date().millisecondsFrom1970()

//    var acceleration: AccelerationData?
    public var bridgeId: String?
    public var groupId: String?
    public var sequenceId: Int64?
    public var nfpkt:Int?
    public var rssi:Int?
    public var isSensor:Bool? //for thirdParty glued packets otherwise - nil
    public var sensorServiceId:String? //for thirt party glued packets
    public var sensorId:String? //for thirdparty glued packets
    public var isScrambled:Bool? //for thirdparty glued packets
    public var isEmbedded:Bool? //for thirdparty glued packets
    public var aliasBridgeId:String?
    
    enum CodingKeys: CodingKey {
        case payload
        case timestamp

//        case acceleration
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
        case aliasBridgeId
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.payload, forKey: .payload)
        try container.encode(self.timestamp, forKey: .timestamp)

//        try container.encodeIfPresent(self.acceleration, forKey: .acceleration)
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
        try container.encodeIfPresent(self.aliasBridgeId, forKey: .aliasBridgeId)
        
    }
    
    
}

extension TagPacketData {
    public func fromOtherPacketDataWithSequenceId(_ sequenceId:Int64) -> TagPacketData {
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
                             isEmbedded: self.isEmbedded,
                             aliasBridgeId: self.aliasBridgeId)
    }
    
    public init (payload:String, timeStamp:TimeInterval, rssi:Int) {
        self.payload = payload
        self.timestamp = timeStamp
        self.rssi = rssi
    }
    
    public init(payload:String, timeStamp:TimeInterval, rssi:Int, aliasBridgeId:String) {
        self.payload = payload
        self.timestamp = timeStamp
        self.rssi = rssi
        self.aliasBridgeId = aliasBridgeId
    }
    
    
    public init(payload:String, timeStamp:TimeInterval, nfpkt:Int, rssi:Int, bridgeId:String) {
        self.payload = payload
        self.timestamp = timeStamp
        self.nfpkt = nfpkt
        self.rssi = rssi
        self.bridgeId = bridgeId
    }
    
    
    public init(payload:String,
                timeStamp:TimeInterval,
                bridgeId:String,
                nfpkt:Int,
                rssi:Int,
                isSensor:Bool,
                sensorServiceId:String,
                sensorId:String,
                isScrambled:Bool,
                isEmbedded:Bool) {
        
        self.payload = payload
        self.timestamp = timeStamp
        self.bridgeId = bridgeId
        self.nfpkt = nfpkt
        self.rssi = rssi
        self.isSensor = isSensor
        self.sensorServiceId = sensorServiceId
        self.sensorId = sensorId
        self.isScrambled = isScrambled
        self.isEmbedded = isEmbedded
    }
}
