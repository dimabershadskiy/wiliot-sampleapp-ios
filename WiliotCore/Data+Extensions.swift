//
//  Data+Extensions.swift
//  WiliotCore
//
//  Created by Ivan Yavorin on 07.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
extension Data {
    /// - Returns: lowercased hex string
    public func stringHexEncoded() -> String {
        self.map{ String(format: "%02hhx", $0)}.joined()
    }
    
    public func stringHexEncodedUppercased() -> String {
        self.map{ String(format: "%02hhX", $0)}.joined()
    }
}
