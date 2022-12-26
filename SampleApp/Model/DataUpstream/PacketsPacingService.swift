//
//  PacketsPacingService.swift

import Foundation

// ouptut
protocol TagPacketsSender {
    func sendPacketsInfo(_ info: [TagPacketData]?)
}
extension WeakObject: TagPacketsSender where T: TagPacketsSender {
    func sendPacketsInfo(_ info: [TagPacketData]?) {
        object?.sendPacketsInfo(info)
    }
}

// input
protocol PacketsPacing {
    func receivePacketsByUUID(_ pacingPackets: [UUID: TagPacketData])
}

class PacketsPacingService {

    private var pacingTimer: DispatchSourceTimer?
    private(set) var packetsSender: TagPacketsSender

    /// default value is 10 seconds
    private(set) var pacingTimeoutSeconds: TimeInterval = 10
    private lazy var packetsStore: [UUID: TagPacketData] = [:]
    private lazy var uuidsByExternalTagId: [String: [UUID]] = [:]
    var firstFireDate: Date?

    init(with tagPacketsSender: TagPacketsSender) {
        packetsSender = tagPacketsSender
        print("+ PacketsPacingService INIT -")
        startPacingWithTimeout()
    }

    deinit {
        print("+ PacketsPacingService Deinit +")
        stopPacingTimer()
        cleanCache()
    }

    /// timeout has limit 0-255 seconds. 0 timeout has no effect, the pacing will not start. Default Value is 10 seconds
    func startPacingWithTimeout(_ timeout: UInt8 = 10) {
        if timeout < 1 {
            return
        }

        stopPacingTimer()

        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + .seconds(Int(timeout)),
                       repeating: .seconds( Int(timeout)),
                       leeway: .milliseconds(100))

        timer.setEventHandler(handler: { [weak self] in self?.pacingTimerFire() })
        self.pacingTimer = timer
        timer.resume()
    }

    func stopPacingTimer() {
        pacingTimer?.cancel()
        pacingTimer = nil
    }

    func cleanCache() {
        packetsStore.removeAll()
    }

    private func pacingTimerFire() {
        clearOldPacketsIfFound()
        let packets = preparePacketsToSend()

        sendPackets(packets)

        if firstFireDate == nil {
            firstFireDate = Date()
        }
    }

    private func preparePacketsToSend() -> [TagPacketData] {
        guard let startDate = Calendar.current.date(byAdding: .second, value: -Int(pacingTimeoutSeconds), to: Date())
            else {
            return []
        }

        let targetTime = startDate.milisecondsFrom1970()

        let storeSnapshot = packetsStore
        let filteredElements: [UUID: TagPacketData] = storeSnapshot.filter { (_, packet) in
            return packet.timestamp > targetTime
        }

        var toReturn = [TagPacketData]()

        var pairsByExtId: [String: [TagPacketData]] = [:]

        let mappingSnapshot = uuidsByExternalTagId
        for (uuid, tagPacketData) in filteredElements {
            if let mappingPair = mappingSnapshot.first(where: { (_, uuids) in
                uuids.contains(uuid)
            }) {
                let extTagIdKey = mappingPair.key
                let existingArray = pairsByExtId[extTagIdKey, default: []]
                pairsByExtId[extTagIdKey] = existingArray + [tagPacketData]
            } else {
                // no External Tag Id for current TagPackedData
                toReturn.append(tagPacketData)
            }
        }

        if !pairsByExtId.isEmpty {
            if let unknowns = pairsByExtId["unknown"] {
                toReturn.append(contentsOf: unknowns)
            }

            pairsByExtId["unknown"] = nil

            for tagPacketDatas in pairsByExtId.values {
                let sortedByTimestamp = tagPacketDatas.sorted(by: {$0.timestamp < $1.timestamp})
                let latestTagPacketData = sortedByTimestamp.last

                if let lastTagPacket = latestTagPacketData {
                    toReturn.append(lastTagPacket)
                }
            }
        }

        return toReturn
    }

    private func sendPackets(_ packets: [TagPacketData]) {
//        printDebug("PacketsPacingService sending packets Count:\(packets.count). Date:\(Date())")
        packetsSender.sendPacketsInfo(packets)
    }

    private func clearOldPacketsIfFound() {
        guard let hourAgoDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) else {
            return
        }

        let storeSnapshot = packetsStore
        let hourAgoIntervalMSEC = hourAgoDate.milisecondsFrom1970()
        let filtered = storeSnapshot.filter { (_, tagPacket) in
            tagPacket.timestamp <= hourAgoIntervalMSEC
        }

        filtered.keys.forEach {
            self.packetsStore[$0] = nil
        }
    }
}

// MARK: - PacketsPacing
extension PacketsPacingService: PacketsPacing {

    func receivePacketsByUUID(_ pacingPackets: [UUID: TagPacketData]) {
        for (uuid, tagPacketData) in pacingPackets {
            packetsStore[uuid] = tagPacketData
        }
    }

}
