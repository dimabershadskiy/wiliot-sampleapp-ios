//
//  NonEmptyContainers.swift
//  WiliotCore
//
//  Created by Ivan Yavorin on 09.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
public struct NonEmptySetContainer<T> where T:Hashable {
    private var wrappedValue:Set<T>
    
    public var set:Set<T> {
        return self.wrappedValue
    }
    
    public var count:Int {
        return self.wrappedValue.count
    }
    
    public init?(withSet aSet:Set<T>) {
        if aSet.isEmpty {
            return nil
        }
        self.wrappedValue = aSet
    }
}

public struct NonEmptyCollectionContainer <T> where T:Collection {
    public var array:T {
        wrappedValue
    }
    
    public var collection:T {
        wrappedValue
    }
    
    public var count:Int {
        wrappedValue.count
    }
    
    private var wrappedValue:T
    
    public init?(withArray array:T) {
        guard !array.isEmpty else {
            return nil
        }
        self.wrappedValue = array
    }
    
    public init?(withCollection collection:T) {
        guard !collection.isEmpty else { return nil }
        self.wrappedValue = collection
    }
    
    public init?( _ string:String) where T == String {
        guard !string.isEmpty else {
            return nil
        }
        self.wrappedValue = string
    }
}

public protocol StringWrapper {
    var string:String{get}
}

extension NonEmptyCollectionContainer:StringWrapper where T == String {
    public var string:String {
        return wrappedValue
    }
}
