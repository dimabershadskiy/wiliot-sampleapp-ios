//
//  Date+Extensions.swift

import Foundation

public extension Date {
    func milisecondsFrom1970() -> Double {
        return (timeIntervalSince1970 * 1000).rounded()
    }
}
