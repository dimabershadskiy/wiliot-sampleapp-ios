//
//  PreferredConnectionType.swift
//  WiliotCore
//
//  Created by Ivan Yavorin on 12.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

public enum PreferredConnectionType:Int {
    case none
    case cellular
    case wirelessOrEthernet
}
 
extension PreferredConnectionType : Comparable, Equatable {
    
    public static func < (lhs: PreferredConnectionType, rhs: PreferredConnectionType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    public static func == (lhs: PreferredConnectionType, rhs: PreferredConnectionType) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
    
    public static func > (lhs: PreferredConnectionType, rhs: PreferredConnectionType) -> Bool {
        lhs.rawValue > rhs.rawValue
    }
  
}

extension PreferredConnectionType : CustomStringConvertible {
    public var description:String {
        switch self {
        case .none:
            return "none"
        case .cellular:
            return "cellular"
        case .wirelessOrEthernet:
            return "wirelessOrEthernet"
        }
    }
}
