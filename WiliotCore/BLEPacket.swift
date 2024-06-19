//
//  BLEPacket.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 20.05.2022.
//

import Foundation
public struct BLEPacket {
    public let isManufacturer:Bool
    public let uid:UUID
    public let rssi:Int
    public let data:Data
    public let timeStamp:Double// = Date().millisecondsFrom1970()
    
    public init(isManufacturer: Bool, uid: UUID, rssi: Int, data: Data, timeStamp: Double) {
        self.isManufacturer = isManufacturer
        self.uid = uid
        self.rssi = rssi
        self.data = data
        self.timeStamp = timeStamp
    }
}

extension BLEPacket {
    ///hex encoded String used last 4 bytes of the BLE payload
    public var packetId:String {
        return data.suffix(4).stringHexEncoded()
    }
}
