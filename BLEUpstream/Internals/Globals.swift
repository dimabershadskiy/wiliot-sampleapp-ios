//
//  Globals.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 12.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
import OSLog

func bleuCreateLogger(subsystem:String, category:String) -> Logger {
    #if DEBUG
    return Logger(subsystem: subsystem, category: category)
    #else
    return Logger(.disabled)
    #endif
}
