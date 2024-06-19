//
//  ResolveInfo.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 19.05.2022.
//

import Foundation

public struct PayloadContainer: Encodable {
    let payload:String
    let timestamp:TimeInterval
    public init(payload: String, timestamp: TimeInterval) {
        self.payload = payload
        self.timestamp = timestamp
    }
}

public struct ResolveInfo : Encodable {
    
    public static var deviceId:String = ""
    static var deviceGatewayType = "mobile"
    
    var location:WLTLocation?
    let gatewayId: String //= Device.deviceId
    let gatewayType: String //= "mobile"
    let timestamp: TimeInterval //= Date().milisecondsFrom1970()
    var packets: [PayloadContainer]
    
    private init(location: WLTLocation?, gatewayId: String, gatewayType: String, packets: [PayloadContainer]) {
        self.location = location
        self.gatewayId = gatewayId
        self.gatewayType = gatewayType
        self.packets = packets
        self.timestamp = (Date().timeIntervalSince1970 * 1000).rounded()
    }
    
    public static func defaultWith(payloads:[PayloadContainer], location:WLTLocation?) throws -> ResolveInfo {
        guard !payloads.isEmpty else {
            throw ValueReadingError.invalidValue("Empty Payloads")
        }
        
        guard !Self.deviceId.isEmpty else {
            throw ValueReadingError.missingRequiredValue("No Device Id was set")
        }
        
        let instance = ResolveInfo(location: location, 
                                   gatewayId: Self.deviceId,
                                   gatewayType: Self.deviceGatewayType,
                                   packets: payloads)
        
        return instance
    }
}


