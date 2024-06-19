//
//  BLEPacket+Extensions.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 28.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
import WiliotCore

extension BLEPacket {
    func isHeartbeatPacket() -> Bool {
        guard BeaconDataReader.isBeaconDataBridgeToGWmessage(self.data) else {
            return false
        }
        
        let valuesData = self.data.subdata(in: 5..<29)
        
        let messageType = valuesData[0]
        
        return messageType == UInt8(0x02) //heartbeat
    }
    
    func firmwareAPIversionFromHeartbeat() -> Int {
        
        let valuesData = self.data.subdata(in: 5..<29)
        
        let apiVersionByte = valuesData[1]
        
        return Int(apiVersionByte)
    }
    
    func is_ModuleIFV_Packet() -> Bool {
        guard BeaconDataReader.isBeaconDataBridgeToGWmessage(self.data) else {
            return false
        }
        
        let targetValue:UInt8 = self.data[5]
        let mask:UInt8 = 0b00010000
        
        let isMaskValid:Bool = (targetValue & mask) == mask
        
        return isMaskValid
    }
}
