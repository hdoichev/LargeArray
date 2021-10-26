//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/24/21.
//

import Foundation
import Allocator
import HArray

typealias Nodes = ContiguousArray<Node>
///
@available(macOS 10.15.4, *)
public struct PageInfo: Codable {
    var nodes_address: Address = Address.max
    var availableNodes: LargeArray.Index = 0
    var maxNodes: LargeArray.Index = 0
}
@available(macOS 10.15.4, *)
extension PageInfo {
    public var isFull: Bool { availableNodes >= maxNodes }
    public var freeSpaceCount: Int { return maxNodes - availableNodes }
}
///
@available(macOS 10.15.4, *)
class NodesPage: Codable {
    enum Properties {
        case All, Info, Nodes
    }
    enum NodeMoveLocation {
        case ToFront(Range<Int>)
        case ToBack(Range<Int>)
    }
    struct Dirty: Codable {
        var info: Bool = false
        var nodes: Bool = false
        var isDirty: Bool { info || nodes }
        init(_ dirty: Bool = false) { info = dirty; nodes = dirty}
        init(info: Bool, nodes: Bool) { self.info = info; self.nodes = nodes}
    }
    //
    private var _info: PageInfo
    private var _nodes: Nodes
    private var _dirty: Dirty
    private var _infoAddress: Int
    private var _storage: StorageSystem?
    //
    var info: PageInfo {
        get { return _info }
        set {
            if _info != newValue {
                _info = newValue
                _dirty.info = true
            }
        }
    }
    var dirty: Dirty { _dirty }
    var isFull: Bool { _info.isFull }
    var pageAddress: Address { _infoAddress }
    ///
    enum CodingKeys: String, CodingKey {
        case a
    }
    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        _infoAddress = try values.decode(Int.self, forKey: .a)
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _storage = nil
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_infoAddress, forKey: .a)
    }
    ///
    init() {
        _infoAddress = Int.max
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _storage = StorageSystem(fileHandle: FileHandle(), allocator: Allocator(capacity: 0), nodeCache: 0, pageCache: 0, maxNodesPerPage: 128)
    }
    ///
    init(maxNodes: LargeArray.Index, using storage: StorageSystem) throws {
        _infoAddress = Int.max
        _storage = storage
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty(info: true, nodes: true)
        _info.maxNodes = maxNodes
        
        try store()
    }
    ///
    init(address: Address, using storage: StorageSystem) throws {
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _infoAddress = address
        _storage = storage
        
        try _loadInfo(from: address)
        // load nodes ???
        try _loadNodes()
    }
    /// Deallocate the page and remove it from the prev/next chain,
    /// by linking the prev and next to one another
    ///
    func deallocate() throws {
        try Node.deallocate(start: _infoAddress, using: _storage!)
        try Node.deallocate(start: _info.nodes_address, using: _storage!)
        // remove this page from the prev and next pages.
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _infoAddress = Int.max
    }
    ///
    func appendNode(_ node: Node) throws {
        guard isFull == false else { throw LAErrors.NodeIsFull }
        _dirty.nodes = true
        _nodes.append(node)
        info.availableNodes += 1
    }
    ///
    func insertNode(_ node: Node, at position: LargeArray.Index) throws {
        guard isFull == false else { throw LAErrors.NodeIsFull }
        _dirty.nodes = true
        _nodes.insert(node, at: position)
        info.availableNodes += 1
    }
    ///
    func removeNode(at position: LargeArray.Index) {
        _dirty.nodes = true
        _nodes.remove(at: position)
        info.availableNodes -= 1
    }
    ///
    func updateNode(at position: LargeArray.Index, with node: Node) {
        _dirty.nodes = true
        _nodes[position] = node
    }
    ///
    func node(at position: LargeArray.Index) -> Node {
        return _nodes[position]
    }
}

@available(macOS 10.15.4, *)
extension NodesPage: Storable {
    typealias StorageAllocator = StorageSystem
    typealias Index = Int
    typealias Element = Node
    var startIndex: Int { 0 }
    var endIndex: Int { _info.availableNodes }
    var capacity: Int {
        self._info.maxNodes
    }
    func index(after i: Int) -> Int { i + 1 }
    
    subscript(position: Int) -> Node {
        get {
            Node()
        }
        set(newValue) {
            
        }
    }
    
    
    var allocator: StorageAllocator? {
        get {
            _storage
        }
        set(newValue) {
            _storage = newValue!
        }
    }
    
    func replace(with elements: [Element]) {
        
    }
    
    func append(_ elements: [Element]) {
        
    }
    
    func append(_ element: Element) {
        
    }
    
    func insert(_ element: Element, at position: Int) {
        
    }
    
    func remove(at: Int) -> Element {
        return Node()
    }
}

///     Store and load functionality
@available(macOS 10.15.4, *)
extension NodesPage {
    ///
    func store() throws {
        guard let storage = _storage else { return }
        guard _dirty.isDirty else { return }
        if _infoAddress == Int.max {
            // Allocate the space for the info and the nodes.
            guard let ainfo = storage.allocator.allocate(MemoryLayout<PageInfo>.size, overhead: MemoryLayout<Node>.size) else { throw LAErrors.AllocationFailed }
            guard let anodes = storage.allocator.allocate(MemoryLayout<Node>.size * _info.maxNodes,
                                                           overhead: MemoryLayout<Node>.size) else {
                storage.allocator.deallocate(chunks: ainfo)
                throw LAErrors.AllocationFailed }
            _infoAddress = ainfo[0].address
            _info.nodes_address = anodes[0].address

            _info.availableNodes = _nodes.count // preserve the count of the actual nodes, so we can properly load the nodes data
            try _store(from: _info).store(with: ainfo, using: storage.fileHandle)
            _dirty.info = false

            var nodesData = Data(repeating: 0, count: MemoryLayout<Node>.size * Int(_info.maxNodes))
            nodesData.withUnsafeMutableBytes { dest in _nodes.withUnsafeBytes { source in dest.copyBytes(from: source) }}
            try nodesData.store(with: anodes, using: storage.fileHandle)
            _dirty.nodes = false
        } else {
            if _dirty.info {
                _info.availableNodes = _nodes.count // preserve the count of the actual nodes, so we can properly load the nodes data
                try _store(from: _info).update(startNodeAddress: _infoAddress, using: storage.fileHandle)
                _dirty.info = false
            }
            // Store the nodes into the data buffer
            // When storing we always store the _maxNodes size. This prevents the relocation of the NodesPage when elements are added/removed from it.
            // When loading the nodes the _availableNodes is used to read the nodes data, thus only the actual stored elements are loaded.
            //        var nodesData = Data(count: MemoryLayout<Node>.size * Int(_info._maxNodes))
            if _dirty.nodes {
                var nodesData = Data(repeating: 0, count: MemoryLayout<Node>.size * Int(_info.maxNodes))
                nodesData.withUnsafeMutableBytes { dest in _nodes.withUnsafeBytes { source in dest.copyBytes(from: source) }}
                try nodesData.update(startNodeAddress: _info.nodes_address, using: storage.fileHandle)
                _dirty.nodes = false
            }
        }
    }
    ///
    func _loadInfo(from address: Address) throws {
        guard let storage = _storage else { throw LAErrors.InvalidObject }
        let di = try Data.load(start: address, upTo: MemoryLayout<PageInfo>.size, using: storage.fileHandle)
        try _load(into: &_info, from: di)
        _infoAddress = address
        _dirty.info = false
    }
    ///
    func _loadNodes() throws {
        guard let storage = _storage else { throw LAErrors.InvalidObject }
        guard _info.nodes_address != Int.max else { throw LAErrors.InvalidNodeAddress }
        guard _info.availableNodes > 0 else { _nodes.removeAll(); return }
        let nd = try Data.load(start: _info.nodes_address,
                                        upTo: MemoryLayout<Node>.size * _info.availableNodes, using: storage.fileHandle)
        _nodes = Nodes(repeating: Node(), count: Int(_info.availableNodes))
        _nodes.withUnsafeMutableBufferPointer { nd.copyBytes(to: $0) }
        _dirty.nodes = false
    }
    ///
    func load(from address: Address, what: Properties = .All) throws {
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
extension NodesPage: CustomStringConvertible {
    var description: String {
        return """
        Page(Address: \(pageAddress), AvailableNodes: \(_info.availableNodes) (\(_nodes.count))
        """
    }
}

@available(macOS 10.15.4, *)
extension PageInfo: Equatable {
//    static func == (lhs: NodesPage.Info, rhs: NodesPage.Info) -> Bool {
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
    func store(using storage: StorageSystem, address: Address) throws {
        try _store(from: self).update(startNodeAddress: address, using: storage.fileHandle)
    }
    func store(using storage: StorageSystem, with chunks: Allocator.Chunks) throws {
        try _store(from: self).store(with: chunks, using: storage.fileHandle)
    }
    static func load(using storage: StorageSystem, at address: Address) throws -> PageInfo {
        let di = try Data.load(start: address, upTo: MemoryLayout<PageInfo>.size, using: storage.fileHandle)
        var info = PageInfo()
        try _load(into: &info, from: di)
        return info
    }
}

extension Address {
    static var invalid: Address { return Address.max }
}
