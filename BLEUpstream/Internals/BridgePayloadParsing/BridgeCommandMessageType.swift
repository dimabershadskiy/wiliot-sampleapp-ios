//
//  BridgeCommandMessageType.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 12.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

///sets 1 byte of config type
public enum BLEUPacketMessageType: UInt8, Codable {
    case empty = 0x00
    case assign = 0x01
    case heartBeat = 0x02
    case ledBlink = 0x04
    case configSet = 0x05
    case configGet = 0x06
//    case action = 0x07 // deprecated
    
    ///uses only 4 least bits from the byte (shift left by 4, then shift right by 4)
    public static func fromDataByte(_ byte:UInt8) -> BLEUPacketMessageType? {
        let cleanedValue = (byte << 4) >> 4
        return BLEUPacketMessageType(rawValue: cleanedValue)
    }
}
