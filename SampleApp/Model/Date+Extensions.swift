//
//  Date+Extensions.swift

import Foundation

extension Date {
    func milisecondsFrom1970() -> Double {
        return (timeIntervalSince1970 * 1000).rounded()
    }
    
    func timeIntervalFrom(_ anotherDate:Date) -> TimeInterval {
        var distance:TimeInterval = 0
        if #available(iOS 13.0, *) {
            distance = anotherDate.distance(to: self)
        } else {
            distance = timeIntervalSince(anotherDate)
        }
        return distance
    }

}
