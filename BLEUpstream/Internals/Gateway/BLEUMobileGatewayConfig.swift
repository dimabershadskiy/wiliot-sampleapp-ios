//
//  BLEUMobileGatewayConfig.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 09.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
import WiliotCore

struct BLEUMobileGatewayConfig {
    let locationSource:LocationCoordinatesContainer
    let endpoint:BLEUpstreamEndpoint
    let accountId:NonEmptyCollectionContainer<String>
    let appVersion:NonEmptyCollectionContainer<String>
    let gatewayId:NonEmptyCollectionContainer<String>
    let connectionToken:NonEmptyCollectionContainer<String>
}
