//
//  GatewayPacketsData.swift


import Foundation


//MARK: - Resolved Tags Info
struct GatewayPacketsData:GatewayDataType {
    var location:Location?
    let gatewayId: String = Device.deviceId
    let gatewayType: String = "mobile"
    let timestamp: TimeInterval = Date().milisecondsFrom1970()
    var packets: [TagPacketData]?
}
