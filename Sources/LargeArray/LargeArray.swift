//
//  LargeArray.swift
//
//
//  Created by Hristo Doichev on 9/17/21.
//
import Foundation
import Allocator

public typealias Address = Int

///
//protocol StorageAccessor {
//    func write<T: DataProtocol>(_ data: T, at address: Address) throws
//    func write<T: DataProtocol>(data: T) throws
//    func read(from address: Address, upToCount: Int) throws -> Data?
//    func read(bytesCount: Int) throws -> Data?
//    func seek(to: Address) throws
//}

/// Aggregate all the classes used for storage
struct StorageSystem {
    var fileHandle: FileHandle
    var allocator: Allocator
    var nodeCache: Int
    var pageCache: Int
}
///
///  LargeArray structure:
///   Header:
///   IndexPage:
///     Info:
///     nodes: ContiguousArray<Node>
///     --- The Nodes are stored immediately after the IndexPage.Info information ---
///
///    ... the rest is a mixture of Objects data (which is pointed to by the Nodes) and additional IndexPages
///
///  Node:
///     address: Address
///     used: Int
///     reserved: Int
///
///
@available(macOS 10.15.4, *)
public class LargeArray /*: MutableCollection, RandomAccessCollection */{
    public typealias Element = Data
    public typealias Index = Int

    var _storage: StorageSystem
    let _rootAddress: Address
    var _header: Header
    let _maxElementsPerPage: Index
    var _currentPage: IndexPage
    @usableFromInline
    var _currentPage_startIndex: Index
    var _dirty: Bool = false
    ///
    enum WalkDirection: Int {
        case Up, Down
    }
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
    private var totalUsedCount: Address {
        get {
            return _header._totalUsedBytesCount
        }
        set {
//            if newValue < 0 { }
            _header._totalUsedBytesCount = newValue
        }
    }
    ///
    public var totalUsedBytesCount: Address {
        return _header._totalUsedBytesCount
    }
    public var totalFreeBytesCount: Int {
        return _storage.allocator.freeByteCount
    }
    ///
    init(start root: Address, maxPerPage: Index, fileHandle: FileHandle, capacity: Int = Int.max) throws {
        _storage = StorageSystem(fileHandle: fileHandle,
                                 allocator: Allocator(capacity: capacity, start: root + MemoryLayout<Header>.size),
                                 nodeCache: 0,
                                 pageCache: 0)
        _rootAddress = root
        _header = Header()
        _currentPage_startIndex = 0
        _maxElementsPerPage = maxPerPage

        _currentPage = IndexPage()
        _currentPage_startIndex = 0
        
        // Read header if possible. If error, throw
        do {
            try _load(into: &_header, from: _storage.fileHandle.read(from: _rootAddress, upToCount: MemoryLayout<Header>.size) ?? Data())
            guard _header._version <= _LA_VERSION else { throw LAErrors.InvalidFileVersion }
            // Load the Allocator free space.
            _storage.allocator = try Allocator.load(using: _storage, from: _header._freeRoot)
            
            try _currentPage = IndexPage(address: _header._startPageAddress, using: _storage)
            try _currentPage.load(from: _header._startPageAddress)
//            guard _header._startPageAddress == _currentPage.pageAddress else { throw LAErrors.CorruptedPageAddress }
            // TODO: Better verification that the data is correct
            return
        } catch {
            // Don't override the contents of the file. Continue only if storing data at the 'end' of the file.
            // TODO: Is this check good enough???
            
            // if the rootAddress is at the end of file, then we can go on, othrwise the file contains data
            // and there was an exception while reaing it.
            guard try _storage.fileHandle.seekToEnd() == _rootAddress else { throw error }
        }

        _currentPage = try IndexPage(maxNodes: _maxElementsPerPage, using: _storage)
        _header._startPageAddress = _currentPage.pageAddress
//        try storeHeader()
//        try _currentPage.store()
    }
    ///
    public convenience init?(path: String, capacity: Int = Address.max, maxPerPage: Index = 1024) {
        if FileManager.default.fileExists(atPath: path) == false {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let fh = FileHandle(forUpdatingAtPath: path) {
            do {
                try self.init(start: 0, maxPerPage: maxPerPage, fileHandle: fh, capacity: capacity)
            } catch {
                return nil
            }
        } else {
            return nil
        }
    }
    ///
    deinit {
        do {
            if _dirty {
                _header._freeRoot = try _storage.allocator.store(using: _storage)
                try storeHeader()
                try _currentPage.store()
            }
        } catch {
            /// Hmmm. Exception in deinit. Not good.
        }
//        if _fileHandle.
        try! _storage.fileHandle.close()
    }
    ///
    func storeHeader() throws {
        try _storage.fileHandle.seek(toOffset: UInt64(_rootAddress))
        try _storage.fileHandle.write(contentsOf: _store(from: _header))
    }
    ///
    func createNode(with data: Data) throws -> Node {
        // Store the data and create a node to point to it.
        let overhead = MemoryLayout<Node>.size
        guard let allocated = _storage.allocator.allocate(data.count, overhead: overhead) else { throw LAErrors.AllocationFailed}
        let node = Node(chunk_address: allocated[0].address, used: data.count, reserved: data.count)
        try data.storeWithNodes(chunks: allocated, using: _storage.fileHandle)
        _dirty = true
        return node
    }
    /// Update the data stored in Node.
    /// This function follows the chain of Nodes in order to find all relevant chunks.
    func updateNodeData(_ node: Node, contentsOf data: Data) throws {
        var nodeAddress = node.chunk_address
        var n = Node()
        try data.withUnsafeBytes{ buffer in
            var bufPosition = 0
            try n.load(using: _storage.fileHandle, from: nodeAddress)
            let usedCount = Swift.min(data.count, n.used)
            if usedCount != n.used {
                // update the stored node
                n.used = usedCount
                try n.store(using: _storage.fileHandle, at: nodeAddress)
            }
            try buffer.baseAddress!.store(fromOffset: bufPosition, byteCount: usedCount, using: _storage.fileHandle)
//            guard let srcPtr = UnsafeMutableRawPointer(bitPattern: Int(bitPattern: buffer.baseAddress!.advanced(by: bufPosition))) else { throw LAErrors.ErrorConstructingSourcePointer }
//            let chunkData = Data(bytesNoCopy: srcPtr, count: usedCount, deallocator: .none)
//            try _fileHandle.write(chunkData)
            bufPosition += usedCount
            nodeAddress = n.chunk_address
        }
    }
    func getNodeData(_ node: Node) throws -> Data {
        return try node.loadData(using: _storage.fileHandle).0
    }
    ///
    /*mutating*/
    func createNewCurrentPage() throws {
        var newPage = try IndexPage(maxNodes: _maxElementsPerPage, using: _storage)
        newPage.info.prev = _currentPage.pageAddress
        // First: Store the new page, thus when the current_page.next is updated it will point to a properly stored data.
        try newPage.store()
        // Second: Store the updated NexPageAddress of the current page.
        _currentPage.info.next = newPage.pageAddress
        try _currentPage.store()
        // Last: Set the new page as the current page and update related properties.
        _currentPage_startIndex = _currentPage_startIndex + Index(_currentPage.info.availableNodes)
        _currentPage = newPage
        
        _dirty = true
    }
    ///
    func provideSpaceInCurrentPage() throws {
        if _currentPage.info.next != Address.invalid {
            // move some of the nodes from the current page to the next, if that is possible.
            // Otherwise create a new page and split the nodes between the current and the new page.
            var nextPage = try IndexPage(address: _currentPage.info.next, using: _storage)
            if nextPage.info.availableNodes < nextPage.info.maxNodes/2 {
                try nextPage.load(from: nextPage.pageAddress, what: .Nodes)
                let elementsCount = nextPage.info.maxNodes/2
                try _currentPage.moveNodes((_currentPage.info.availableNodes-elementsCount..<_currentPage.info.availableNodes), into: &nextPage)
                try nextPage.store()
                try _currentPage.store()
            }
        }
        if _currentPage.isFull {
            try splitCurrentPage()
        }
        _dirty = true
    }
    ///
    func splitCurrentPage() throws {
        var newPage = try IndexPage(maxNodes: _maxElementsPerPage, using: _storage)
        newPage.info.prev = _currentPage.pageAddress
        newPage.info.next = _currentPage.info.next
        // Update the _curPage.info._next page to point to the newPage.
        if _currentPage.info.next != Address.invalid {
            var pageToUpdate = try IndexPage(address: _currentPage.info.next, using: _storage)
            pageToUpdate.info.prev = newPage.pageAddress
            try pageToUpdate.store()
        }
        // now, link the current page with the split (new) page
        _currentPage.info.next = newPage.pageAddress
        // Move half of the nodes to the new page and save it
        try _currentPage.moveNodes(_currentPage.info.availableNodes/2..<_currentPage.info.availableNodes, into: &newPage)
        try newPage.store()
        try _currentPage.store()
    }
    ///
    @inlinable
    func indexRelativeToCurrentPage(_ position: Index) -> Index {
        return position - _currentPage_startIndex
    }
    ///
    func isItemInCurrentPage(at position: Index) -> Bool {
        return _currentPage.isValidIndex(indexRelativeToCurrentPage(position))
    }
    ///
    func findPageForInsertion(position: Index) throws {
        var startPos = _currentPage_startIndex
        var range = (startPos...startPos + _currentPage.info.availableNodes)
        guard range.contains(position) == false else { return  }
        try _currentPage.store()
        let direction = position > range.upperBound ? WalkDirection.Down: WalkDirection.Up
        while range.contains(position) == false {
            let address = (direction == .Up) ? _currentPage.info.prev : _currentPage.info.next
            guard address != Address.invalid else { throw LAErrors.PositionOutOfRange }
            if direction == .Down { startPos += _currentPage.info.availableNodes }
            try _currentPage.load(from: address)
            if direction == .Up { startPos -= _currentPage.info.availableNodes }
            range = (startPos...startPos+_currentPage.info.availableNodes)
        }
        _currentPage_startIndex = startPos
        try _currentPage.load(from: _currentPage.pageAddress, what: .Nodes)
    }
    ///
    func findPageForAccess(position: Index) throws {
        var startPos = _currentPage_startIndex
        var range = (startPos..<startPos + _currentPage.info.availableNodes)
        guard range.contains(position) == false else { return }
        try _currentPage.store()
        let direction = position < range.upperBound ? WalkDirection.Up: WalkDirection.Down
        while range.contains(position) == false {
            let address = (direction == .Up) ? _currentPage.info.prev : _currentPage.info.next
            guard address != Address.invalid else { throw LAErrors.PositionOutOfRange }
            if direction == .Down { startPos += _currentPage.info.availableNodes }
            try _currentPage.load(from: address, what: .Info)
            if direction == .Up { startPos -= _currentPage.info.availableNodes }
            range = (startPos..<startPos+_currentPage.info.availableNodes)
        }
        _currentPage_startIndex = startPos
        try _currentPage.load(from: _currentPage.pageAddress, what: .Nodes)
    }
    ///
    /*mutating*/
    func getNodeFor(position: Index) throws -> Node {
        try findPageForAccess(position: position)
        return _currentPage.node(at: indexRelativeToCurrentPage(position))
    }
    /// When nodes are removed the current page can become empty and perhaps a page with some data should be loaded. Perhaps not?!?!?
    func adjustCurrentPageIfRequired() throws {
        if _header._count  == 0 {
            try _currentPage.store()
            guard _currentPage_startIndex == 0 else { throw LAErrors.CorruptedStartIndex}
            try _currentPage.load(from: _header._startPageAddress)
            return
        }
        guard _currentPage.info.next != Address.max || _currentPage.info.prev != Address.max else { return }
                
        if _currentPage.info.availableNodes == 0 {
//            try _currentPage.store()
           
            let nextAddress = _currentPage.info.next
            let prevAddress = _currentPage.info.prev
            try _currentPage.deallocate()
            if nextAddress != Address.max {
                // load the prev page as _current
                try _currentPage.load(from: nextAddress)
            } else {
                // load the next page as _current
                try _currentPage.load(from: prevAddress)
                _currentPage_startIndex -= _currentPage.info.availableNodes
            }
            _dirty = true
        }
    }
}

@available(macOS 10.15.4, *)
extension LargeArray {
    public func indexPagesInfo() throws -> [PageInfo] {
        try _currentPage.store() // ensure it is stored.
        var infos = [PageInfo]()
        var pageAddress = _header._startPageAddress
        while pageAddress != Address.invalid {
            let page = try PageInfo.load(using: _storage, at: pageAddress)
            infos.append(page.0)
            pageAddress = page.0.next
        }
        return infos
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
        get {
            do {
                return try autoreleasepool {
                    return try getNodeData(getNodeFor(position: position))
                }
            } catch {
                fatalError("\(error.localizedDescription) - Position: \(position)")
            }
        }
        set {
            do {
                try autoreleasepool {
                    let node = try getNodeFor(position: position)
                    if node.used != newValue.count {
                        // Deallocate the existing node data - such that it is available for reuse
                        try _storage.allocator.deallocate(chunks: node.getChunksForData(using: _storage.fileHandle))
                        // Create a new node
                        let newNode = try createNode(with: newValue)
                        _currentPage.updateNode(at: indexRelativeToCurrentPage(position), node: newNode)
                    } else {
                        try updateNodeData(node, contentsOf: newValue)
                    }
                }
//                try _currentPage.store(using: _fileHandle) // Store all ... perhaps later>???
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    public subscript<T: Codable>(position: Index) -> T {
        get { try! JSONDecoder().decode(T.self, from: self[position]) }
        set { self[position] = try! JSONEncoder().encode(newValue) }
    }
//    @inlinable
    public /*mutating*/ func append(_ element: Data) throws {
        try autoreleasepool {
            // update the IndexPage and store that too??? Or store the IndexPage only after a number of changes have occurred.
            try appendNode(createNode(with: element))
//            try _currentPage.store(using: _fileHandle) // store All ... perhaps later???
        }
    }
    public func append<T:Codable>(_ element: T) throws {
        try self.append(JSONEncoder().encode(element))
    }
//    @inlinable
    public func remove(at position: Index) throws {
        try autoreleasepool {
            let node = try getNodeFor(position: position)
            try _storage.allocator.deallocate(chunks: node.getChunksForData(using: _storage.fileHandle))
            _currentPage.removeNode(at: indexRelativeToCurrentPage(position))
            
//            try _currentPage.store(using: _fileHandle) // store All ... perhaps later???
            totalCount -= 1
            totalUsedCount -= Address(node.used)
            try adjustCurrentPageIfRequired()
            _dirty = true
        }
    }
    ///
    public func removeSubrange(_ range: Range<Int>) throws {
        // TODO: This can be optimized by removeing chunks of Nodes from each page rather than rather than going one at a time
        try range.forEach { _ in try remove(at: range.startIndex) }
    }
    ///
    public func insert(_ element: Element, at position: Index) throws {
        try autoreleasepool {
            // Find in which page the Element should be inserted.
            // If the pate is full - then split it in a half (creating two linked pages) and insert the new
            // element into one of those pages.
            try findPageForInsertion(position: position)
            if _currentPage.isFull {
                // Split into two pages and then insert the item into one of them.
                try provideSpaceInCurrentPage()
                try findPageForInsertion(position: position)
            }
            try _currentPage.insertNode(createNode(with: element), at: indexRelativeToCurrentPage(position))
            totalCount += 1
            totalUsedCount += element.count
        }
    }
    public func insert<T: Codable>(_ element: T, at position: Index) throws {
        try self.insert(JSONEncoder().encode(element), at: position)
    }
    /// Append a node. The Data associated with the Node is not moved or copied.
    func appendNode(_ node: Node) throws {
        try findPageForInsertion(position: _header._count)
        if _currentPage.isFull {
            try createNewCurrentPage()
        }
        try _currentPage.appendNode(node)
        totalCount += 1
        totalUsedCount += Address(node.used)
    }
}
@available(macOS 10.15.4, *)
extension LargeArray: Collection {
}

@available(macOS 10.15.4, *)
extension LargeArray: CustomStringConvertible {
    public var description: String {
        """
        \(LargeArray.self):
            \(self._header)
            currentPage_StartIndex: \(_currentPage_startIndex)
            \(_currentPage)
        """
    }
}
///
extension MemoryLayout {
    static var description: String {
        "\(T.self) : \(MemoryLayout<T>.size), \(MemoryLayout<T>.alignment), \(MemoryLayout<T>.stride)"
    }
}

@available(macOS 10.15.4, *)
extension FileHandle/*: StorageAccessor */{
    func write<T: DataProtocol>(_ data: T, at address: Address) throws {
        try self.seek(toOffset: UInt64(address))
        try self.write(contentsOf: data)
    }
    func write<T: DataProtocol>(data: T) throws {
        try self.write(contentsOf: data)
    }
    func read(from address: Address, upToCount: Int) throws -> Data? {
        try self.seek(toOffset: UInt64(address))
        return try self.read(upToCount: upToCount)
    }
    func read(bytesCount: Int) throws -> Data? {
        return try self.read(upToCount: bytesCount)
    }
    func seek(to address: Address) throws {
        try self.seek(toOffset: UInt64(address))
    }
}

@available(macOS 10.15.4, *)
extension UnsafeRawPointer {
    func store(fromOffset: Int, byteCount: Int, using fileHandle: FileHandle) throws {
        guard let srcPtr = UnsafeMutableRawPointer(bitPattern: Int(bitPattern: self.advanced(by: fromOffset))) else { throw LAErrors.ErrorConstructingSourcePointer }
        let chunkData = Data(bytesNoCopy: srcPtr, count: byteCount, deallocator: .none)
        try fileHandle.write(data: chunkData)
    }
}

@available(macOS 10.15.4, *)
extension Allocator {
    /// Load the allocator state fron the StorageSystem
    static func load(using storage: StorageSystem, from address: Address) throws -> Allocator {
        return try JSONDecoder().decode(Allocator.self, from: Data.loadFromNodes(start: address, using: storage.fileHandle).0)
    }
    /// Store the allocator state to the storage system
    /// 1) Capture the current state of the Allocator.
    /// 2) Allocate space to store that state (Data)
    /// 3) Store the state.
    ///
    /// When loading the state (at some later time) the saved state will not include the
    /// allocations for the state storage. Thus loading the stored state will automatically
    /// udno the allocated space used for storing the Allocator space.
    func store(using storage: StorageSystem) throws -> Address {
        let encodedAllocator = try JSONEncoder().encode(self)
        print("Allocator encoded count: \(encodedAllocator.count)")
        guard let chunks = try self.allocate(encodedAllocator.count, overhead: MemoryLayout<Node>.size) else { throw LAErrors.AllocationFailed }
        try encodedAllocator.storeWithNodes(chunks: chunks, using: storage.fileHandle)
        return chunks[0].address
    }
}
