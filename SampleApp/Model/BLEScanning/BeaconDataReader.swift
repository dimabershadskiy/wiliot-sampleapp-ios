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

        if isPacketFDAF(data), groupIdString == "0000ec" {
//            print("groupIdString: \(groupIdString)")
            return true
        }
        return false
    }

    class func isBeaconDataGWtoBridgeMessage(_ data: Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)
        let groupIdString = groupIdData.hexEncodedString()

        if isPacketFDAF(data), groupIdString == "0000ed" {
//            print("Group ID: \(groupIdString)")
            return true
        }
        return false
    }

    class func isBeaconDataBridgeToGWmessage(_ data: Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)
        let groupIdString = groupIdData.hexEncodedString()

        if isPacketFDAF(data), groupIdString == "0000eb" ||  groupIdString == "0000ee" {
//            print("Group ID: \(groupIdString) isBeaconDataBridgeToGWmessage- TRUE")
            return true
        }
        return false
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

//    class func bridgeTagIdStringFrom(_ data:Data) -> String {
//        let tagPacketIdentifier = data.subdata(in: 14..<18)
//        let tagPacketIdentifierStr = tagPacketIdentifier.hexEncodedString()
//        return tagPacketIdentifierStr
//    }

    class func isPacketFDAF(_ data: Data) -> Bool {
        let serviceRange = 0..<2
        let aData = data.subdata(in: serviceRange)
        let packetTypeString = aData.hexEncodedString()

        if packetTypeString == "fdaf" {
            return true
        }
        return false
    }

    class func isPacketAFFD(_ data: Data) -> Bool {
        let serviceRange = 0..<2
        let aData = data.subdata(in: serviceRange)
        let packetTypeString = aData.hexEncodedString()

        if packetTypeString == "affd" {
            return true
        }
        return false
    }

    class func bridgeMacAddressFrom(_ data: Data) -> String {
        let macAddressSubdata = bridgeMacAddressDataFrom(data)
        let macAddressStr = macAddressSubdata.hexEncodedString(options: .upperCase)
        return macAddressStr
    }

    class func bridgeMacAddressDataFrom(_ data: Data) -> Data {
        let macAddressSubdata = data.subdata(in: 5..<11)
        return macAddressSubdata
    }

    class func first8BytesOf(data: Data) -> Data? {

        if data.count < 8 {
            return nil
        }

        let range = 0..<8
        return data.subdata(in: range)
    }

//    class func isBeaconDataBridgeWithSWVersion(_ data:Data) -> Bool {
//        if isPacketFDAF(data) {
//            let groupIdRange = 2..<5
//            let groupIdData = data.subdata(in: groupIdRange)
//            let groupIdString = groupIdData.hexEncodedString()
//            if groupIdString == "0000eb" {
//                return true
//            }
//            print(" - groupIdString: \(groupIdString)")
//        }
//        return false
//    }

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

        guard let intCount = Int(aString, radix: 16) else {
            return nil
        }

        return intCount
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

// extension BeaconDataReader {
//    class func softwareVersionStringFromSoftwareVersionTuple(_ tuple:BridgeSoftwareVersionStringsTuple, separator:String = ".") -> String {
//        let majorVersion = removeLeadingZeroFromString(tuple.major)
//        let minorVersion = removeLeadingZeroFromString(tuple.minor)
//        let patchVersion = removeLeadingZeroFromString(tuple.patch)
//
//        let versionStrings:[String] = [majorVersion, minorVersion, patchVersion]
//
//        return versionStrings.joined(separator: separator)
//    }
//
//    class func removeLeadingZeroFromString(_ string:String) -> String {
//        var toReturn = string
//        if string.hasPrefix("0") {
//            let suffix = string.suffix(1)
//            toReturn = String(suffix)
//        }
//        return toReturn
//    }
// }
