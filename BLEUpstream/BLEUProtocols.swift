//
//  BLEUProtocols.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 12.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
import Combine

import WiliotCore

//MARK: -
public protocol ExternalPixelResolver {
    func resolve(info: ResolveInfo) -> AnyPublisher<ResolvedPacket, Error>
}

public protocol ExternalPixelRSSIUpdatesReceiver {
    func receivePixelPacketRSSI(_ packetRSSI:Int, forTagExtId tagExternalId:String)
}

public protocol ExternalResolvedPacketReceiver {
    func receiveResolvedPacketInfo(_ resolvedPacketInfo:ResolvedPacket)
}

public protocol ExternalBridgePacketsReceiver {
    func receiveBridgePackets(_ containers:[UUIDWithIdContainer])
}


public struct UUIDWithIdContainer {
    public let id:String
    public let uuid:UUID
}

public protocol ExternalMessageLogging {
    func logMessage(_ message:String)
}
