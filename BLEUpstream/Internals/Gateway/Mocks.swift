//
//  Mocks.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 13.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
import CoreLocation

class LocationCoordinatesContainerDummy:LocationCoordinatesContainer {
    
    /// returns CLLocationCoordinate2D(latitude: 10, longitude: 10)
    var currentLocationCoordinates: CLLocationCoordinate2D? {
        return CLLocationCoordinate2D(latitude: 10, longitude: 10)
    }
    
}
