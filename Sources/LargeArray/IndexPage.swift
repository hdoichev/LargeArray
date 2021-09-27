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
    struct Dirty: Codable {
        var info: Bool = false
        var nodes: Bool = false
        var isDirty: Bool { info || nodes }
    }
    var info: Info {
        get { return _info }
        set {
            if _info != newValue {
                _info = newValue
                _dirty.info = true
            }
        }
    }
    var dirty: Dirty {
        _dirty
    }
    var isFull: Bool {
        return _info._availableNodes >= _info._maxNodes 
    }
    
    private var _info: Info
    private var _nodes: ContiguousArray<Node>
    private var _dirty: Dirty
    ///
    init(address: Address, maxNodes: LargeArray.Index) {
        _info = Info(_address: address, _availableNodes: 0, _maxNodes: maxNodes, _next: 0, _prev: 0)
        _nodes = ContiguousArray<Node>()
        _dirty = Dirty(info: true, nodes: true)
    }
    ///
    mutating func appendNode(_ node: Node) throws {
        guard isFull == false else { throw LAErrors.NodeIsFull }
        _dirty.nodes = true
        _nodes.append(node)
        info._availableNodes += 1
    }
    ///
    mutating func insertNode(_ node: Node, at position: LargeArray.Index) throws {
        guard isFull == false else { throw LAErrors.NodeIsFull }
        _dirty.nodes = true
        _nodes.insert(node, at: position)
        info._availableNodes += 1
    }
    ///
    mutating func removeNode(at position: LargeArray.Index) {
        _dirty.nodes = true
        _nodes.remove(at: position)
        info._availableNodes -= 1
    }
    ///
    mutating func updateNode(at position: LargeArray.Index, node: Node) {
        _dirty.nodes = true
        _nodes[position] = node
    }
    ///
    func node(at position: LargeArray.Index) -> Node {
        return _nodes[position]
    }
    ///
    mutating func moveNodes(_ range: Range<Int>, into page: inout IndexPage) throws {
        for i in range {
            try page.appendNode(node(at: i))
        }
        _nodes.removeSubrange(range)
        _info._availableNodes = _nodes.count
        _dirty.nodes = true
    }
    ///
    func isValidIndex(_ position: LargeArray.Index) -> Bool {
        return (0..<_info._availableNodes).contains(position)
    }
}

@available(macOS 10.15.4, *)
extension IndexPage {
    ///
    mutating func store(using storageAccessor: StorageAccessor) throws {
        guard _dirty.isDirty else { return }
        if _dirty.info {
            _info._availableNodes = _nodes.count // preserve the count of the actual nodes, so we can properly load the nodes data
            var data = Data(count: MemoryLayout<Info>.size)
            data.withUnsafeMutableBytes { buffer in
                let out_buffer = buffer.bindMemory(to: Info.self)
                out_buffer[0] = _info
            }
            try storageAccessor.write(data, at: _info._address)
            _dirty.info = false
        } else {
            try storageAccessor.seek(to: _info._address + Address(MemoryLayout<Info>.size))
        }
        // Store the nodes into the data buffer
        // When storing we always store the _maxNodes size. This prevents the relocation of the IndexPage when elements are added/removed from it.
        // When loading the nodes the _availableNodes is used to read the nodes data, thus only the actual stored elements are loaded.
        //        var nodesData = Data(count: MemoryLayout<Node>.size * Int(_info._maxNodes))
        if _dirty.nodes {
            var nodesData = Data(repeating: 0, count: MemoryLayout<Node>.size * Int(_info._maxNodes))
            nodesData.withUnsafeMutableBytes { dest in
                _nodes.withUnsafeBytes { source in
                    dest.copyBytes(from: source)
                }
            }
            try storageAccessor.write(data: nodesData)
            _dirty.nodes = false
        }
    }
    ///
    mutating func _loadInfo(using storageAccessor: StorageAccessor, from address: Address) throws {
        guard let data = try storageAccessor.read(from: address, upToCount: MemoryLayout<IndexPage.Info>.size) else { throw LAErrors.ErrorReadingData }
        try data.withUnsafeBytes { buffer in
            let in_buffer = buffer.bindMemory(to: IndexPage.Info.self)
            guard in_buffer.count == 1 else { throw LAErrors.InvalidReadBufferSize }
            self._info = in_buffer[0]
        }
        guard self._info._address == address else { throw LAErrors.InvalidAddressInIndexPage }
        _dirty.info = false
    }
    ///
    mutating func _loadNodes(using storageAccessor: StorageAccessor, from address: Address?) throws {
        guard _info._availableNodes > 0 else { _nodes.removeAll(); return }
        if let address = address {
            try storageAccessor.seek(to: address + Address(MemoryLayout<IndexPage.Info>.size))
        }
        let nodesSize = MemoryLayout<Node>.size * _info._availableNodes
        guard let nodesData = try storageAccessor.read(bytesCount: nodesSize) else { throw LAErrors.ErrorReadingData }
        guard nodesSize == nodesData.count else { throw LAErrors.InvalidReadBufferSize }
        _nodes = ContiguousArray<Node>(repeating: Node(), count: Int(_info._availableNodes))
        _nodes.withUnsafeMutableBufferPointer { nodesData.copyBytes(to: $0) }
        _dirty.nodes = false
    }
    ///
    mutating func load(using storageAccessor: StorageAccessor, from address: Address, what: Properties = .All) throws {
        switch what {
        case .All:
            try _loadInfo(using: storageAccessor, from: address)
            try _loadNodes(using: storageAccessor, from: nil) // the Storage should already be positioned at the start of the Nodes section so seek is not needed.
        case .Info:
            try _loadInfo(using: storageAccessor, from: address)
            // after loading the info the nodes can't be marked as dirty
            _dirty.nodes = false
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

@available(macOS 10.15.4, *)
extension IndexPage.Info: Equatable {
//    static func == (lhs: IndexPage.Info, rhs: IndexPage.Info) -> Bool {
//        return
//        (lhs._address == rhs._address &&
//         lhs._availableNodes == rhs._availableNodes &&
//         lhs._maxNodes == rhs._maxNodes &&
//         lhs._next == rhs._next &&
//         lhs._prev == rhs._prev)
//    }
}
