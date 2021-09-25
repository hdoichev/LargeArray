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
    case IndexMismatch
    case CorruptedPageAddress
}

typealias Address = UInt64

///
protocol StorageAccessor {
    func write<T: DataProtocol>(_ data: T, at address: Address) throws
    func write<T: DataProtocol>(data: T) throws
    func read(from address: Address, upToCount: Int) throws -> Data?
    func read(bytesCount: Int) throws -> Data?
    func seek(to: Address) throws
}

///
public let _LA_VERSION: Int = 1
struct Header: Codable {
    let _version: Int
    var _count: Int /// Total number of lelements in the Array
}
///
struct Node: Codable {
    var address: Address = 0
    var used: Int = 0
    var reserved: Int = 0
}

///
///  LargeArray structure:
///   Header:
///     Version: Int
///     Count: Int  // the number of elements in the array
///     MaxNodesPerPage: Int // The number of node per page. This help calculate the page size.
///   IndexPage:
///     Info:
///         address: Address - the address of the page
///         _availableNodes: LargeArray.Index - how many nodes are stored in this page
///         _maxNodes: LargeArray.Index - maximum nodes per page
///         _next: Address - next node, if any
///         _prev: Address - previous node, if any
///     nodes: ContiguousArray<Node>
///     --- The Nodes are stored immediately after the IndexPage.Info information ---
///
///    ... the rest is a mixture of Objects data (which is pointed to by the Nodes) and additional IndexPages
///
///  Node:
///     address: UInt64
///     used: Int
///     reserved: Int
///
///
@available(macOS 10.15.4, *)
public class LargeArray /*: MutableCollection, RandomAccessCollection */{
    public typealias Element = Data
    public typealias Index = Int /// TODO: Change this UInt64
//    public typealias Address = UInt64
    
    var _header: Header
    let _maxElementsPerPage: Index
    var _currentPage: IndexPage
    @usableFromInline
    var _currentPage_startIndex: Index
    ///
    var _fileHandle: FileHandle
    ///
    private var totalCount: Index {
        get {
            _header._count
        }
        set {
            if newValue < 0 { fatalError("Invalid array count.") }
            _header._count = newValue
        }
    }
    ///
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
    ///
    func createNode(with data: Data) throws -> Node {
        // Store the data and create a node to point to it.
        let node = try Node(address: _fileHandle.seekToEnd(), used: data.count, reserved: data.count)
        try _fileHandle.write(contentsOf: data)
        return node
    }
    ///
    /*mutating*/ func removeNode(at position: Index) {
        
    }
    ///
    /*mutating*/ func createNewCurrentPage() throws {
        var newPage = IndexPage(address: _fileHandle.seekToEndOfFile(), maxNodes: _maxElementsPerPage)
        newPage.info._prev = _currentPage.info._address
        // First: Store the new page, thus when the current_page.next is updated it will point to a properly stored data.
        try newPage.store(using: _fileHandle)
        // Second: Store the updated NexPageAddress of the current page.
        _currentPage.info._next = newPage.info._address
        try _currentPage.store(using: _fileHandle)
        // Last: Set the new page as the current page and update related properties.
        _currentPage_startIndex = _currentPage_startIndex + Index(_currentPage.info._availableNodes)
//        print("CurrentPage: \(_currentPage)")
//        print("NewPage: \(newPage)")
        _currentPage = newPage
    }
    ///
    @inlinable
    func indexRelativeToCurrentPage(_ index: Index) -> Index {
        return index - _currentPage_startIndex
    }
    ///
    func isItemIndexInCurrentPage(index: Index) -> Bool {
        return _currentPage.isValidIndex(indexRelativeToCurrentPage(index))
    }
    ///
    /*mutating*/ func loadPageFor(index: Index) throws {
        guard isItemIndexInCurrentPage(index: index) == false else { return }
        try _currentPage.store(using: _fileHandle)
        let traverseUp = (index < _currentPage_startIndex)
        while isItemIndexInCurrentPage(index: index) == false {
            guard traverseUp == (index < _currentPage_startIndex) else { throw LAErrors.IndexMismatch }
            let addressToLoad = traverseUp ? _currentPage.info._prev : _currentPage.info._next
            guard addressToLoad != 0 else {
                throw LAErrors.CorruptedPageAddress
            }
            try _currentPage.load(using: _fileHandle, from: addressToLoad, what: .Info)
            traverseUp ? ( _currentPage_startIndex -= _currentPage.info._availableNodes ) :
                         ( _currentPage_startIndex += _currentPage.info._availableNodes )
        }
        try _currentPage.load(using: _fileHandle, from: _currentPage.info._address, what: .Nodes)
    }
    ///
    /*mutating*/ func getNodeFor(index: Index) throws -> Node {
        try loadPageFor(index: index)
        return _currentPage.node(at: indexRelativeToCurrentPage(index))
    }
    ///
    func addNodeToFreePool(_ node: Node) {
        
    }
    /// When nodes are removed the current page can become empty and perhaps a page with some data should be loaded. Perhaps not?!?!?
    func adjustCurrentPageIfRequired() {
        if _currentPage.info._availableNodes == 0 {
            // The current Page is empty so load a page with proper indexes, if available.
            // If there are no other pages with data, then we start from the root
            if _currentPage.info._prev != 0 || _currentPage.info._next != 0 {
            } else {
                // There are no page with data - the array is empty
            }
        }
    }
}


@available(macOS 10.15.4, *)
extension LargeArray: MutableCollection, RandomAccessCollection {
    @inlinable public var startIndex: Index {
        return 0
    }
//    @inlinable
    public var endIndex: Index {
        return _header._count
    }
    @inlinable public func index(after i: Index) -> Index {
        return i + 1
    }
    
//    @inlinable
    public subscript(position: Index) -> Data {
//    public subscript<T: Decodable>(position: Index) -> T {
        get {
            do {
                let node = try getNodeFor(index: position)
                guard let nodeData = try _fileHandle.read(from: node.address, upToCount: node.used) else { throw LAErrors.ErrorReadingData }
                return nodeData
            } catch {
                fatalError("\(error.localizedDescription) - Position: \(position)")
            }
        }
        set {
            do {
                var node = try getNodeFor(index: position)
                if node.reserved < newValue.count {
                    // TODO: Move the old node+data for reuse.
                    // Create a new node
                    let newNode = try createNode(with: newValue)
                    addNodeToFreePool(node)
                    _currentPage.updateNode(at: indexRelativeToCurrentPage(position), node: newNode)
                } else {
                    node.used = newValue.count
                    _currentPage.updateNode(at: indexRelativeToCurrentPage(position), node: node)
                }
//                try _currentPage.store(using: _fileHandle) // Store all ... perhaps later>???
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
//    @inlinable
//    public /*mutating*/ func append<T:Codable>(_ newElement:T) throws {
    public /*mutating*/ func append(_ newElement: Data) throws {
        if _currentPage.info._availableNodes >= _maxElementsPerPage {
            try createNewCurrentPage()
        }
        
        // update the IndexPage and store that too??? Or store the IndexPage only after a number of changes have occurred.
        try _currentPage.appendNode(createNode(with: newElement))
//        try _currentPage.store(using: _fileHandle) // store All ... perhaps later???
        totalCount += 1
    }
//    @inlinable
    public func remove(at position: Index) throws {
        let node = try getNodeFor(index: position)
        _currentPage.removeNode(at: indexRelativeToCurrentPage(position))
        // TODO: Move the old node+data for reuse.
        addNodeToFreePool(node)
        
//        try _currentPage.store(using: _fileHandle) // store All ... perhaps later???
        totalCount -= 1
        adjustCurrentPageIfRequired()
    }
}
@available(macOS 10.15.4, *)
extension LargeArray: CustomStringConvertible {
    public var description: String {
        """
        \(LargeArray.self)
        \(self._header)
        currentPage_StartIndex: \(_currentPage_startIndex)
        \(_currentPage)
        """
    }
}
///
extension Header: CustomStringConvertible {
    var description: String {
        "\(Header.self): version: \(_version), count: \(_count)"
    }
}
///
extension MemoryLayout {
    static var description: String {
        "\(T.self) : \(MemoryLayout<T>.size), \(MemoryLayout<T>.alignment), \(MemoryLayout<T>.stride)"
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
    func read(from address: Address, upToCount: Int) throws -> Data? {
        try self.seek(toOffset: address)
        return try self.read(upToCount: upToCount)
    }
    func read(bytesCount: Int) throws -> Data? {
        return try self.read(upToCount: bytesCount)
    }
    func seek(to address: Address) throws {
        try self.seek(toOffset: address)
    }
}

extension LAErrors: CustomStringConvertible {
    var description: String {
        switch self {
        case .ErrorReadingData: return "ErrorRadingData"
        case .InvalidWriteBufferSize: return "InvalidWriteBufferSize"
        case .InvalidReadBufferSize: return "InvalidReadBufferSize"
        case .CorruptedPageAddress: return "CorruptedPageAddress"
        case .IndexMismatch: return "IndexMismatch"
        case .InvalidAddressInIndexPage: return "InvalidAddressInIndexPage"
        case .InvalidFileVersion: return "InvalidFileVersion"
        case .NilBaseAddress: return "NilBaseAddress"
        }
    }
}
