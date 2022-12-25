//
//  BLEPacketsManager.swift

import Foundation
import Combine

class BLEPacketsManager {
    private var cancellables: Set<AnyCancellable> = []

    private lazy var accelerationService: MotionAccelerationService = {
        let service = MotionAccelerationService(accelerationUpdateInterval: 1.0)
        return service
    }()

    private lazy var locationService: LocationService = LocationService()

    var pacingReceiver: PacketsPacing?

    init(pacingReceiver: PacketsPacing?) {
        self.pacingReceiver = pacingReceiver
    }

    func subscribeToBLEpacketsPublisher(publisher: AnyPublisher<BLEPacket, Never>) {
        publisher.sink {[weak self] packet in
            self?.handleBLEPacket(packet)
        }.store(in: &cancellables)
    }

    func start() {
        tryToStartAccelerometerUpdates()
        startLocationService()
    }
    // MARK: - Setup
    private func tryToStartAccelerometerUpdates() {
        do {
            try accelerationService.startUpdates()
        } catch let error {
            if let handledError = error as? ValueReadingError {
                switch handledError {
                case .notFound:
                    break
                case .invalidValue(let optionalMessage):
                    print("PixelService accelerometer is already working: \(optionalMessage ?? "-")")
                case .missingRequiredValue(let optionalMessage):
                    print("PixelService accelerometer not availableError: \(optionalMessage ?? "-")")
                }
            } else {
                print("PixelService Unknown error while trying to start accelerometer updates: \(error)")
            }
        }
    }

    private func startLocationService() {
        locationService.startLocationUpdates()
        locationService.startRanging()
    }

    private func stopLocationService() {
        locationService.stopLocationUpdates()
        locationService.stopRanging()
    }

    private func handleBLEPacket(_ packet: BLEPacket) {
        let data: Data = packet.data

        if BeaconDataReader.isBeaconDataGWtoBridgeMessage(data) || BeaconDataReader.isBeaconDataBridgeToGWmessage(data) {
            return
        }

        handlePixelPacket(packet)
    }

    private func handlePixelPacket(_ blePacket: BLEPacket) {
//        print("BLEPacketsManager: \(blePacket.data.hexEncodedString(options: .upperCase)) - from - \(blePacket.uid.uuidString)")

        let accelerationData = self.accelerationService.currentAcceleration
        var location: Location?
        if let clLocaton = locationService.lastLocation {
            location = Location(latitude: clLocaton.coordinate.latitude, longtitude: clLocaton.coordinate.longitude)
        }
        let payloadStr = blePacket.data.hexEncodedString(options: .upperCase)

        let bleUUID = blePacket.uid

        let packet = TagPacketData(payload: payloadStr,
                            timestamp: blePacket.timeStamp,
                            location: location,
                            acceleration: accelerationData,
                            bridgeId: nil,
                            groupId: nil,
                            sequenceId: 0,
                            nfpkt: nil,
                            rssi: blePacket.rssi)

        pacingReceiver?.receivePacketsByUUID([bleUUID: packet])
    }
}
