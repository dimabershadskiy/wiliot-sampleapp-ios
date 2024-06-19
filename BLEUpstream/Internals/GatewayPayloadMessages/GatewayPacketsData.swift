//
//  GatewayPacketsData.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 26.05.2022.
//

import Foundation

import WiliotCore
//MARK: - Resolved Tags Info
struct GatewayPacketsData:GatewayDataType {
    var location:WLTLocation?
    let gatewayId: String //= Device.deviceId
    let gatewayType: String = "mobile"
    let timestamp: TimeInterval = Date().millisecondsFrom1970()
    var packets: [TagPacketData]?
}
