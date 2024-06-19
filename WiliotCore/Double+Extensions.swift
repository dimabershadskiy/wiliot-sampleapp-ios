//
//  Double+Extensions.swift
//  WiliotCore
//
//  Created by Ivan Yavorin on 07.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

extension Double {
    public func encodeUsingFraction(_ fractionDigits: Int) -> Decimal {
        return Decimal(string: String(format: "%.\(fractionDigits)f", self))!
    }
}
