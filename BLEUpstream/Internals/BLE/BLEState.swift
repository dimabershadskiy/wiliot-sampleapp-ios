//
//  BLEState.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 13.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation

import CoreBluetooth

public struct BLEUScanState {
    public let managerState:CBManagerState
    public let statusString:String
}

extension BLEUScanState:Equatable {
    public static func == (lhs:BLEUScanState, rhs:BLEUScanState) -> Bool {
        if lhs.statusString != rhs.statusString {
            return false
        }
        
        switch lhs.managerState {
        case .poweredOn:
            if case .poweredOn = rhs.managerState {
                return true
            }
        case .poweredOff:
            if case .poweredOff = rhs.managerState {
                return true
            }
        case .resetting:
            if case .resetting = rhs.managerState {
                return true
            }
        case .unknown:
            if case .unknown = rhs.managerState {
                return true
            }
        case .unsupported:
            if case .unsupported = rhs.managerState {
                return true
            }
        case .unauthorized:
            if case .unauthorized = rhs.managerState {
                return true
            }
        @unknown default:
            return false
        }
        
        return false
    }
}
