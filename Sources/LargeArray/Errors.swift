//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/27/21.
//

import Foundation

enum LAErrors: Error {
    case InvalidReadBufferSize
    case InvalidWriteBufferSize
    case NilBaseAddress
    case ErrorReadingData
    case InvalidAddressInIndexPage
    case InvalidFileVersion
    case IndexMismatch
    case CorruptedPageAddress
    case CorruptedStartIndex
    case CorruptedItemsCount
    case PositionOutOfRange
    case NodeIsFull
    case AllocationFailed
    case ErrorConstructingSourcePointer
    case InvalidAllocatedSize
    case InvalidNodeAddress
}

extension LAErrors: CustomStringConvertible {
    var description: String {
        switch self {
        case .ErrorReadingData: return "ErrorRadingData"
        case .InvalidWriteBufferSize: return "InvalidWriteBufferSize"
        case .InvalidReadBufferSize: return "InvalidReadBufferSize"
        case .CorruptedPageAddress: return "CorruptedPageAddress"
        case .CorruptedStartIndex: return "CorruptedStartIndex"
        case .CorruptedItemsCount: return "CorruptedItemsCount"
        case .PositionOutOfRange: return "PositionOutOfRange"
        case .IndexMismatch: return "IndexMismatch"
        case .InvalidAddressInIndexPage: return "InvalidAddressInIndexPage"
        case .InvalidFileVersion: return "InvalidFileVersion"
        case .NilBaseAddress: return "NilBaseAddress"
        case .NodeIsFull: return "NodeIsFull"
        case .AllocationFailed: return "AllocationFailed"
        case .ErrorConstructingSourcePointer: return "ErrorConstructingSourcePointer"
        case .InvalidAllocatedSize: return "InvalidAllocatedSize"
        case .InvalidNodeAddress: return "InvalidNodeAddress"
        }
    }
}
