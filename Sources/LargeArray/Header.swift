//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/27/21.
//

import Foundation

///
public let _LA_VERSION: Int = 1
public struct Header: Codable {
    let _version: Int
    @usableFromInline
    var _count: Int /// Total number of lelements in the Array
    var _totalUsedBytesCount: Address
    var _storageAddress: Address
    var _freeRoot: Address
}
extension Header {
    init() {
        _version = _LA_VERSION
        _count = 0
        _totalUsedBytesCount = 0
        _storageAddress = Address.invalid
        _freeRoot = Address.invalid
    }
}
///
extension Header: CustomStringConvertible {
    public var description: String {
        "\(Header.self): version: \(_version), count: \(_count), totalUsedBytesCount: \(_totalUsedBytesCount), storageAddress: \(_storageAddress), freeRoot: \(_freeRoot)"
    }
}
