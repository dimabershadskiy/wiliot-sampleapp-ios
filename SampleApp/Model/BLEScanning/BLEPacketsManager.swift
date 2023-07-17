//
//  BLEPacketsManager.swift


import Foundation
import Combine

class BLEPacketsManager {
    private var cancellables:Set<AnyCancellable> = []
    
    let pacingReceiver:PacketsPacing
    let bridgesUpdater:NearbyBridgesUpdating
    let locationSource:LocationSource
    let sideInfoHandler:SideInfoPacketsHandling
    
    init(pacingReceiver:PacketsPacing,
         sideInfoPacketsHandler:SideInfoPacketsHandling,
         bridgesUpdater:NearbyBridgesUpdating,
         locationSource:LocationSource) {
        
        self.pacingReceiver = pacingReceiver
        self.sideInfoHandler = sideInfoPacketsHandler
        self.bridgesUpdater = bridgesUpdater
        self.locationSource = locationSource
    }
    
    func subscribeToBLEpacketsPublisher(publisher:AnyPublisher<BLEPacket,Never>) {
        publisher.sink {[weak self] packet in
            self?.handleBLEPacket(packet)
        }.store(in: &cancellables)
    }
    
    
    //MARK: - 
    
    private func handleBLEPacket(_ packet:BLEPacket) {
        let data:Data = packet.data
        
        if BeaconDataReader.isBeaconDataGWtoBridgeMessage(data) {
            return
        }
        
        if BeaconDataReader.isBeaconDataBridgeToGWmessage(data) {
            handleBridgeCommandPacket(packet)
        }
        else {
            handlePixelPacket(packet)
        }
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
        
        pacingReceiver.receivePacketsByUUID([bleUUID : packet])
    }
    
    private func handleBridgeCommandPacket(_ packet:BLEPacket) {
        //bridge to gateway command packets (e.g. config containing packet)
        
        var location:Location?
        if let aLocation = locationSource.getLocation() {
            location = aLocation
        }
        
        bridgesUpdater.receiveBridgePackets([packet], location: location)
    }
}
