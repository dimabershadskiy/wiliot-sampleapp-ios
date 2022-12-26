//
//  BeaconDataReader.swift

import Foundation

typealias BridgeSoftwareVersionStringsTuple = (major: String, minor: String, patch: String)
typealias BridgeSoftwareVersionUInt8Tuple = (major: UInt8, minor: UInt8, patch: UInt8)

class BeaconDataReader {

    class func isBeaconDataSideInfoPacket(_ data: Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)
        let groupIdString = groupIdData.hexEncodedString()

        return isPacketFDAF(data) && groupIdString == "0000ec"
    }

    class func isBeaconDataGWtoBridgeMessage(_ data: Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)
        let groupIdString = groupIdData.hexEncodedString()

        return isPacketFDAF(data) && groupIdString == "0000ed"
    }

    class func isBeaconDataBridgeToGWmessage(_ data: Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)
        let groupIdString = groupIdData.hexEncodedString()

        return isPacketFDAF(data) && ["0000eb", "0000ee"].contains(groupIdString)
    }

    class func tagPacketId(from data: Data) -> Data? {
        #if DEBUG
        let dataCount = data.count
        if dataCount != 29 {
            print("tagPacketId. Data length: \(dataCount)")
        }
        #endif
        let tagPacketIdRange = 25..<29
        let origTagPacketId = data.subdata(in: tagPacketIdRange)
        if origTagPacketId.count < 4 {
            return nil
        }
        return origTagPacketId
    }

    class func isPacketFDAF(_ data: Data) -> Bool {
        let serviceRange = 0..<2
        let aData = data.subdata(in: serviceRange)
        let packetTypeString = aData.hexEncodedString()

        return packetTypeString == "fdaf"
    }

    class func isPacketAFFD(_ data: Data) -> Bool {
        let serviceRange = 0..<2
        let aData = data.subdata(in: serviceRange)
        let packetTypeString = aData.hexEncodedString()

        return packetTypeString == "affd"
    }

    class func bridgeMacAddressFrom(_ data: Data) -> String {
        let macAddressSubdata = bridgeMacAddressDataFrom(data)
        return macAddressSubdata.hexEncodedString(options: .upperCase)
    }

    class func bridgeMacAddressDataFrom(_ data: Data) -> Data {
        return data.subdata(in: 5..<11)
    }

    class func first8BytesOf(data: Data) -> Data? {
        if data.count < 8 {
            return nil
        }

        return data.subdata(in: 0..<8)
    }

    class func bridgeSoftwareVersionFrom(_ data: Data) -> (major: String, minor: String, patch: String) {
        let softWareVersionRange = 0..<3
        let softWareData = data.subdata(in: softWareVersionRange)

        return bridgeSoftwareVersionFromCompact(softWareData: softWareData)
    }

    class func bridgeSoftwareVersionFromCompact(softWareData: Data) -> BridgeSoftwareVersionStringsTuple {
        var result = (major: "", minor: "", patch: "")

        let majorVersionByte = softWareData.subdata(in: 0..<1)
        let majorStr = majorVersionByte.hexEncodedString(options: .upperCase).suffix(1)
        result.major = String(majorStr)

        let minorVersionByte = softWareData.subdata(in: 1..<2)
        let minorStr = minorVersionByte.hexEncodedString(options: .upperCase).suffix(1)
        result.minor = String(minorStr)

        let patchVersionByte = softWareData.subdata(in: 2..<3)
        let patchStr = patchVersionByte.hexEncodedString(options: .upperCase).suffix(1)

        result.patch = String(patchStr)

        return result
    }

    class func numberOfPackets(from data: Data) -> Int? {
        let packetsCounterRange = 11..<13
        let packetsBytes = data[packetsCounterRange] // subscript range
        if packetsBytes.count != 2 {
            return nil
        }

        let aString = packetsBytes.hexEncodedString()
        return Int(aString, radix: 16)
    }

    class func rssiValue(from data: Data) -> Int? {
        let rssiRange = 13..<14
        let rssiByte = data[rssiRange] // subscript range
        if rssiByte.count != 1 {
            return nil
        }

        let uint8value = Data(rssiByte).withUnsafeBytes { pointer in
            pointer.load(as: UInt8.self)
        }

        return Int(uint8value)
    }
}
