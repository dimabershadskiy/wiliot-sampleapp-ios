//
//  ClaimableAsset.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 29.07.2022.
//

import Foundation

public struct ClaimableAsset:Codable {
    public let id:String
    public var name:String?
    public var category:ClaimableCategory?
    public var tags:[AssetTag]?
    
}

extension ClaimableAsset:Hashable {}

extension ClaimableAsset:Comparable {
    public static func ==(lhs:ClaimableAsset, rhs:ClaimableAsset) -> Bool {
        return lhs.id == rhs.id
    }
    
    public static func <(lhs:ClaimableAsset, rhs:ClaimableAsset) -> Bool {
        return lhs.id < rhs.id
    }
    
    public static func >(lhs:ClaimableAsset, rhs:ClaimableAsset) -> Bool {
        return lhs.id > rhs.id
    }
}

public struct AssetTag: Codable, Hashable {
    public let tagId:String
    public init(tagId: String) {
        self.tagId = tagId
    }
}

extension AssetTag {
    init?(info dictionary:[String:String]) {
        guard let lvTagId = dictionary["tagId"] else {
            return nil
        }
        tagId = lvTagId
    }
}

public struct ClaimableCategory: Codable, Hashable {
    public let id:String
    public var name:String?
    public var sku_upc:String?
    public var descript:String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, sku_upc
        case descript = "description"
    }
}


//extension ClaimableCategory {
//    var assetCategory: AssetCategory {
//        AssetCategory(id: self.id, name: self.name, sku_upc: self.sku_upc, descript: self.descript)
//    }
//}
