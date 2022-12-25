//
//  AccelerationData.swift

import Foundation

/// A structure containing 3-axis acceleration data.
public struct AccelerationData: Codable {
    let x: Double
    let y: Double
    let z: Double

    /// Initializer of AccelerationData structure.
    ///
    /// - Parameters:
    ///   - x: X-axis acceleration in G's.
    ///   - y: Y-axis acceleration in G's.
    ///   - z: Z-axis acceleration in G's.
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}
