//
//  LargeArray.swift
//
//
//  Created by Hristo Doichev on 9/17/21.
//
import Foundation
import Allocator
import HArray

public typealias Address = Int

@available(macOS 10.15.4, *)
typealias StorageArray = HArray<StorageSystem>
///
//protocol StorageAccessor {
//    func write<T: DataProtocol>(_ data: T, at address: Address) throws
//    func write<T: DataProtocol>(data: T) throws
//    func read(from address: Address, upToCount: Int) throws -> Data?
//    func read(bytesCount: Int) throws -> Data?
//    func seek(to: Address) throws
//}
@available(macOS 10.15.4, *)
class NodesPageCache {
    struct Cache {
        var info: PageInfo
        var nodes: Nodes = Nodes()
        var dirty: Bool = false
    }
    var fileHandle: FileHandle
    var page = Cache(info: PageInfo(), nodes: Nodes())
    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }
    ///
    func storeCache() {
        guard page.dirty else { return }
        try? page.nodes.update(to: page.info, using: fileHandle) // TODO: What about error handling???
        page.dirty = false
    }
    ///
    func updateCache(_ pageInfo: PageInfo) {
        if pageInfo.address != page.info.address {
            storeCache()
            page.info = pageInfo
            guard let nd = try? Data.load(start: page.info.address,
                                          upTo: MemoryLayout<LANode>.size * page.info.count, using: fileHandle) else { fatalError("Failed to load cache for nodes. address:\(page.info.address), itemsCount: \(page.info.count)") }
            page.nodes = Nodes(repeating: LANode(), count: Int(page.info.count))
            page.nodes.reserveCapacity(page.info.maxCount)
            page.nodes.withUnsafeMutableBufferPointer { nd.copyBytes(to: $0) }
            page.dirty = false
        }
    }
    func node(pageInfo: PageInfo, at position: Int) -> LANode {
        updateCache(pageInfo)
        // Load the nodepage (if required) and return the the Node at position.
        return page.nodes[position]
    }
    func access(pageInfo: PageInfo, block: (inout Nodes)->Void) {
        updateCache(pageInfo)
        // Load the nodepage (if required) and return the the Node at position.
        block(&page.nodes)
        page.dirty = true
    }
    func access(node position: Int, pageInfo: PageInfo, block: (inout LANode)->Void) {
        updateCache(pageInfo)
        // Load the nodepage (if required) and return the the Node at position.
        block(&page.nodes[position])
        page.dirty = true
    }
}
/// Aggregate all the classes used for storage
@available(macOS 10.15.4, *)
struct StorageSystem {
    var fileHandle: FileHandle
    var allocator: Allocator
    var nodeCache: Int
    var pageCache: NodesPageCache
    var maxNodesPerPage: Int
}

@available(macOS 10.15.4, *)
extension StorageSystem: StorableAllocator {
    typealias Storage = NodesPage
    func createStore(capacity: Int) -> NodesPage? {
        return try? NodesPage(maxNodes: maxNodesPerPage, using: self)
    }
}

///
///  LargeArray structure:
///   Header:
///   NodesPage:
///     Info:
///     nodes: ContiguousArray<LANode>
///     --- The Nodes are stored immediately after the NodesPage.Info information ---
///
///    ... the rest is a mixture of Objects data (which is pointed to by the Nodes) and additional IndexPages
///
///  LANode:
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
    @usableFromInline
    var _header: Header
    let _maxElementsPerPage: Index
    var _storageArray: StorageArray
    var _dirty: Bool = false
    ///
    enum WalkDirection: Int {
        case Up, Down
    }
    ///
    private var totalCount: Index {
        get { _header._count }
        set { if newValue < 0 { fatalError("Invalid array count.") }
              _header._count = newValue }
    }
    private var totalUsedCount: Address {
        get { _header._totalUsedBytesCount }
        set { _header._totalUsedBytesCount = newValue }
    }
    ///
    public var totalUsedBytesCount: Address { _header._totalUsedBytesCount }
    public var totalFreeBytesCount: Int { _storage.allocator.freeByteCount }
    ///
    init(start root: Address, maxPerPage: Index, fileHandle: FileHandle, capacity: Int = Int.max) throws {
        _storage = StorageSystem(fileHandle: fileHandle,
                                 allocator: Allocator(capacity: capacity, start: root + MemoryLayout<Header>.size),
                                 nodeCache: 0,
                                 pageCache: NodesPageCache(fileHandle),
                                 maxNodesPerPage: maxPerPage)
        _rootAddress = root
        _header = Header()
        _maxElementsPerPage = maxPerPage
        _storageArray = StorageArray(maxElementsPerNode: _maxElementsPerPage, allocator: _storage)

        // Read header if possible. If error, throw
        do {
            try _load(into: &_header, from: _storage.fileHandle.read(from: _rootAddress, upToCount: MemoryLayout<Header>.size) ?? Data())
            guard _header._version <= _LA_VERSION else { throw LAErrors.InvalidFileVersion }
            // Load the Allocator free space.
            _storage.allocator = try Allocator.load(using: _storage, from: _header._freeRoot)
            
            _storageArray = try StorageArray.load(using: _storage, from: _header._storageAddress, with: _maxElementsPerPage)
            // TODO: Better verification that the data is correct
            return
        } catch {
            // Don't override the contents of the file. Continue only if storing data at the 'end' of the file.
            // TODO: Is this check good enough???
            
            // if the rootAddress is at the end of file, then we can go on, othrwise the file contains data
            // and there was an exception while reaing it.
            guard try _storage.fileHandle.seekToEnd() == _rootAddress else { throw error }
        }

//        _header._storageAddress = try _storageArray.store()
        try storeHeader()
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
            if _dirty || _header._freeRoot == Int.max {
                _storage.pageCache.storeCache()
                _header._storageAddress = try _storageArray.store()
                _header._freeRoot = try _storage.allocator.store(using: _storage)
                try storeHeader()
            }
        } catch {
            /// Hmmm. Exception in deinit. Not good.
        }

        try! _storage.fileHandle.close()
    }
    ///
    func storeHeader() throws {
//        try _storage.fileHandle.seek(toOffset: UInt64(_rootAddress))
        try _storage.fileHandle.write(_store(from: _header), at: _rootAddress)
    }
    ///
    func createNode(with data: Data) throws -> LANode {
        // Store the data and create a node to point to it.
        let overhead = MemoryLayout<LANode>.size
        guard let allocated = _storage.allocator.allocate(data.count, overhead: overhead) else {
            throw LAErrors.AllocationFailed
        }
        let node = LANode(chunk_address: allocated[0].address, used: data.count, reserved: data.count)
        try data.store(with: allocated, using: _storage.fileHandle)
        _dirty = true
        return node
    }
    /// Update the data stored in Node.
    /// This function follows the chain of Nodes in order to find all relevant chunks.
    func updateNodeData(_ node: LANode, contentsOf data: Data) throws {
        try data.update(startNodeAddress: node.chunk_address, using: _storage.fileHandle)
//        var nodeAddress = node.chunk_address
//        var n = LANode()
//        try data.withUnsafeBytes{ buffer in
//            var bufPosition = 0
//            try n.load(using: _storage.fileHandle, from: nodeAddress)
//            let usedCount = Swift.min(data.count, n.used)
//            if usedCount != n.used {
//                // update the stored node
//                n.used = usedCount
//                try n.store(using: _storage.fileHandle, at: nodeAddress)
//            }
//            try buffer.baseAddress!.store(fromOffset: bufPosition, byteCount: usedCount, using: _storage.fileHandle)
//            bufPosition += usedCount
//            nodeAddress = n.chunk_address
//        }
    }
    func getNodeData(_ node: LANode) throws -> Data {
        return try node.loadData(using: _storage.fileHandle)
    }
}

@available(macOS 10.15.4, *)
extension LargeArray {
    public func indexPagesInfo() throws -> [PageInfo] {
        var infos = [PageInfo]()
        return infos
    }
}

@available(macOS 10.15.4, *)
extension LargeArray {
}

@available(macOS 10.15.4, *)
extension LargeArray: MutableCollection, RandomAccessCollection {
    @inlinable public var startIndex: Index {
        return 0
    }
    public var endIndex: Index {
        return _storageArray.count
    }
    @inlinable public func index(after i: Index) -> Index {
        return i + 1
    }
    ///
    public subscript(position: Index) -> Data {
        get {
            do {
                return try autoreleasepool {
                    return try getNodeData(_storageArray[position])
                }
            } catch {
                fatalError("\(error.localizedDescription) - Position: \(position)")
            }
        }
        set {
            do {
                try autoreleasepool {
                    let node = _storageArray[position]
                    if node.used != newValue.count {
                        // Deallocate the existing node data - such that it is available for reuse
                        try LANode.deallocate(start: node.chunk_address, using: _storage)
//                        try _storage.allocator.deallocate(chunks: node.getChunksForData(using: _storage.fileHandle))
                        // Create a new node
                        let newNode = try createNode(with: newValue)
                        _storageArray[position] = newNode
                        _header._totalUsedBytesCount += newNode.used - node.used
                    } else {
                        try updateNodeData(node, contentsOf: newValue)
                    }
                }
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    public subscript<T: Codable>(position: Index) -> T {
        get { try! JSONDecoder().decode(T.self, from: self[position]) }
        set { self[position] = try! JSONEncoder().encode(newValue) }
    }
    ///
    public func append(_ element: Data) throws {
        try autoreleasepool {
            // update the NodesPage and store that too??? Or store the NodesPage only after a number of changes have occurred.
            try _storageArray.append(createNode(with: element))
            _header._totalUsedBytesCount += Address(element.count)
            totalCount += 1
        }
    }
    public func append<T:Codable>(_ element: T) throws {
        try self.append(JSONEncoder().encode(element))
    }
    ///
    public func remove(at position: Index) throws {
        try autoreleasepool {
            let node = _storageArray.remove(at: position) // TODO: make this return the element so the above line is not needed.
            try LANode.deallocate(start: node.chunk_address, using: _storage)
            totalCount -= 1
            _header._totalUsedBytesCount -= Address(node.used)
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
            _storageArray.insert(try createNode(with: element), at: position)
            // Find in which page the Element should be inserted.
            // If the pate is full - then split it in a half (creating two linked pages) and insert the new
            // element into one of those pages.
            totalCount += 1
            _header._totalUsedBytesCount += element.count
        }
    }
    public func insert<T: Codable>(_ element: T, at position: Index) throws {
        try self.insert(JSONEncoder().encode(element), at: position)
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
        return try JSONDecoder().decode(Allocator.self, from: Data.load(start: address, using: storage.fileHandle))
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
        guard let chunks = self.allocate(encodedAllocator.count, overhead: MemoryLayout<LANode>.size) else { throw LAErrors.AllocationFailed }
        try encodedAllocator.store(with: chunks, using: storage.fileHandle)
        return chunks[0].address
    }
}

@available(macOS 10.15.4, *)
extension StorageArray {
    ///
    static func load(using storage: StorageSystem, from address: Address, with capacity: Int) throws -> StorageArray {
        let sa = try JSONDecoder().decode(StorageArray.self, from: Data.load(start: address, using: storage.fileHandle))
        sa.allocator = storage
        return sa
    }
    ///
    func store() throws -> Address {
        guard let storage = self.allocator else { throw LAErrors.InvalidObject }
        guard let encodedArray = try? JSONEncoder().encode(self) else { throw LAErrors.AllocationFailed }
        guard let chunks = storage.allocator.allocate(encodedArray.count, overhead: MemoryLayout<LANode>.size) else { throw LAErrors.AllocationFailed }
        try encodedArray.store(with: chunks, using: storage.fileHandle)
        return chunks[0].address
    }
}
