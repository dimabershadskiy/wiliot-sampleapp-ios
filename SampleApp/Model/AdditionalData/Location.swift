//
//  Location.swift

import Foundation
import CoreLocation

/// Custom codable structure that represents geographical coordinate.
public struct Location: Codable {
    var lat: Double
    var lng: Double

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

// MARK: - extension for encoding
extension Location {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lat.encodeUsingFraction(5), forKey: .lat)
        try container.encode(lng.encodeUsingFraction(5), forKey: .lng)
    }
}

fileprivate extension Double {
    func encodeUsingFraction(_ fractionDigits: Int) -> Decimal {
        return Decimal(string: String(format: "%.\(fractionDigits)f", self))!
    }
}

extension Location {
    init?(geoLocation clLocation: CLLocation?) {
        guard let loc = clLocation else {
            return nil
        }
        lat = loc.coordinate.latitude
        lng = loc.coordinate.longitude
    }
}
