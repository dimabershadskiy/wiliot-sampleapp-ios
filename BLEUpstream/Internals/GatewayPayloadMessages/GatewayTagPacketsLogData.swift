//
//  GatewayTagPacketsLogData.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 09.11.2022.
//

import Foundation

import WiliotCore

public struct GatewayTagPacketsLogData:GatewayDataType {
    //GatewayDataType
    public var location:WLTLocation?
    public let gatewayId: String// = Device.deviceId
    public let gatewayType: String = "mobile"
    public let timestamp: TimeInterval = Date().millisecondsFrom1970()
    
    //other
    public let gatewayLogs:[String]
}

//extension GatewayTagPacketsLogData {
//    public init(location: WLTLocation? = nil, gatewayId: String, gatewayLogs: [String]) {
//        self.init(location: location, gatewayId: gatewayId, gatewayLogs: gatewayLogs)
////        self.location = location
////        self.gatewayId = gatewayId
////        self.gatewayLogs = gatewayLogs
//    }
//}
