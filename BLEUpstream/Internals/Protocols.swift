//
//  Protocols.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 06.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
import Combine
import CoreLocation

import WiliotCore





protocol TagPayloadByUUIDReceiver {
    func receiveTagPayloadsByUUID(_ pacingPackets: [UUID : String])
    func startHandlingPayloads()
    func stopHandlihgPayloads()
}


public protocol LocationCoordinatesContainer {
    var currentLocationCoordinates:CLLocationCoordinate2D? {get}
}



//MARK: -
protocol SideInfoPacketsReceiving {
    func receiveSideInfoPacket(_ sideInfo:BLEPacket)
}

protocol CombinedPacketsReceiving {
    func receiveCombinedPacket(_ combinedPacket:BLEPacket)
}

protocol TagPacketsReceiving {
    func receiveTagPacket(_ tagPacket:BLEPacket)
}

protocol BridgePayloadsReceiving {
    func receiveBridgeMessagePayloadPacket(_ bridgeMessagePacket:BLEPacket)
}

protocol ThirdPartyPacketsReceiving {
    func receiveThirdPartyDataPacket(_ thirdPartyDataPacket:BLEPacket)
}

//MARK: -


protocol TagPacketsPayloadLogSender {
    func sendLogPayloads(_ payloads:NonEmptyCollectionContainer<[String]>)
}

protocol TagPacketsSending {
    func sendPacketsInfo(_ infoContainer:NonEmptyCollectionContainer<[TagPacketData]>)
}


//MARK: -

protocol PacketsPacing {
    func receivePacketsByUUID(_ pacingPacketsInfo:[UUID:TagPacketData])
    func setUUIDToExternalTagIdCorrespondence(_ info:[String:UUID])
}
