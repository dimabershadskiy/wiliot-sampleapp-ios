//
//  ResolvedData.swift
//  Wiliot
//
//  Created by Dima Bershadskiy on 07.05.2021.
//  Copyright © 2021 Wiliot. All rights reserved.
//

import Foundation

public struct ResolvedDataModel: Codable {
    public private(set) var data: [ResolvedPacket]?
    public private(set) var message: String
}

public struct ResolvedPacket: Codable {
    enum CodingKeys:String, CodingKey {
        case claimableAsset = "asset"
        case timestamp, externalId, ownerId, labelId, labels, assetId
    }
    
    public private(set) var timestamp: Int
    public private(set) var externalId: String
    public private(set) var ownerId: String?
    public private(set) var labelId: String?
    public private(set) var labels: [String]?
    public private(set) var assetId: String?
    public private(set) var claimableAsset: ClaimableAsset?
}

extension ResolvedPacket {
//    var shortExternalId:String {
//        //externalId.components(separatedBy: kTagIdDelimiter).last!
//        TagIdReader.wiliotPixelTagExternalIdFrom(externalId) ?? ""
//    }
    
    public var isClaimable:Bool {
        claimableAsset != nil
    }
}

extension ResolvedPacket:Hashable {
    
}


/*{"data":[{"timestamp":1636538572949,"externalId":"(01)00850027865010(21)001rT1053","ownerId":"devkit","labels":["Vanya-test"]}],"message":"Successfully resolved packets"}*/
