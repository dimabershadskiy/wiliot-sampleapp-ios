//
//  BLEPacketsManager.swift


import Foundation
import Combine

class BLEPacketsManager {
    private var cancellables:Set<AnyCancellable> = []
    
    var pacingReceiver:PacketsPacing?
    
    init(pacingReceiver:PacketsPacing?) {
        self.pacingReceiver = pacingReceiver
    }
    
    func subscribeToBLEpacketsPublisher(publisher:AnyPublisher<BLEPacket,Never>) {
        publisher.sink {[weak self] packet in
            self?.handleBLEPacket(packet)
        }.store(in: &cancellables)
    }
    
    
    //MARK: - 
    
    private func handleBLEPacket(_ packet:BLEPacket) {
        let data:Data = packet.data
        
        if BeaconDataReader.isBeaconDataGWtoBridgeMessage(data) || BeaconDataReader.isBeaconDataBridgeToGWmessage(data) {
            return
        }
        
        handlePixelPacket(packet)
    }
    
    private func handlePixelPacket(_ blePacket:BLEPacket) {

        let payloadStr = blePacket.data.hexEncodedString(options: .upperCase)
        
        let bleUUID = blePacket.uid
        
        let packet = TagPacketData(payload: payloadStr,
                            timestamp: blePacket.timeStamp,
                            bridgeId: nil,
                            groupId: nil,
                            sequenceId: 0,
                            nfpkt: nil,
                            rssi: blePacket.rssi)
        
        pacingReceiver?.receivePacketsByUUID([bleUUID : packet])
    }
}
