//
//  GatewayDataEncoder.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 26.05.2022.
//

import Foundation

import WiliotCore

public protocol GatewayDataType :Encodable {
    var gatewayId:   String {get}
    var gatewayType: String {get}
    var timestamp:   TimeInterval {get}
    var location:    WLTLocation? {get}
}

protocol GatewayCapabilitiesMessageType: Encodable { }

public final class GatewayDataEncoder {
    typealias GWData = GatewayDataType
    static let encoder = JSONEncoder()
    
    private static func encode<GWData>(_ gatewayData:GWData) throws -> Data where GWData:Encodable {
        let resultData = try encoder.encode(gatewayData)
        return resultData
    }
    
    private static func encodeDataToString(_ data:Data) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CodingError.encodingFailed(ValueReadingError.invalidValue("GatewayDataEncoder Failed to encode Data to String"))
        }
        
        return string
    }
    
    public static func tryEncodeToString<GWData>(_ gatewayData:GWData) throws -> String where GWData:Encodable {
        let data = try encode(gatewayData)
        let string = try encodeDataToString(data)
        return string
    }
}


extension GatewayDataEncoder {
    static func tryEncodeToString(_ message:GatewayCapabilitiesMessageType) throws -> String {
        let data = try encoder.encode(message)
        guard let string = String(data:data, encoding: .utf8) else {
            throw CodingError.encodingFailed(ValueReadingError.invalidValue("GatewayDataEncoder Failed to encode Data to String"))
        }
        
        return string
    }
}
