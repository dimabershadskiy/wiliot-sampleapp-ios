//
//  WeakObject.swift

import Foundation
final class WeakObject<T: AnyObject> {
    weak var object: T?

    init(_ object: T) {
        self.object = object
    }
}
