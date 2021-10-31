//
//  Header.swift
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
    var _maxElementsPerPage: Int
    var _totalUsedBytesCount: Address
    var _storageAddress: Address
    var _freeRoot: Address
}
extension Header {
    init(maxElementsPerPage: Int = 32) {
        _version = _LA_VERSION
        _count = 0
        _maxElementsPerPage = maxElementsPerPage
        _totalUsedBytesCount = 0
        _storageAddress = Address.invalid
        _freeRoot = Address.invalid
    }
}
///
extension Header: CustomStringConvertible {
    public var description: String {
        """
        \(Header.self):
            version: \(_version),
            count: \(_count),
            maxElementsPerPage: \(_maxElementsPerPage),
            totalUsedBytesCount: \(_totalUsedBytesCount),
            storageAddress: \(_storageAddress),
            freeRoot: \(_freeRoot)
        """
    }
}
