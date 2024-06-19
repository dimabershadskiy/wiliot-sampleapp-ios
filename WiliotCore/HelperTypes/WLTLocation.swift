//
//  Location.swift
//  Wiliot
//
//  Created by Anatolii Zavialov on 11/26/18.
//  Copyright © 2018 Eastern Peak. All rights reserved.
//

import Foundation
import CoreLocation

/// Custom codable structure that represents geographical coordinate.
public struct WLTLocation: Codable {
    public var lat: Double
    public var lng: Double

    /// Initializer of Location structure.
    ///
    /// - Parameters:
    ///   - latitude: The latitude in degrees.
    ///   - longtitude: The longtitude in degrees.
    public init(latitude: Double, longtitude: Double) {
        lat = latitude
        lng = longtitude
    }
    
    enum CodingKeys: String, CodingKey {
        case lat
        case lng
    }
}

//MARK: - extension for encoding
extension WLTLocation {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lat.encodeUsingFraction(5), forKey: .lat)
        try container.encode(lng.encodeUsingFraction(5), forKey: .lng)
    }
}


extension WLTLocation {
//    init?(geoLocation clLocation:CLLocation?) {
//        guard let loc = clLocation else {
//            return nil
//        }
//        lat = loc.coordinate.latitude
//        lng = loc.coordinate.longitude
//    }
    
    public init(coordinate:CLLocationCoordinate2D) {
        self.lat = coordinate.latitude
        self.lng = coordinate.longitude
    }
    
    public static let zero : WLTLocation = WLTLocation(latitude: 0, longtitude: 0)
    
}

extension WLTLocation: Equatable, Hashable {
    public static func ==(lhs:WLTLocation, rhs:WLTLocation) -> Bool {
        return (lhs.lat != rhs.lat || lhs.lng != rhs.lng) ? false : true
    }
}

extension WLTLocation {
    public var longitudeText:String {
        String(lng)
    }
    
    public var latitudeText:String {
        String(lat)
    }

    /// up to first 9 sympols
    public var longitudeStrTrimmed:String {
        let fullString = String(lng)
        
        let trimmed = String(fullString.prefix(9))
        return trimmed
    }
    
    /// up to first 9 sympols
    public var latitudeStrTrimmed:String {
        let fullString = String(lat)
        
        let trimmed = String(fullString.prefix(9))
        return trimmed
    }
}

extension WLTLocation {
    public var clCoordinate:CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
