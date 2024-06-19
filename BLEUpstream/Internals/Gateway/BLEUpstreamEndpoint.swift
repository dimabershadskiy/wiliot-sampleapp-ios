//
//  BLEUpstreamEndpoint.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 08.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

public struct BLEUpstreamEndpoint {
    internal let host:String
    internal let port:UInt16
    private init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

extension BLEUpstreamEndpoint {
    
    public static func test() -> BLEUpstreamEndpoint {
        BLEUpstreamEndpoint(host: TestStage.endpoint, 
                            port: TestStage.port)
    }
    
    public static func dev() -> BLEUpstreamEndpoint {
        BLEUpstreamEndpoint(host: DevStage.endpoint,
                            port: DevStage.port)
    }
    
    public static func prod() -> BLEUpstreamEndpoint {
        BLEUpstreamEndpoint(host: ProdStage.endpoint,
                            port: ProdStage.port)
    }
    
    public static func gcpTest() -> BLEUpstreamEndpoint {
        BLEUpstreamEndpoint(host: TestStageGCP.endpoint,
                            port: TestStageGCP.port)
    }
    
    public static func gcpDev() -> BLEUpstreamEndpoint {
        BLEUpstreamEndpoint(host: DevStageGCP.endpoint,
                            port: DevStageGCP.port)
    }
    
    public static func gcpProd() -> BLEUpstreamEndpoint {
        BLEUpstreamEndpoint(host: ProdStageGCP.endpoint,
                            port: ProdStageGCP.port)
    }
    
    public static func custom(host:String, port:UInt16) -> BLEUpstreamEndpoint {
        BLEUpstreamEndpoint(host: host, port: port)
    }
}


fileprivate let kDefaultPort:UInt16 = 8883

fileprivate extension BLEUpstreamEndpoint {
    
    struct ProdStage {
        static let endpoint:String = "mqtt.us-east-2.prod.wiliot.cloud" //"mqttv2.wiliot.com"
        static let port: UInt16 = kDefaultPort //1883 //8883
    }

//    struct ProdLegacyStage {
//        static let endpoint:String = "mqttv2.wiliot.com"
//        static let port: UInt16 = 8883
//    }
    
    struct DevStage {
        static let endpoint:String = "mqtt.us-east-2.dev.wiliot.cloud"
        static let port: UInt16 = kDefaultPort //1883
    }
    
    struct TestStage {
        static let endpoint:String = "mqtt.us-east-2.test.wiliot.cloud"
        static let port:UInt16 = kDefaultPort// 1883
    }
   
    struct TestStageGCP {
        static let endpoint:String = "mqtt.us-central1.test.gcp.wiliot.cloud"
        static let port:UInt16 = kDefaultPort //1883
    }
    
    struct DevStageGCP {
        static let endpoint:String = "mqtt.us-central1.dev.gcp.wiliot.cloud"
        static let port:UInt16 = kDefaultPort //1883
    }
    
    struct ProdStageGCP {
        static let endpoint:String = "mqtt.us-central1.prod.gcp.wiliot.cloud"
        static let port:UInt16 = kDefaultPort // 1883
    }
    
//    static func forStage(_ stage:CloudStage) -> MQTTEndpoint {
//        
//        var port:UInt16 = 0
//        var endpoint = ""
//        
//        switch stage {
//        case .prod:
//            endpoint = ProdStage.endpoint
//            port = ProdStage.port
////        case .prodLegacy:
////            endpoint = ProdLegacyStage.endpoint
////            port = ProdLegacyStage.port
//        case .dev:
//            endpoint = DevStage.endpoint
//            port = DevStage.port
//        case .test:
//            endpoint = TestStage.endpoint
//            port = TestStage.port
//        case .gcpProd:
//            endpoint = ProdStageGCP.endpoint
//            port = ProdStageGCP.port
//        case .gcpDev:
//            endpoint = DevStageGCP.endpoint
//            port = DevStageGCP.port
//        case .gcpTest:
//            endpoint = TestStageGCP.endpoint
//            port = TestStageGCP.port
//        }
//        
//        return MQTTEndpoint(host:endpoint, port:port)
//    }
}
