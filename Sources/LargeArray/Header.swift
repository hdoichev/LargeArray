//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/27/21.
//

import Foundation

///
public let _LA_VERSION: Int = 1
struct Header: Codable {
    let _version: Int
    var _count: Int /// Total number of lelements in the Array
    var _startPageAddress: Address
    var _startFreeAddress: Address
}
extension Header {
    init() {
        _version = _LA_VERSION
        _count = 0
        _startPageAddress = 0
        _startFreeAddress = 0
    }
}
///
extension Header: CustomStringConvertible {
    var description: String {
        "\(Header.self): version: \(_version), count: \(_count), startPageAddress: \(_startPageAddress), startFreeAddress: \(_startFreeAddress)"
    }
}
