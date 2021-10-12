//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/24/21.
//

import Foundation
import Allocator

typealias Nodes = ContiguousArray<Node>
///
@available(macOS 10.15.4, *)
public struct PageInfo: Codable {
    var nodes_address: Address = Address.max
    var availableNodes: LargeArray.Index = 0
    var maxNodes: LargeArray.Index = 0
    var next: Address = Address.max
    var prev: Address = Address.max
}

///
@available(macOS 10.15.4, *)
struct IndexPage {
    enum Properties {
        case All, Info, Nodes
    }
    struct Dirty: Codable {
        var info: Bool = false
        var nodes: Bool = false
        var isDirty: Bool { info || nodes }
    }
    var info: PageInfo {
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
        return _info.availableNodes >= _info.maxNodes 
    }
    var pageAddress: Address {
        return _infoChunks[0].address
    }
    private var _info: PageInfo
    private var _nodes: Nodes
    private var _dirty: Dirty
    private var _infoChunks: Allocator.Chunks
    private var _nodeChunks: Allocator.Chunks
    private var _storage: StorageSystem
    ///
    init() {
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _infoChunks = Allocator.Chunks()
        _nodeChunks = Allocator.Chunks()
        _storage = StorageSystem(fileHandle: FileHandle(), allocator: Allocator(capacity: 0), nodeCache: 0, pageCache: 0)
    }
    ///
    init(maxNodes: LargeArray.Index, using storage: StorageSystem) throws {
        _storage = storage
        guard let ainfo = _storage.allocator.allocate(MemoryLayout<PageInfo>.size, overhead: MemoryLayout<Node>.size) else { throw LAErrors.AllocationFailed }
        guard let anodes = _storage.allocator.allocate(MemoryLayout<Node>.size * maxNodes,
                                                       overhead: MemoryLayout<Node>.size) else {
            _storage.allocator.deallocate(chunks: ainfo)
            throw LAErrors.AllocationFailed }
        _infoChunks = ainfo
        _nodeChunks = anodes
        guard _infoChunks.allocatedCount >= MemoryLayout<PageInfo>.size + MemoryLayout<Node>.size else {
            _storage.allocator.deallocate(chunks: ainfo)
            _storage.allocator.deallocate(chunks: anodes)
            throw LAErrors.InvlaidAllocatedSize }
        _info = PageInfo(nodes_address: _nodeChunks[0].address,
                         availableNodes: 0, maxNodes: maxNodes, next: Address.invalid, prev: Address.invalid)
        _nodes = Nodes()
        _dirty = Dirty(info: true, nodes: true)
    }
    ///
    init(address: Address, using storage: StorageSystem) throws {
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _infoChunks = Allocator.Chunks()
        _nodeChunks = Allocator.Chunks()
        _storage = storage
        
        try _loadInfo(from: address)
        // load nodes ???
        try _loadNodes()
    }
    /// Deallocate the page and remove it from the prev/next chain,
    /// by linking the prev and next to one another
    ///
    mutating func deallocate() throws {
        _storage.allocator.deallocate(chunks: _nodeChunks)
        _storage.allocator.deallocate(chunks: _infoChunks)
        // remove this page from the prev and next pages.
        if _info.prev != Address.max {
            var prevInfo = try PageInfo.load(using: _storage, at: _info.prev)
            prevInfo.0.next = _info.next
            try prevInfo.0.store(using: _storage, with: prevInfo.1)
        }
        if _info.next != Address.max {
            var nextInfo = try PageInfo.load(using: _storage, at: _info.next)
            nextInfo.0.prev = _info.prev
            try nextInfo.0.store(using: _storage, with: nextInfo.1)
        }
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _infoChunks = Allocator.Chunks()
        _nodeChunks = Allocator.Chunks()
    }
    ///
    mutating func appendNode(_ node: Node) throws {
        guard isFull == false else { throw LAErrors.NodeIsFull }
        _dirty.nodes = true
        _nodes.append(node)
        info.availableNodes += 1
    }
    ///
    mutating func insertNode(_ node: Node, at position: LargeArray.Index) throws {
        guard isFull == false else { throw LAErrors.NodeIsFull }
        _dirty.nodes = true
        _nodes.insert(node, at: position)
        info.availableNodes += 1
    }
    ///
    mutating func removeNode(at position: LargeArray.Index) {
        _dirty.nodes = true
        _nodes.remove(at: position)
        info.availableNodes -= 1
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
        _info.availableNodes = _nodes.count
        _dirty.nodes = true
    }
    ///
    func isValidIndex(_ position: LargeArray.Index) -> Bool {
        return (0..<_info.availableNodes).contains(position)
    }
}

@available(macOS 10.15.4, *)
extension IndexPage {
    ///
    mutating func store() throws {
        guard _dirty.isDirty else { return }
        if _dirty.info {
            _info.availableNodes = _nodes.count // preserve the count of the actual nodes, so we can properly load the nodes data
            try _store(from: _info).storeWithNodes(chunks: _infoChunks, using: _storage.fileHandle)
            _dirty.info = false
        }
        // Store the nodes into the data buffer
        // When storing we always store the _maxNodes size. This prevents the relocation of the IndexPage when elements are added/removed from it.
        // When loading the nodes the _availableNodes is used to read the nodes data, thus only the actual stored elements are loaded.
        //        var nodesData = Data(count: MemoryLayout<Node>.size * Int(_info._maxNodes))
        if _dirty.nodes {
            var nodesData = Data(repeating: 0, count: MemoryLayout<Node>.size * Int(_info.maxNodes))
            nodesData.withUnsafeMutableBytes { dest in
                _nodes.withUnsafeBytes { source in
                    dest.copyBytes(from: source)
                }
            }
            try nodesData.storeWithNodes(chunks: _nodeChunks, using: _storage.fileHandle)
            _dirty.nodes = false
        }
    }
    ///
    mutating func _loadInfo(from address: Address) throws {
        let li = try Data.loadFromNodes(start: address, byteCount: MemoryLayout<PageInfo>.size, using: _storage.fileHandle)
        _infoChunks = li.1
        try _load(into: &_info, from: li.0)
        _dirty.info = false
    }
    ///
    mutating func _loadNodes() throws {
        guard _info.availableNodes > 0 else { _nodes.removeAll(); return }
        let li = try Data.loadFromNodes(start: _info.nodes_address,
                                        byteCount: MemoryLayout<Node>.size * _info.availableNodes, using: _storage.fileHandle)
        _nodeChunks = li.1
        _nodes = Nodes(repeating: Node(), count: Int(_info.availableNodes))
        _nodes.withUnsafeMutableBufferPointer { li.0.copyBytes(to: $0) }
        _dirty.nodes = false
    }
    ///
    mutating func load(from address: Address, what: Properties = .All) throws {
        switch what {
        case .All:
            try _loadInfo(from: address)
            try _loadNodes() // the Storage should already be positioned at the start of the Nodes section so seek is not needed.
        case .Info:
            try _loadInfo(from: address)
            // after loading the info the nodes can't be marked as dirty
            _dirty.nodes = false
        case .Nodes:
            try _loadNodes()
        }
    }
}

@available(macOS 10.15.4, *)
extension IndexPage: CustomStringConvertible {
    var description: String {
        return """
        Page(Address: \(pageAddress), AvailableNodes: \(_info.availableNodes) (\(_nodes.count)), Prev: \(_info.prev), Next: \(_info.next))
        """
    }
}

@available(macOS 10.15.4, *)
extension PageInfo: Equatable {
//    static func == (lhs: IndexPage.Info, rhs: IndexPage.Info) -> Bool {
//        return
//        (lhs._address == rhs._address &&
//         lhs._availableNodes == rhs._availableNodes &&
//         lhs._maxNodes == rhs._maxNodes &&
//         lhs._next == rhs._next &&
//         lhs._prev == rhs._prev)
//    }
}

@available(macOS 10.15.4, *)
extension PageInfo{
    func store(using storage: StorageSystem, with chunks: Allocator.Chunks) throws {
        try _store(from: self).storeWithNodes(chunks: chunks, using: storage.fileHandle)
    }
    static func load(using storage: StorageSystem, at address: Address) throws -> (PageInfo, Allocator.Chunks) {
        let li = try Data.loadFromNodes(start: address, byteCount: MemoryLayout<PageInfo>.size, using: storage.fileHandle)
        var info = PageInfo()
        try _load(into: &info, from: li.0)
        return (info, li.1)
    }
}

extension Address {
    static var invalid: Address { return Address.max }
}
