

import Foundation
import Combine


protocol BridgePayloadsReceiving {
    func receiveBridgeMassagePayloadPacket(_ bridgeMessagePacket:BLEPacket)
}


protocol NearbyBridgesUpdating {
    func receiveBridgePackets(_ bridgeInfo:[BLEPacket], location:Location?)
}

//input

class NearbyBridgesUpdater:NearbyBridgesUpdating {

    var bridgePayloadsSender:BridgePayloadsReceiving
    
    private var datesByMAC:[Data:Date] = [:]
    private lazy var bridgeMACsByDates = [String:Date]()
    
    private var lastRequestDate:Date = .distantPast
    private var currentLocation:Location?
    
    //MARK: - INIT
    init(bridgePayloadsSender:BridgePayloadsReceiving) {
        #if DEBUG
        print("+ NearbyBridgesUpdater INIT - bridgePayloadsSender: \(bridgePayloadsSender)")
        #endif
        
        self.bridgePayloadsSender = bridgePayloadsSender
    }
    
    #if DEBUG
    deinit {
        print("+ NearbyBridgesUpdater Deinit +")
    }
    #endif
    
    //MARK: -
    private func deleteBridgeByMacID(_ bridgeMac:String) {
        bridgeMACsByDates[bridgeMac] = nil
        if let dataKey = bridgeMac.data(using: .utf8) {
            datesByMAC[dataKey] = nil
        }
    }
    
    //MARK: - NearbyBridgesUpdating
    func receiveBridgePackets(_ bridgeBLEPackets: [BLEPacket], location:Location?) {
        if let loc = location {
            currentLocation = loc
        }
       
        for aBLEPacket in bridgeBLEPackets {
            bridgePayloadsSender.receiveBridgeMassagePayloadPacket(aBLEPacket)
        }
    }
    
}
