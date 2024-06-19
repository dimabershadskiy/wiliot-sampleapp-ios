//
//  GatewayCapabilitiesMessage.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 31.01.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

// MARK: - GatewayCapabilitiesMessage
struct GatewayCapabilitiesMessage: GatewayCapabilitiesMessageType {
    
    let bridgeOtaUpgradeSupported:Bool = false
    let downlinkSupported: Bool = false
    let gatewayConf: GatewayConf
    let gatewayType: String = "mobile"
    let melOtaUpgradeSupported :Bool = false
    let tagMetadataCouplingSupported: Bool = true//false
    let fwUpgradeSupported: Bool = false //WMB-1464
    
    
    struct GatewayConf: Encodable {
        let additional: Additional
        let apiVersion: Int = 202
        let gatewayVersion: String
        
        
        struct Additional: Encodable {
            let pacingPeriod: Int
            let versionName: String
        }
    }
}

extension GatewayCapabilitiesMessage {
    static func createWith(applicationVersion:String, pacingPeriod:Int) -> GatewayCapabilitiesMessage {
        return GatewayCapabilitiesMessage(gatewayConf:
                                            GatewayConf(additional:
                                                            GatewayConf.Additional(pacingPeriod: pacingPeriod,
                                                                       versionName: applicationVersion),
                                                        gatewayVersion: applicationVersion))
    }
}
