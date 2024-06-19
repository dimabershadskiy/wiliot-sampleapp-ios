//
//  BLEUPacketsRouterConfiguration.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 09.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
struct BLEUPacketsRouterConfiguration {
    var coordinatesContainer: any LocationCoordinatesContainer
    var tagPacketsReceiver: any TagPacketsReceiving
    var thirdPartyDataPacketsReceiver: any ThirdPartyPacketsReceiving
    var sideInfoPacketsReceiver: any SideInfoPacketsReceiving
    var combinedPacketsReceiver: any CombinedPacketsReceiving
    var bridgeMessagesPacketsReceiver: any BridgePayloadsReceiving
    var tagPacketsLogsSender: (any TagPacketsPayloadLogSender)?
    var externatOutputs:BLEUExternalReceivers
}
