//
//  BeaconDataReader.swift
//  Wiliot
//
//  Created by Ivan Yavorin on 19.10.2021.
//  Copyright © 2021 Eastern Peak. All rights reserved.
//

import Foundation

typealias BridgeSoftwareVersionStringsTuple = (major:String, minor:String, patch:String)
typealias BridgeSoftwareVersionUInt8Tuple = (major:UInt8, minor:UInt8, patch:UInt8)


public class BeaconDataReader {
    
    private static var thirdPartySensorFlagData:Data = Data([UInt8(0x00), UInt8(0x00), UInt8(0xEB)])
    private static var sideInfoFlagData:Data =         Data([UInt8(0x00), UInt8(0x00), UInt8(0xEC)])
    private static var gatewayToBridgeFlagData =       Data(Array<UInt8>(arrayLiteral:0x00, 0x00, 0xED))
    private static var bridgeToGatewayFlagData:Data =  Data(Array<UInt8>(arrayLiteral:0x00, 0x00, 0xEE))
    private static var combinedPacketMajorFlagUInt8 =   UInt8(0x3F) // 0b00111111
    private static var thirdPartyServiceUUIDValue:Data = Data([UInt8(0xFC), UInt8(0x90)])
    
    public class func isBeaconDataSideInfoPacket(_ data:Data) -> Bool {
        
        if (isPacketFCC6(data) || isPacketAFFD(data) || isPacketFDAF(data)),
            (isBeaconDataSideInfoEC(data) || isBeaconDataSideInfoThirdPartySensorInfo(data)) {
            return true
        }
        return false
    }
    
    public class func isBeaconDataCombinedPacket(_ data:Data) -> Bool {
        guard data.count > 4 /*( O(1) - RandomAccessCollection )*/, isPacketFCC6(data) else { return false }
        
        let uint8ToMask:UInt8 = data[4]
        
        let isCombPacket = (uint8ToMask & Self.combinedPacketMajorFlagUInt8) == Self.combinedPacketMajorFlagUInt8
        
        return isCombPacket //isCombinedPacket
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
    public class func isBeaconDataSideInfoThirdPartySensorInfo(_ data:Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData:Data = data.subdata(in: groupIdRange)
        if groupIdData == thirdPartySensorFlagData { //[00, 00, EB]
//            printDebug("Side Info as 3rd party payload: \(data.hexEncodedString(options: .upperCase))")
            return true
        }
        return false
//
//        var aData = data.suffix(8).prefix(4)
//
////        printDebug(" hexValue of \(aData.hexEncodedString(options: .upperCase)) from full Data: \(data.hexEncodedString(options: .upperCase))")
//
//        if let lastByte:UInt8 = aData.last {
//            if lastByte != 0 {
//
//                aData.removeLast()
//
//                var isAllZoroes:Bool = true
//                var iterationsCount = aData.count
//
//                //3 bytes should all be zeroes
//                repeat {
//                    iterationsCount -= 1
//                    if let lastUInt = aData.popLast(), lastUInt != 0 {
//                        isAllZoroes = false
//                    }
//                }
//                while isAllZoroes && iterationsCount > 0
//
//                if isAllZoroes {
//                    printDebug("Side Info as 3rd party payload: \(data.hexEncodedString(options: .upperCase))")
//                    return true
//                }
//            }
//        }
//
//        return false
    }
    
    static func isBeaconDataThirdPartyDataPayload(_ data:Data) -> Bool {
        guard data.count == 29 else {
            return false
        }
        
        let first2Bytes:Data = data.prefix(2)
        
        if first2Bytes == thirdPartyServiceUUIDValue {
            return true
        }
        return false
    }
    
    ///uses first bytes 3,4,5 of incoming Data object and compares to Data with Bytes 0x00, 0x00, 0xED
    public class func isBeaconDataGWtoBridgeMessage(_ data:Data) -> Bool {
        let groupIdRange = 2..<5
        let groupIdData = data.subdata(in: groupIdRange)
        
        if (isPacketFCC6(data) || isPacketAFFD(data)), groupIdData == gatewayToBridgeFlagData { //[00,00,ED]
            return true
        }
        return false
    }
    
    ///uses first bytes 3,4,5 of incoming Data object and compares to Data with Bytes 0x00, 0x00, 0xEE
    public class func isBeaconDataBridgeToGWmessage(_ data:Data) -> Bool { //[00,00,EE]
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
    
//    class func bridgeTagIdStringFrom(_ data:Data) -> String {
//        let tagPacketIdentifier = data.subdata(in: 14..<18)
//        let tagPacketIdentifierStr = tagPacketIdentifier.hexEncodedString()
//        return tagPacketIdentifierStr
//    }
    
    class func isPacketFDAF(_ data:Data) -> Bool {
        let serviceRange = 0..<2
        let aData = data.subdata(in: serviceRange)
        let packetTypeString = aData.stringHexEncoded()
        
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
        let uint8Arr:[UInt8] = [0xFC, 0xC6] //0xFCC6
        let dataFCC6:Data = Data(uint8Arr)
        
        
        let aDataPrefix:Data = data.subdata(in: serviceRange)
        
        if aDataPrefix == dataFCC6 {
            return true
        }
        return false
    }
    
    /// - Returns: Uppercased hex string
    public class func bridgeMacAddressFrom(sideInfoData data:Data) -> String {
        let macAddressSubdata = bridgeMacAddressDataFrom(data)
        let macAddressStr = macAddressSubdata.stringHexEncodedUppercased()
        return macAddressStr
    }
    
    fileprivate
    class func bridgeMacAddressDataFrom(_ data:Data) -> Data {
        let macAddressSubdata = data.subdata(in: 5..<11)
        return macAddressSubdata
    }
    
    public class func numberOfPackets(from data:Data) -> Int? {
       let packetsCounterRange = 11..<13
       let packetsBytes = data[packetsCounterRange] //subscript range
       if packetsBytes.count != 2 {
           return nil
       }
       
       let aString = packetsBytes.stringHexEncoded()

       guard let intCount = Int(aString, radix: 16) else {
           return nil
       }

       return intCount
   }
       
    public class func rssiValue(from data: Data) -> Int? {
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
