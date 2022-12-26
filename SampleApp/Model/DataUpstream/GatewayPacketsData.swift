//
//  GatewayPacketsData.swift

import Foundation

// MARK: - Resolved Tags Info
struct GatewayPacketsData: GatewayDataType {
    let location: Location?
    let gatewayId: String = Device.deviceId
    let gatewayType: String = "Wiliot iPhone"
    let timestamp: TimeInterval = Date().milisecondsFrom1970()
    let packets: [TagPacketData]?
}
