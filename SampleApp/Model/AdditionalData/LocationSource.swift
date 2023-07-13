//
//  LocationSource.swift
//  SampleApp
//
//  Created by Ivan Yavorin on 13.07.2023.
//

import Foundation

protocol LocationSource {
    func getLocation() -> Location?
}
