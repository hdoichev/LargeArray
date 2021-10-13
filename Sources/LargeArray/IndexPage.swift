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
@available(macOS 10.15.4, *)
extension PageInfo {
    public var isFull: Bool { availableNodes >= maxNodes }
    public var freeSpaceCount: Int { return maxNodes - availableNodes }
}
///
@available(macOS 10.15.4, *)
struct IndexPage {
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
    private var _storage: StorageSystem
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
    init() {
        _infoAddress = Int.max
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _storage = StorageSystem(fileHandle: FileHandle(), allocator: Allocator(capacity: 0), nodeCache: 0, pageCache: 0)
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
    mutating func deallocate() throws {
        try Node.deallocate(start: _infoAddress, using: _storage)
        try Node.deallocate(start: _info.nodes_address, using: _storage)
        // remove this page from the prev and next pages.
        if _info.prev != Address.max {
            var prevInfo = try PageInfo.load(using: _storage, at: _info.prev)
            prevInfo.next = _info.next
            try prevInfo.store(using: _storage, address: _info.prev)
        }
        if _info.next != Address.max {
            var nextInfo = try PageInfo.load(using: _storage, at: _info.next)
            nextInfo.prev = _info.prev
            try nextInfo.store(using: _storage, address: _info.next)
        }
        _info = PageInfo()
        _nodes = Nodes()
        _dirty = Dirty()
        _infoAddress = Int.max
    }
    /// Either move some the nodes from this page to the next, or create a new page and then move some
    /// of the nodes from this page into the new one.
    ///
    ///
    mutating func ensurePageHasFreeSpace() throws {
        guard isFull else { return }
        // Ensure nodes are loaded so we can move them to another page.
        if _nodes.isEmpty {
            try _loadNodes()
        }
        
        if self._info.next != Address.invalid {
            // move some of the nodes from the current page to the next, if that is possible.
            // Otherwise create a new page and split the nodes between the current and the new page.
            var nextPage = try IndexPage(address: self._info.next, using: _storage)
            if nextPage.info.availableNodes < nextPage.info.maxNodes/2 {
                try nextPage.load(from: nextPage.pageAddress, what: .Nodes)
                let elementsCount = nextPage.info.maxNodes/2
                try self.moveNodes(NodeMoveLocation.ToFront(self._info.availableNodes-elementsCount..<self._info.availableNodes),
                                   into: &nextPage)
                try nextPage.store()
                try self.store()
            }
        }
//        if self.isFull && self._info.prev != Address.invalid {
//            var prevPage = try IndexPage(address: self._info.prev, using: _storage)
//            if prevPage._info.availableNodes < prevPage._info.maxNodes/2 {
//                try prevPage.load(from: prevPage.pageAddress, what: .Nodes)
//                let elementsCount = prevPage._info.maxNodes/2
//                try self.moveNodes(NodeMoveLocation.ToBack(0..<self._info.availableNodes-elementsCount),
//                                   into: &prevPage)
//                try prevPage.store()
//                try self.store()
//            }
//        }
        if self.isFull {
            try splitPage()
        }
//        _dirty = Dirty(true)
    }
    mutating func splitPage() throws {
        var newPage = try IndexPage(maxNodes: _info.maxNodes, using: _storage)
        newPage.info.prev = self.pageAddress
        newPage.info.next = self._info.next
        // Update the _curPage.info._next page to point to the newPage.
        if self._info.next != Address.invalid {
            var pageToUpdate = try IndexPage(address: self._info.next, using: _storage)
            pageToUpdate.info.prev = newPage.pageAddress
            try pageToUpdate.store()
        }
        // now, link the current page with the split (new) page
        self.info.next = newPage.pageAddress
        // Move half of the nodes to the new page and save it
        try self.moveNodes(NodeMoveLocation.ToFront(self._info.availableNodes/2..<self._info.availableNodes),
                                                    into: &newPage)
        try newPage.store()
        try self.store()
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
    mutating func updateNode(at position: LargeArray.Index, with node: Node) {
        _dirty.nodes = true
        _nodes[position] = node
    }
    ///
    func node(at position: LargeArray.Index) -> Node {
        return _nodes[position]
    }
    ///
    mutating func moveNodes(_ location: NodeMoveLocation, into outPage: inout IndexPage) throws {
        switch location {
        case .ToBack(let range):
            outPage._nodes += _nodes[range]
            _nodes.removeSubrange(range)
        case .ToFront(let range):
            outPage._nodes = _nodes[range] + outPage._nodes
            _nodes.removeSubrange(range)
        }
        outPage._info.availableNodes = outPage._nodes.count
            
        info.availableNodes = _nodes.count
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
        if _infoAddress == Int.max {
            // Allocate the space for the info and the nodes.
            guard let ainfo = _storage.allocator.allocate(MemoryLayout<PageInfo>.size, overhead: MemoryLayout<Node>.size) else { throw LAErrors.AllocationFailed }
            guard let anodes = _storage.allocator.allocate(MemoryLayout<Node>.size * _info.maxNodes,
                                                           overhead: MemoryLayout<Node>.size) else {
                _storage.allocator.deallocate(chunks: ainfo)
                throw LAErrors.AllocationFailed }
            _infoAddress = ainfo[0].address
            _info.nodes_address = anodes[0].address

            _info.availableNodes = _nodes.count // preserve the count of the actual nodes, so we can properly load the nodes data
            try _store(from: _info).storeWithNodes(chunks: ainfo, using: _storage.fileHandle)
            _dirty.info = false

            var nodesData = Data(repeating: 0, count: MemoryLayout<Node>.size * Int(_info.maxNodes))
            nodesData.withUnsafeMutableBytes { dest in _nodes.withUnsafeBytes { source in dest.copyBytes(from: source) }}
            try nodesData.storeWithNodes(chunks: anodes, using: _storage.fileHandle)
            _dirty.nodes = false
        } else {
            if _dirty.info {
                _info.availableNodes = _nodes.count // preserve the count of the actual nodes, so we can properly load the nodes data
                try _store(from: _info).update(startNodeAddress: _infoAddress, using: _storage.fileHandle)
                _dirty.info = false
            }
            // Store the nodes into the data buffer
            // When storing we always store the _maxNodes size. This prevents the relocation of the IndexPage when elements are added/removed from it.
            // When loading the nodes the _availableNodes is used to read the nodes data, thus only the actual stored elements are loaded.
            //        var nodesData = Data(count: MemoryLayout<Node>.size * Int(_info._maxNodes))
            if _dirty.nodes {
                var nodesData = Data(repeating: 0, count: MemoryLayout<Node>.size * Int(_info.maxNodes))
                nodesData.withUnsafeMutableBytes { dest in _nodes.withUnsafeBytes { source in dest.copyBytes(from: source) }}
                try nodesData.update(startNodeAddress: _info.nodes_address, using: _storage.fileHandle)
                _dirty.nodes = false
            }
        }
    }
    ///
    mutating func _loadInfo(from address: Address) throws {
        let di = try Data.loadFromNodes(start: address, upTo: MemoryLayout<PageInfo>.size, using: _storage.fileHandle)
        try _load(into: &_info, from: di)
        _infoAddress = address
        _dirty.info = false
    }
    ///
    mutating func _loadNodes() throws {
        guard _info.nodes_address != Int.max else { throw LAErrors.InvalidNodeAddress }
        guard _info.availableNodes > 0 else { _nodes.removeAll(); return }
        let nd = try Data.loadFromNodes(start: _info.nodes_address,
                                        upTo: MemoryLayout<Node>.size * _info.availableNodes, using: _storage.fileHandle)
        _nodes = Nodes(repeating: Node(), count: Int(_info.availableNodes))
        _nodes.withUnsafeMutableBufferPointer { nd.copyBytes(to: $0) }
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
    func store(using storage: StorageSystem, address: Address) throws {
        try _store(from: self).update(startNodeAddress: address, using: storage.fileHandle)
    }
    func store(using storage: StorageSystem, with chunks: Allocator.Chunks) throws {
        try _store(from: self).storeWithNodes(chunks: chunks, using: storage.fileHandle)
    }
    static func load(using storage: StorageSystem, at address: Address) throws -> PageInfo {
        let di = try Data.loadFromNodes(start: address, upTo: MemoryLayout<PageInfo>.size, using: storage.fileHandle)
        var info = PageInfo()
        try _load(into: &info, from: di)
        return info
    }
}

extension Address {
    static var invalid: Address { return Address.max }
}
