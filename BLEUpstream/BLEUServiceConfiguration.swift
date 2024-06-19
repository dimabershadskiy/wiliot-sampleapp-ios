//
//  BLEUConfig.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 08.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

import WiliotCore

public struct BLEUServiceConfiguration {
    
    public let accountId: NonEmptyCollectionContainer<String>
    public let appVersion: NonEmptyCollectionContainer<String>
    public let endpoint: BLEUpstreamEndpoint
    public let deviceId: NonEmptyCollectionContainer<String>
    public let pacingEnabled:Bool
    public private(set) var tagPayloadsLoggingEnabled: Bool
    public let coordinatesContainer: any LocationCoordinatesContainer
    public let externalReceivers: BLEUExternalReceivers
    public private(set) var externalLogger: (any ExternalMessageLogging)?
    
    public init(accountId: NonEmptyCollectionContainer<String>,
                appVersion: NonEmptyCollectionContainer<String>,
                endpoint: BLEUpstreamEndpoint,
                deviceId: NonEmptyCollectionContainer<String>,
                pacingEnabled:Bool,
                tagPayloadsLoggingEnabled: Bool,
                coordinatesContainer: any LocationCoordinatesContainer,
                externalReceivers: BLEUExternalReceivers,
                externalLogger: (any ExternalMessageLogging)?) {
        
        self.accountId = accountId
        self.appVersion = appVersion
        self.endpoint = endpoint
        self.deviceId = deviceId
        
        self.pacingEnabled = pacingEnabled
        self.tagPayloadsLoggingEnabled = tagPayloadsLoggingEnabled
        
        self.coordinatesContainer = coordinatesContainer
        self.externalReceivers = externalReceivers
        self.externalLogger = externalLogger
    }
}

extension BLEUServiceConfiguration {
    mutating func setTagPayloadsLoggingEnabled(_ isEnabled:Bool) {
        self.tagPayloadsLoggingEnabled = isEnabled
    }
}

public struct BLEUExternalReceivers {
    public private(set) var bridgesUpdater: (any ExternalBridgePacketsReceiver)?
    public private(set) var blePixelResolver: (any ExternalPixelResolver)?
    public private(set) var pixelsRSSIUpdater: (any ExternalPixelRSSIUpdatesReceiver)?
    public private(set) var resolvedPacketsInfoReceiver: (any ExternalResolvedPacketReceiver)?
    
    public init(bridgesUpdater: (any ExternalBridgePacketsReceiver)? = nil,
                blePixelResolver: (any ExternalPixelResolver)? = nil,
                pixelsRSSIUpdater: (any ExternalPixelRSSIUpdatesReceiver)? = nil,
                resolvedPacketsInfoReceiver: (any ExternalResolvedPacketReceiver)? = nil) {
        
        self.bridgesUpdater = bridgesUpdater
        self.blePixelResolver = blePixelResolver
        self.pixelsRSSIUpdater = pixelsRSSIUpdater
        self.resolvedPacketsInfoReceiver = resolvedPacketsInfoReceiver
    }
}
