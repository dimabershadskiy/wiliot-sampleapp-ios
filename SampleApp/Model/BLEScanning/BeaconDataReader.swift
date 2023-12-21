//
//  BeaconDataReader.swift


import Foundation

typealias BridgeSoftwareVersionStringsTuple = (major:String, minor:String, patch:String)
typealias BridgeSoftwareVersionUInt8Tuple = (major:UInt8, minor:UInt8, patch:UInt8)


class BeaconDataReader {
    
    private static var thirdPartySensorFlagData:Data = Data([UInt8(0x00), UInt8(0x00), UInt8(0xEB)])
    private static var sideInfoFlagData:Data =         Data([UInt8(0x00), UInt8(0x00), UInt8(0xEC)])
    private static var gatewayToBridgeFlagData =       Data(Array<UInt8>(arrayLiteral:0x00, 0x00, 0xED))
    private static var bridgeToGatewayFlagData:Data =  Data(Array<UInt8>(arrayLiteral:0x00, 0x00, 0xEE))
    
    class func isBeaconDataSideInfoPacket(_ data:Data) -> Bool {
        
        if (isPacketFCC6(data) || isPacketAFFD(data)),
            (isBeaconDataSideInfoEC(data) || isBeaconDataSideInfoThirdPartySensorInfo(data)) {
            return true
        }
        return false
    }
    
    ///uses first bytes 3,4,5 of incoming Data object and compares to Data with Bytes 0x00, 0x00, 0xEC
    private class func isBeaconDataSideInfoEC(_ data:Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)
        if groupIdData == sideInfoFlagData { //[00, 00, EC]
            return true
        }
        return false
    }
    
    ///uses first bytes 3,4,5 of incoming Data object and compares to Data with Bytes 0x00, 0x00, 0xEB
    class func isBeaconDataSideInfoThirdPartySensorInfo(_ data:Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData:Data = data.subdata(in: groupIdRange)
        if groupIdData == thirdPartySensorFlagData { //[00, 00, EB]
            #if DEBUG
            print("Side Info as 3rd party payload: \(data.hexEncodedString(options: .upperCase))")
            #endif
            return true
        }
        return false
    }
    
    ///uses first bytes 3,4,5 of incoming Data object and compares to Data with Bytes 0x00, 0x00, 0xED
    class func isBeaconDataGWtoBridgeMessage(_ data:Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)
        
        if (isPacketFCC6(data) || isPacketAFFD(data)), groupIdData == gatewayToBridgeFlagData { //[00,00,ED]
            return true
        }
        return false
    }
    
    ///uses first bytes 3,4,5 of incoming Data object and compares to Data with Bytes 0x00, 0x00, 0xEE
    class func isBeaconDataBridgeToGWmessage(_ data:Data) -> Bool { //[00,00,EE]
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)

        if  (isPacketFCC6(data) || isPacketAFFD(data)), groupIdData == bridgeToGatewayFlagData {
            return true
        }
        return false
    }
    
    //uses bytes 26,27,28,29 of the incoming Data object and returns them as a separate data. If count of bytes is less than 4 - returns nil
    class func tagPacketId(from data:Data) -> Data? {
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
    
    class func isPacketFDAF(_ data:Data) -> Bool {
        let serviceRange = 0..<2
        let aData = data.subdata(in: serviceRange)
        let packetTypeString = aData.hexEncodedString()
        
        if packetTypeString == "fdaf" {
            return true
        }
        return false
    }
    
    class func isPacketAFFD(_ data:Data) -> Bool {
        let serviceRange = 0..<2
        let aDataToCompare:Data = data.subdata(in: serviceRange)
        
        let uint8Arr:[UInt8] = [UInt8(0xAF), UInt8(0xFD)] //0xAFFD
        let dataAFFD:Data = Data.init(uint8Arr)
        if dataAFFD == aDataToCompare {
            return true
        }
        return false
    }
    
    class func isPacketFCC6(_ data:Data) -> Bool {
        let serviceRange = 0..<2
        let uint8Arr:[UInt8] = [0xFC, 0xC6] //0XFCC6
        let dataFCC6:Data = Data(uint8Arr)
        
        
        let aDataPrefix:Data = data.subdata(in: serviceRange)
        
        if aDataPrefix == dataFCC6 {
            return true
        }
        return false
    }
    /// - Returns: Uppercased hex string
    class func bridgeMacAddressFrom(sideInfoData data:Data) -> String {
        let macAddressSubdata = bridgeMacAddressDataFrom(data)
        let macAddressStr = macAddressSubdata.hexEncodedString(options:.upperCase)
        return macAddressStr
    }
    
    fileprivate
    class func bridgeMacAddressDataFrom(_ data:Data) -> Data {
        let macAddressSubdata = data.subdata(in: 5..<11)
        return macAddressSubdata
    }
    
    class func bridgeSoftwareVersionFrom(_ data:Data) -> (major:String, minor:String, patch:String) {
        
        let softWareVersionRange = 0..<3
        let softWareData = data.subdata(in: softWareVersionRange)
        
        return bridgeSoftwareVersionFromCompact(softWareData: softWareData)
    }
    
    class func bridgeSoftwareVersionFromCompact(softWareData data:Data) -> BridgeSoftwareVersionStringsTuple {
        
        var result = (major:"", minor:"", patch:"")
        
        let majorVersionByte = data.subdata(in: 0..<1)
        let majorStr = majorVersionByte.hexEncodedString(options: .upperCase).suffix(1)
        result.major = String(majorStr)
        
        let minorVersionByte = data.subdata(in: 1..<2)
        let minorStr = minorVersionByte.hexEncodedString(options: .upperCase).suffix(1)
        result.minor = String(minorStr)
        
        let patchVersionByte = data.subdata(in: 2..<3)
        let patchStr = patchVersionByte.hexEncodedString(options: .upperCase).suffix(1)

        result.patch = String(patchStr)
        
        return result
    }
    
    class func numberOfPackets(from data:Data) -> Int? {
        let packetsCounterRange = 11..<13
        let packetsBytes = data[packetsCounterRange] //subscript range
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
        let rssiByte = data[rssiRange] //subscript range
        if rssiByte.count != 1 {
            return nil
        }
        
        let uint8value = Data(rssiByte).withUnsafeBytes { pointer in
            pointer.load(as: UInt8.self)
        }
        
        return Int(uint8value)
    }
}
