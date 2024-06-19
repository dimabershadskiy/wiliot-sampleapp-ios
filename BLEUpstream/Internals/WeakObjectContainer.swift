//
//  WeakObjectContainerswift.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 09.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

import WiliotCore

class WeakObjectContainer<T:AnyObject> {
    private weak var object:T?
    
    init(_ object: T) {
        self.object = object
    }
}

//MARK: -
//MARK: - WiliotMQTTClientDelegate
extension WeakObjectContainer:WiliotMQTTClientDelegate where T:WiliotMQTTClientDelegate {
    func mqttClientDidConnect() {
        object?.mqttClientDidConnect()
    }
    
    func mqttClientIsConnecting() {
        object?.mqttClientIsConnecting()
    }
    
    func mqttClientDidDisconnect() {
        object?.mqttClientDidDisconnect()
    }
    
    func mqttClientDidEncounterError(_ error: Error, willAttemptToReconnect: Bool) {
        object?.mqttClientDidEncounterError(error, willAttemptToReconnect: willAttemptToReconnect)
    }
    
}

//MARK: - TagPacketsSending
extension WeakObjectContainer:TagPacketsSending where T:TagPacketsSending {
    func sendPacketsInfo(_ infoContainer: WiliotCore.NonEmptyCollectionContainer<[TagPacketData]>) {
        object?.sendPacketsInfo(infoContainer)
    }
}

//MARK: - TagPacketsPayloadLogSender
extension WeakObjectContainer:TagPacketsPayloadLogSender where T:TagPacketsPayloadLogSender {
    func sendLogPayloads(_ payloads: WiliotCore.NonEmptyCollectionContainer<[String]>) {
        object?.sendLogPayloads(payloads)
    }
}

//MARK: - TagPacketsReceiving
extension WeakObjectContainer:TagPacketsReceiving where T:TagPacketsReceiving {
    func receiveTagPacket(_ tagPacket: BLEPacket) {
        object?.receiveTagPacket(tagPacket)
    }
}

//MARK: - SideInfoPacketsReceiving
extension WeakObjectContainer:SideInfoPacketsReceiving where T:SideInfoPacketsReceiving {
    func receiveSideInfoPacket(_ sideInfo: BLEPacket) {
        object?.receiveSideInfoPacket(sideInfo)
    }
}

//MARK: - CombinedPacketsReceiving
extension WeakObjectContainer:CombinedPacketsReceiving where T:CombinedPacketsReceiving {
    func receiveCombinedPacket(_ combinedPacket: BLEPacket) {
        object?.receiveCombinedPacket(combinedPacket)
    }
}

extension WeakObjectContainer:PacketsPacing where T:PacketsPacing {
    func setUUIDToExternalTagIdCorrespondence(_ info: [String : UUID]) {
        object?.setUUIDToExternalTagIdCorrespondence(info)
    }
    
    func receivePacketsByUUID(_ pacingPacketsInfo: [UUID : TagPacketData]) {
        object?.receivePacketsByUUID(pacingPacketsInfo)
    }
}

//MARK: -
extension WeakObjectContainer:BridgePayloadsReceiving where T:BridgePayloadsReceiving {
    func receiveBridgeMessagePayloadPacket(_ bridgeMessagePacket: BLEPacket) {
        object?.receiveBridgeMessagePayloadPacket(bridgeMessagePacket)
    }
}

//MARK: - ThirdPartyPacketsReceiving
extension WeakObjectContainer:ThirdPartyPacketsReceiving where T: ThirdPartyPacketsReceiving {
    func receiveThirdPartyDataPacket(_ thirdPartyDataPacket: BLEPacket) {
        object?.receiveThirdPartyDataPacket(thirdPartyDataPacket)
    }
}
