//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/24/21.
//

import Foundation

///
@available(macOS 10.15.4, *)
struct IndexPage: Codable {
    enum Properties {
        case All, Info, Nodes
    }
    struct Info: Codable {
        let _address: Address
        var _availableNodes: LargeArray.Index
        var _maxNodes: LargeArray.Index
        var _next: Address
        var _prev: Address
    }
    var _info: Info
    var _nodes: ContiguousArray<Node>
    init(address: Address, maxNodes: LargeArray.Index) {
        _info = Info(_address: address, _availableNodes: 0, _maxNodes: maxNodes, _next: 0, _prev: 0)
        _nodes = ContiguousArray<Node>()
    }
}
@available(macOS 10.15.4, *)
extension IndexPage {
    /// "at" always points to the location where the entire page can be stored.
    mutating func store(using storageAccessor: StorageAccessor, what: Properties = .All) throws {
        _info._availableNodes = _nodes.count // preserve the count of the actual nodes, so we can properly load the nodes data
        var data = Data(count: MemoryLayout<Info>.size)
        data.withUnsafeMutableBytes { buffer in
            let out_buffer = buffer.bindMemory(to: Info.self)
            out_buffer[0] = _info
        }
        // Store the nodes into the data buffer
        // When storing we always store the _maxNodes size. This prevents the relocation of the IndexPage when elements are added/removed from it.
        // When loading the nodes the _availableNodes is used to read the nodes data, thus only the actual stored elements are loaded.
        //        var nodesData = Data(count: MemoryLayout<Node>.size * Int(_info._maxNodes))
        var nodesData = Data(repeating: 0, count: MemoryLayout<Node>.size * Int(_info._maxNodes))
        nodesData.withUnsafeMutableBytes { dest in
            _nodes.withUnsafeBytes { source in
                dest.copyBytes(from: source)
            }
        }
        try storageAccessor.write(data, at: _info._address)
        try storageAccessor.write(data: nodesData)
    }
    ///
    mutating func _loadInfo(using storageAccessor: StorageAccessor, from address: Address) throws {
        guard let data = try storageAccessor.read(from: address, upToCount: Address(MemoryLayout<IndexPage.Info>.size)) else { throw LAErrors.ErrorReadingData }
        try data.withUnsafeBytes { buffer in
            let in_buffer = buffer.bindMemory(to: IndexPage.Info.self)
            guard in_buffer.count == 1 else { throw LAErrors.InvalidReadBufferSize }
            self._info = in_buffer[0]
        }
        guard self._info._address == address else { throw LAErrors.InvalidAddressInIndexPage }
    }
    ///
    mutating func _loadNodes(using storageAccessor: StorageAccessor, from address: Address?) throws {
        guard _info._availableNodes > 0 else { _nodes.removeAll(); return }
        if let address = address {
            try storageAccessor.seek(to: address + Address(MemoryLayout<IndexPage.Info>.size))
        }
        let nodesSize = MemoryLayout<Node>.size * _info._availableNodes
        guard let nodesData = try storageAccessor.read(bytesCount: Address(nodesSize)) else { throw LAErrors.ErrorReadingData }
        guard nodesSize == nodesData.count else { throw LAErrors.InvalidReadBufferSize }
        _nodes = ContiguousArray<Node>(repeating: Node(), count: Int(_info._availableNodes))
        _nodes.withUnsafeMutableBufferPointer { nodesData.copyBytes(to: $0) }
    }
    ///
    mutating func load(using storageAccessor: StorageAccessor, from address: Address, what: Properties = .All) throws {
        switch what {
        case .All:
            try _loadInfo(using: storageAccessor, from: address)
            try _loadNodes(using: storageAccessor, from: nil) // the Storage should already be positioned at the start of the Nodes section so seek is not needed.
        case .Info:
            try _loadInfo(using: storageAccessor, from: address)
        case .Nodes:
            try _loadNodes(using: storageAccessor, from: address)
        }
    }
}

@available(macOS 10.15.4, *)
extension IndexPage: CustomStringConvertible {
    var description: String {
        return """
        Page(Address: \(_info._address), AvailableNodes: \(_info._availableNodes) (\(_nodes.count)), Prev: \(_info._prev), Next: \(_info._next))
        """
    }
}