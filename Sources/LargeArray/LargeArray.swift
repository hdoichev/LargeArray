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
    case InvalidFileVersion
    case CorruptedIndex
}

typealias Address = UInt64

///
protocol StorageAccessor {
    func write<T: DataProtocol>(_ data: T, at address: Address) throws
    func write<T: DataProtocol>(data: T) throws
    func read(from address: Address, upToCount: Address) throws -> Data?
    func read(bytesCount: Address) throws -> Data?
    func seek(to: Address) throws
}

///
public let _LA_VERSION: Int = 1
struct Header: Codable {
    let _version: Int
    var _count: UInt64 /// Total number of lelements in the Array
}
///
struct Node: Codable {
    var address: Address = 0
    var used: Address = 0
    var reserved: Address = 0
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
    var _currentPage: IndexPage
    var _currentPage_startIndex: Index
    ///
    var _fileHandle: FileHandle
//    var _currentPageNode: Node
    @usableFromInline
    var _storage: [Any]
    ///
    mutating func appendNode(_ data:Data) throws {
        if _currentPage._nodes.count >= _maxElementsPerPage {
            try createNewCurrentPage()
        }
        // Store the data and create a node to point to it.
        let node = try Node(address: _fileHandle.seekToEnd(), used: Address(data.count), reserved: Address(data.count))
        try _fileHandle.write(contentsOf: data)
        
        // update the IndexPage and store that too??? Or store the IndexPage only after a number of changes have occurred.
        _currentPage._nodes.append(node)
        try _currentPage.store(using: _fileHandle) // store All
    }
    ///
    mutating func removeNode(at position: Index) {
        
    }
    ///
    mutating func createNewCurrentPage() throws {
        var newPage = IndexPage(address: _fileHandle.seekToEndOfFile(), maxNodes: _maxElementsPerPage)
        newPage._info._prev = _currentPage._info._address
        // First: Store the new page, thus when the current_page.next is updated it will point to a properly stored data.
        try newPage.store(using: _fileHandle)
        // Second: Store the updated NexPageAddress of the current page.
        _currentPage._info._next = newPage._info._address
        try _currentPage.store(using: _fileHandle, what: .Info)
        // Last: Set the new page as the current page and update related properties.
        _currentPage_startIndex = _currentPage_startIndex + Index(_currentPage._nodes.count)
//        print("CurrentPage: \(_currentPage)")
//        print("NewPage: \(newPage)")
        _currentPage = newPage
    }
    ///
    func isItemIndexInCurrentPage(index: Index) -> Bool {
        return (_currentPage_startIndex..<(_currentPage_startIndex+_currentPage._nodes.count)).contains(index)
    }
    ///
    mutating func loadPageFor(index: Index) throws {
        guard isItemIndexInCurrentPage(index: index) == false else { return }
        let traverseUp = (index < _currentPage_startIndex)
        var page = IndexPage(address: 0, maxNodes: _maxElementsPerPage)
        while isItemIndexInCurrentPage(index: index) == false {
            guard traverseUp == (index < _currentPage_startIndex) else { throw LAErrors.CorruptedIndex }
            let addressToLoad = traverseUp ? _currentPage._info._prev : _currentPage._info._next
            guard addressToLoad != 0 else { throw LAErrors.CorruptedIndex }
            try page.load(using: _fileHandle, from: addressToLoad, what: .Info)
            traverseUp ? (_currentPage_startIndex -= page._info._availableNodes) :
                         (_currentPage_startIndex += page._info._availableNodes)
        }
        _currentPage = page
        try _currentPage.load(using: _fileHandle, from: page._info._address, what: .Nodes)
    }
    ///
    mutating func getNodeFor(index: Index) throws -> Node {
        try loadPageFor(index: index)
        return _currentPage._nodes[index - _currentPage_startIndex]
    }
}


@available(macOS 10.15.4, *)
extension LargeArray: MutableCollection, RandomAccessCollection {
    init?(path: String, maxPerPage: Index = 1024) {
        if FileManager.default.fileExists(atPath: path) == false {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let fh = FileHandle(forUpdatingAtPath: path) {
            _fileHandle = fh
        } else {
            return nil
        }
        //
        _header = Header(_version: _LA_VERSION, _count: 0)
        _maxElementsPerPage = maxPerPage
        let rootPageaddress: Address = Address(MemoryLayout<Header>.size)
        _currentPage = IndexPage(address: rootPageaddress, maxNodes: _maxElementsPerPage)
        _currentPage_startIndex = 0
        _storage = [Any]()

        let fileSize = _fileHandle.seekToEndOfFile()
        if fileSize > MemoryLayout<Header>.size {
            do {
                // try to initialize from the file
                try _fileHandle.seek(toOffset: 0)
                // Header
                let headerData = _fileHandle.readData(ofLength: MemoryLayout<Header>.size)
                try _load(into: &_header, from: headerData)
                guard _header._version <= _LA_VERSION else { throw LAErrors.InvalidFileVersion }
                try _currentPage.load(using: _fileHandle, from: rootPageaddress)
            } catch {
                // Log Error
                return nil
            }
        } else {
            // store initial state to file
            do {
                try _fileHandle.seek(toOffset: 0)
                try _fileHandle.write(contentsOf: _store(from: _header))
                try _currentPage.store(using: _fileHandle)
            } catch {
                // Log Error
                return nil
            }
        }
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

extension Node: CustomStringConvertible {
    var description: String {
        "Node(address: \(address), used: \(used), reserved: \(reserved))"
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
    func read(bytesCount: Address) throws -> Data? {
        return try self.read(upToCount: Int(bytesCount))
    }
    func seek(to address: Address) throws {
        try self.seek(toOffset: address)
    }
}

