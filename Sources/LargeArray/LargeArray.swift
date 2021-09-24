//
//  LargeArray.swift
//
//
//  Created by Hristo Doichev on 9/17/21.
//
import Foundation

enum LAErrors: Error {
    case InvalidReadBufferSize
    case InvalidWriteBufferSize
    case NilBaseAddress
    case ErrorReadingData
    case InvalidAddressInIndexPage
}

typealias Address = UInt64

///
protocol StorageAccessor {
    func write<T: DataProtocol>(_ data: T, at address: Address) throws
    func write<T: DataProtocol>(data: T) throws
    func read(from address: Address, upToCount: Address) throws -> Data?
    func read(upToCount: Address) throws -> Data?
    func seek(to: Address) throws
}

///
///  LargeArray structure:
///   Header:
///     Version: Int
///     Count: UInt64  // the number of elements in the array
///     MaxNodesPerPage: UInt64 // The number of node per page. This help calculate the page size.
///   IndexPage:
///     availableNodes: UInt64 // The nodes available in this page
///     nextPage: UInt64  // Next page address (if any)
///     prevPage: Uint64  // Previous page address (if any)
///     nodes: ContiguousArray<Node>
///     --- The Nodes are stored immediately after the IndexPage information ---
///
///    ... the rest is a mixture of Objects data (which is pointed to by the Nodes) and additional IndexPages
///
///  Node:
///     address: UInt64
///     used: UInt64
///     reserved: Uint64
///
///
@available(macOS 10.15.4, *)
public struct LargeArray /*: MutableCollection, RandomAccessCollection */{
    public typealias Element = Any
    public typealias Index = Int /// TODO: Change this UInt64
//    public typealias Address = UInt64
    
    var _header: Header
    let _maxElementsPerPage: Index
    var _rootPage: IndexPage
    var _currentPage: IndexPage
    var _currentPage_startIndex: Index
    ///
    var _fileHandle: FileHandle
//    var _currentPageNode: Node
    @usableFromInline
    var _storage: [Any]
    
//    init(maxPerPage: Index = 1024)
    
//    @inlinable public var startIndex: Index {
//        return _storage.startIndex
//    }
//    @inlinable public var endIndex: Index {
//        return _storage.endIndex
//    }
//    @inlinable public func index(after i: Index) -> Index {
//        return i + 1
//    }
//
//    @inlinable public subscript(position: Index) -> Any {
//        get {
//            return _storage[position]
//        }
//        set {
//            _storage[position] = newValue
//        }
//    }
    mutating func appendNode(_ data:Data) throws {
        if _currentPage._nodes.count >= _maxElementsPerPage {
            try createNewCurrentPage()
        }
        // Store the data and create a node to point to it.
        let node = try Node(address: _fileHandle.seekToEnd(), used: Address(data.count), reserved: Address(data.count))
        try _fileHandle.write(contentsOf: data)
        
        // update the IndexPage and store that too??? Or store the IndexPage only after a number of changes have occurred.
        _currentPage._nodes.append(Node(address: 0, used: Address(data.count), reserved: Address(data.count)))
        try _currentPage.store(using: _fileHandle) // store All
    }
    mutating func removeNode(at position: Index) {
        
    }
    mutating func createNewCurrentPage() throws {
        let address: Address = 0 // TODO: Get proper page address
        var newPage = IndexPage(address: address, maxNodes: _maxElementsPerPage)
        newPage._info._prev = _currentPage._info._address
        // First: Store the new page, thus when the current_page.next is updated it will point to a properly stored data.
        try newPage.store(using: _fileHandle)
        // Second: Store the updated NexPageAddress of the current page.
        _currentPage._info._next = address
        try _currentPage.store(using: _fileHandle, what: .Info)
        // Last: Set the new page as the current page and update related properties.
        _currentPage_startIndex = _currentPage_startIndex + Index(_currentPage._nodes.count)
        _currentPage = newPage
    }
}

///
struct Header: Codable {
    let _version: Int
    var _count: UInt64 /// Total number of lelements in the Array
}
///
struct Node: Codable {
    var address: Address
    var used: Address
    var reserved: Address
    init () {
        address = 0
        used = 0
        reserved = 0
    }
    init(address: Address, used: Address, reserved: Address) {
        self.address = address
        self.used = used
        self.reserved = reserved
    }
    ///
    func store(into buffer: UnsafeMutableRawBufferPointer) throws {
        let out_buffer = buffer.bindMemory(to: Node.self)
        guard out_buffer.count == 1 else { throw LAErrors.InvalidWriteBufferSize }
        out_buffer[0] = self
//        out_buffer[0] = address
//        out_buffer[1] = used
//        out_buffer[2] = reserved
    }
    mutating func load(from buffer:  UnsafeRawBufferPointer) throws {
        let in_buffer = buffer.bindMemory(to: Node.self)
        guard in_buffer.count == 1 else { throw LAErrors.InvalidReadBufferSize }
        self = in_buffer[0]
//        address = in_buffer[0]
//        used = in_buffer[1]
//        reserved = in_buffer[2]
    }
}
///
@available(macOS 10.15.4, *)
struct IndexPage: Codable {
    enum Properties {
        case All, Info, Nodes
    }
    struct Info: Codable {
        let _address: Address
        var _availableNodes: Address
        var _maxNodes: Address
        var _next: Address
        var _prev: Address
    }
    var _info: Info
    var _nodes: ContiguousArray<Node>
    init(address: Address, maxNodes: LargeArray.Index) {
        _info = Info(_address: address, _availableNodes: 0, _maxNodes: Address(maxNodes), _next: 0, _prev: 0)
        _nodes = ContiguousArray<Node>()
    }
}


@available(macOS 10.15.4, *)
extension LargeArray: MutableCollection, RandomAccessCollection {
    init(maxPerPage: Index = 1024) {
        _header = Header(_version: 1, _count: 0)
        _maxElementsPerPage = maxPerPage
        let address: Address = 0 // TODO: Get proper address for the root.
        _rootPage = IndexPage(address: address, maxNodes: _maxElementsPerPage)
        _currentPage = _rootPage
        _currentPage_startIndex = 0
        _storage = [Any]()
        _fileHandle = FileHandle()
    }
    
    @inlinable public var startIndex: Index {
        return _storage.startIndex
    }
    @inlinable public var endIndex: Index {
        return _storage.endIndex
    }
    @inlinable public func index(after i: Index) -> Index {
        return i + 1
    }
    
    @inlinable public subscript(position: Index) -> Any {
        get {
            return _storage[position]
        }
        set {
            _storage[position] = newValue
        }
    }
    @inlinable public func append<T:Codable>(_ newElement:T) {
        
    }
    @inlinable public func remove(at position:Index) {
        
    }
}

///
extension MemoryLayout {
    static func printInfo() {
        print(T.self, ":", MemoryLayout<T>.size, ", ", MemoryLayout<T>.alignment, ", ", MemoryLayout<T>.stride)
    }
}

extension Node {
    func dump() {
        print("Address = \(self.address), Used = \(self.used), Reserved = \(self.reserved)")
    }
}

extension Node: Equatable {
    static func == (lhs: Node, rhs: Node) -> Bool {
        return
            (lhs.address == rhs.address &&
            lhs.used == rhs.used &&
            lhs.reserved == rhs.reserved)
    }
}

@available(macOS 10.15.4, *)
extension FileHandle: StorageAccessor {
    func write<T: DataProtocol>(_ data: T, at address: Address) throws {
        try self.seek(toOffset: address)
        try self.write(contentsOf: data)
    }
    func write<T: DataProtocol>(data: T) throws {
        try self.write(contentsOf: data)
    }
    func read(from address: Address, upToCount: Address) throws -> Data? {
        try self.seek(toOffset: address)
        return try self.read(upToCount: Int(upToCount))
    }
    func read(upToCount: Address) throws -> Data? {
        return try self.read(upToCount: Int(upToCount))
    }
    func seek(to address: Address) throws {
        try self.seek(toOffset: address)
    }
}

@available(macOS 10.15.4, *)
extension IndexPage {
    /// "at" always points to the location where the entire page can be stored.
    mutating func store(using storageAccessor: StorageAccessor, what: Properties = .All) throws {
        _info._availableNodes = Address(_nodes.count) // preserve the count of the actual nodes, so we can properly load the nodes data
        var data = Data(count: MemoryLayout<Info>.size)
        data.withUnsafeMutableBytes { buffer in
            let out_buffer = buffer.bindMemory(to: Info.self)
//            guard out_buffer.count == 3 else { throw LAErrors.InvalidWriteBufferSize }
            out_buffer[0] = _info
        }
        // Store the nodes into the data buffer
        // When storing we always store the _maxNodes size. This prevents the relocation of the IndexPage when elements are added/removed from it.
        // When loading the nodes the _availableNodes is used to read the nodes data, thus only the actual stored elements are loaded.
        var nodesData = Data(count: MemoryLayout<Node>.size * Int(_info._maxNodes))
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
        if let address = address {
            try storageAccessor.seek(to: address + Address(MemoryLayout<IndexPage.Info>.size))
        }
        let nodesSize = Address(MemoryLayout<Node>.size) * _info._availableNodes
        guard let nodesData = try storageAccessor.read(upToCount: nodesSize) else { throw LAErrors.ErrorReadingData }
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
        ///
//        guard let data = try storageAccessor.read(from: address, upToCount: Address(MemoryLayout<IndexPage.Info>.size)) else { throw LAErrors.ErrorReadingData }
//        try data.withUnsafeBytes { buffer in
//            let in_buffer = buffer.bindMemory(to: IndexPage.Info.self)
//            guard in_buffer.count == 1 else { throw LAErrors.InvalidReadBufferSize }
//            self._info = in_buffer[0]
//        }
//        let nodesSize = Address(MemoryLayout<Node>.size) * _info._availableNodes
//        guard let nodesData = try storageAccessor.read(upToCount: nodesSize) else { throw LAErrors.ErrorReadingData }
//        guard nodesSize == nodesData.count else { throw LAErrors.InvalidReadBufferSize }
//        _nodes = ContiguousArray<Node>(repeating: Node(), count: Int(_info._availableNodes))
//        _nodes.withUnsafeMutableBufferPointer { nodesData.copyBytes(to: $0) }
    }
}
