//
//  Date+Extensions.swift
//  WiliotCore
//
//  Created by Ivan Yavorin on 07.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
extension Date {
    public func millisecondsFrom1970() -> TimeInterval {
        return (timeIntervalSince1970 * 1000).rounded()
    }
}
