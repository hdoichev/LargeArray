//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/27/21.
//

import Foundation

@available(macOS 10.15.4, *)
public class FreeArray: LargeArray /*: MutableCollection, RandomAccessCollection */{
    var _free: LargeArray?
    ///
    override init(start root: Address, maxPerPage: LargeArray.Index, fileHandle: FileHandle) throws {
        try super.init(start: root, maxPerPage: maxPerPage, fileHandle: fileHandle)
        _free = try LargeArray(start: _header._freeRoot != Address.invalid ? _header._freeRoot: _fileHandle.seekToEndOfFile(),
                               maxPerPage: maxPerPage, fileHandle: _fileHandle)
        _header._freeRoot = _free!._rootAddress
    }
    deinit {
    }
    /// Do nothing for the FreeArray, which already contains the Freed nodes.
    override func addNodeToFreePool(_ node: Node) throws {
        try autoreleasepool {
            try _free!.appendNode(node)
        }
    }
    ///
    public var totalFreeBytesCount: Address {
        return _free!.totalUsedBytesCount
    }
    ///
    func purgeFreeSpace() throws {
        var sar = [Node]()
        for i in 0..<_free!.count {
            try insertOrdered(_free!.getNodeFor(position: i), ar: &sar, maxCount: 10, minAddress: 0)
        }
        while sar.count > 0 {
            print("SAR", sar.map({ $0.address }))
            let minAddress = sar.last!.address
            sar.removeAll()
            for i in 0..<_free!.count {
                try insertOrdered(_free!.getNodeFor(position: i), ar: &sar, maxCount: 10, minAddress: minAddress)
            }
        }
    }
    // find the top 10 elements
    func insertOrdered(_ val: Node, ar: inout [Node], maxCount: Int, minAddress: Address) {
        guard val.address > minAddress else { return }
        for i in 0..<ar.count {
            if ar[i].address > val.address {
                ar.insert(val, at: i)
                if ar.count > maxCount {
                    ar.removeLast()
                }
                return
            }
        }
        if ar.count < maxCount {
            ar.append(val)
        }
    }

}
