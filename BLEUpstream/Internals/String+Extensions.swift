//
//  String+Extensions.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 12.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

extension String {
    public var wiliotAdvertizedConnectableBridgeId:String? {
        
        var scannedID:String? = nil
        
        let lowercasedResult = self.lowercased()
        
        if lowercasedResult.contains("wiliot_") {
            scannedID = lowercasedResult.components(separatedBy: "wiliot_").last?.uppercased() ?? self
        }
        else if lowercasedResult.contains("wlt_") {
            scannedID = lowercasedResult.components(separatedBy: "wlt_").last?.uppercased() ?? self
        }
        
        return scannedID
    }
}
