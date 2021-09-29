//
//  LargeArray.swift
//
//
//  Created by Hristo Doichev on 9/17/21.
//
import Foundation

public typealias Address = UInt64

///
protocol StorageAccessor {
    func write<T: DataProtocol>(_ data: T, at address: Address) throws
    func write<T: DataProtocol>(data: T) throws
    func read(from address: Address, upToCount: Int) throws -> Data?
    func read(bytesCount: Int) throws -> Data?
    func seek(to: Address) throws
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
    public typealias Index = Int /// TODO: Change this UInt64

    let _rootAddress: Address
    var _header: Header
    let _maxElementsPerPage: Index
    var _currentPage: IndexPage
    @usableFromInline
    var _currentPage_startIndex: Index
    ///
    var _fileHandle: FileHandle
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
    ///
    init(start root: Address, maxPerPage: Index, fileHandle: FileHandle) throws {
        _rootAddress = root
        _header = Header()
        _currentPage_startIndex = 0
        _fileHandle = fileHandle
        _maxElementsPerPage = maxPerPage

        let rootPageAddress: Address = root + Address(MemoryLayout<Header>.size)
        _currentPage = IndexPage(address: rootPageAddress, maxNodes: _maxElementsPerPage)
        _currentPage_startIndex = 0
        
        // Read header if possible. If error, throw
        do {
            try _load(into: &_header, from: _fileHandle.read(from: root, upToCount: MemoryLayout<Header>.size) ?? Data())
            try _currentPage.load(using: _fileHandle, from: rootPageAddress)
            guard _header._startPageAddress == _currentPage.info._address else { throw LAErrors.CorruptedPageAddress }
            // TODO: Better verification that the data is correct
            return
        } catch {
            // If the file had data and we ended up here then we bailout.
            // Don't override the contents of the file. Continue only if storing data at the 'end' of the file.
            // TODO: Is this check good enough???
            guard try _fileHandle.seekToEnd() == root else { throw error }
            _header._startPageAddress = _currentPage.info._address
        }
        // if we read this from storage and the version is wrong - throw
        // TODO: Better validation???
        guard _header._version <= _LA_VERSION else { throw LAErrors.InvalidFileVersion }
        try storeHeader()
        try _currentPage.store(using: _fileHandle)
    }
    ///
    public convenience init?(path: String, maxPerPage: Index = 1024) {
        if FileManager.default.fileExists(atPath: path) == false {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let fh = FileHandle(forUpdatingAtPath: path) {
            do {
                try self.init(start: 0, maxPerPage: maxPerPage, fileHandle: fh)
            } catch {
                return nil
            }
        } else {
            return nil
        }
    }
    deinit {
        do {
            try storeHeader()
            try _currentPage.store(using: _fileHandle)
        } catch {
            /// Hmmm. Exception in deinit. Not good.
        }
    }
    ///
    func storeHeader() throws {
        try _fileHandle.seek(toOffset: _rootAddress)
        try _fileHandle.write(contentsOf: _store(from: _header))
    }
    ///
    func createNode(with data: Data) throws -> Node {
        // Store the data and create a node to point to it.
        let node = try Node(address: _fileHandle.seekToEnd(), used: data.count, reserved: data.count)
        try storeNodeData(node, contentsOf: data)
//        try _fileHandle.write(contentsOf: data)
        return node
    }
    ///
    func storeNodeData(_ node: Node, contentsOf data: Data) throws {
        try _fileHandle.write(data, at: node.address)
    }
    func getNodeData(_ node: Node) throws -> Data {
        guard let nodeData = try _fileHandle.read(from: node.address, upToCount: node.used) else { throw LAErrors.ErrorReadingData }
        return nodeData
    }
    ///
    /*mutating*/
    func createNewCurrentPage() throws {
        var newPage = IndexPage(address: _fileHandle.seekToEndOfFile(), maxNodes: _maxElementsPerPage)
        newPage.info._prev = _currentPage.info._address
        // First: Store the new page, thus when the current_page.next is updated it will point to a properly stored data.
        try newPage.store(using: _fileHandle)
        // Second: Store the updated NexPageAddress of the current page.
        _currentPage.info._next = newPage.info._address
        try _currentPage.store(using: _fileHandle)
        // Last: Set the new page as the current page and update related properties.
        _currentPage_startIndex = _currentPage_startIndex + Index(_currentPage.info._availableNodes)
        _currentPage = newPage
    }
    ///
    func provideSpaceInCurrentPage() throws {
        if _currentPage.info._next != Address.invalid {
            // move some of the nodes from the current page to the next, if that is possible.
            // Otherwise create a new page and split the nodes between the current and the new page.
            var nextPage = IndexPage(address: _currentPage.info._next, maxNodes: _maxElementsPerPage)
            try nextPage.load(using: _fileHandle, from: _currentPage.info._next, what: .Info)
            if nextPage.info._availableNodes < nextPage.info._maxNodes/2 {
                try nextPage.load(using: _fileHandle, from: nextPage.info._address, what: .Nodes)
                let elementsCount = nextPage.info._maxNodes/2
                try _currentPage.moveNodes((_currentPage.info._availableNodes-elementsCount..<_currentPage.info._availableNodes), into: &nextPage)
                try nextPage.store(using: _fileHandle)
                try _currentPage.store(using: _fileHandle)
            }
        }
        if _currentPage.isFull {
            try splitCurrentPage()
        }
    }
    ///
    func splitCurrentPage() throws {
        var newPage = IndexPage(address: _fileHandle.seekToEndOfFile(), maxNodes: _maxElementsPerPage)
        newPage.info._prev = _currentPage.info._address
        newPage.info._next = _currentPage.info._next
        // Update the _curPage.info._next page to point to the newPage.
        if _currentPage.info._next != Address.invalid {
            var pageToUpdate = IndexPage(address: _currentPage.info._next, maxNodes: _maxElementsPerPage)
            try pageToUpdate.load(using: _fileHandle, from: _currentPage.info._next, what: .Info)
            pageToUpdate.info._prev = newPage.info._address
            try pageToUpdate.store(using: _fileHandle)
        }
        // now, link the current page with the split (new) page
        _currentPage.info._next = newPage.info._address
        // Move half of the nodes to the new page and save it
        try _currentPage.moveNodes(_currentPage.info._availableNodes/2..<_currentPage.info._availableNodes, into: &newPage)
        try newPage.store(using: _fileHandle)
        try _currentPage.store(using: _fileHandle)
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
        var range = (startPos...startPos + _currentPage.info._availableNodes)
        guard range.contains(position) == false else { return  }
        try _currentPage.store(using: _fileHandle)
        let direction = position > range.upperBound ? WalkDirection.Down: WalkDirection.Up
        while range.contains(position) == false {
            let address = (direction == .Up) ? _currentPage.info._prev : _currentPage.info._next
            guard address != Address.invalid else { throw LAErrors.PositionOutOfRange }
            if direction == .Down { startPos += _currentPage.info._availableNodes }
            try _currentPage.load(using: _fileHandle, from: address)
            if direction == .Up { startPos -= _currentPage.info._availableNodes }
            range = (startPos...startPos+_currentPage.info._availableNodes)
        }
        _currentPage_startIndex = startPos
        try _currentPage.load(using: _fileHandle, from: _currentPage.info._address, what: .Nodes)
    }
    ///
    func findPageForAccess(position: Index) throws {
        var startPos = _currentPage_startIndex
        var range = (startPos..<startPos + _currentPage.info._availableNodes)
        guard range.contains(position) == false else { return }
        try _currentPage.store(using: _fileHandle)
        let direction = position < range.upperBound ? WalkDirection.Up: WalkDirection.Down
        while range.contains(position) == false {
            let address = (direction == .Up) ? _currentPage.info._prev : _currentPage.info._next
            guard address != Address.invalid else { throw LAErrors.PositionOutOfRange }
            if direction == .Down { startPos += _currentPage.info._availableNodes }
            try _currentPage.load(using: _fileHandle, from: address, what: .Info)
            if direction == .Up { startPos -= _currentPage.info._availableNodes }
            range = (startPos..<startPos+_currentPage.info._availableNodes)
        }
        _currentPage_startIndex = startPos
        try _currentPage.load(using: _fileHandle, from: _currentPage.info._address, what: .Nodes)
    }
    ///
    /*mutating*/
    func getNodeFor(position: Index) throws -> Node {
        try findPageForAccess(position: position)
        return _currentPage.node(at: indexRelativeToCurrentPage(position))
    }
    ///
    func addNodeToFreePool(_ node: Node) throws {
    }
    /// When nodes are removed the current page can become empty and perhaps a page with some data should be loaded. Perhaps not?!?!?
    func adjustCurrentPageIfRequired() throws {
        if _header._count  == 0 {
            try _currentPage.store(using: _fileHandle)
            guard _currentPage_startIndex == 0 else { throw LAErrors.CorruptedStartIndex}
            try _currentPage.load(using: _fileHandle, from: _header._startPageAddress)
            return
        }
        if _currentPage.info._availableNodes == 0 {
            try _currentPage.store(using: _fileHandle)

            var loadNodes = false
            let initialNextAddress = _currentPage.info._address
            // Go up
            while _currentPage.info._availableNodes == 0 {
                guard _currentPage.info._prev != Address.invalid else { break }
                try _currentPage.load(using: _fileHandle, from: _currentPage.info._prev, what: .Info)
                _currentPage_startIndex -= _currentPage.info._availableNodes
                loadNodes = true
            }
            if _currentPage.info._availableNodes == 0 && initialNextAddress != Address.invalid{
                try _currentPage.load(using: _fileHandle, from: initialNextAddress, what: .Info)
                while _currentPage.info._availableNodes == 0 {
                    guard _currentPage.info._next != Address.invalid else { break }
                    try _currentPage.load(using: _fileHandle, from: _currentPage.info._next, what: .Info)
                    loadNodes = true
                }
            }
            guard _currentPage.info._availableNodes > 0 else { throw LAErrors.CorruptedItemsCount }
            if loadNodes {
                try _currentPage.load(using: _fileHandle, from: _currentPage.info._address, what: .Nodes)
            }
        }
    }
}

@available(macOS 10.15.4, *)
extension LargeArray {
    public func indexPagesInfo() throws -> [PageInfo] {
        try _currentPage.store(using: _fileHandle) // ensure it is stored.
        var infos = [PageInfo]()
        var page = try PageInfo.load(from: _fileHandle, at: _header._startPageAddress)
        page._next = _header._startPageAddress // bootstrap the first page to start loading
        while page._next != Address.invalid {
            page = try PageInfo.load(from: _fileHandle, at: page._next)
            infos.append(page)
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
                    var node = try getNodeFor(position: position)
                    if node.reserved < newValue.count {
                        // TODO: Move the old node+data for reuse.
                        // Create a new node
                        let newNode = try createNode(with: newValue)
                        try addNodeToFreePool(node)
                        _currentPage.updateNode(at: indexRelativeToCurrentPage(position), node: newNode)
                    } else {
                        node.used = newValue.count
                        _currentPage.updateNode(at: indexRelativeToCurrentPage(position), node: node)
                        try storeNodeData(node, contentsOf: newValue)
                    }
                }
//                try _currentPage.store(using: _fileHandle) // Store all ... perhaps later>???
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
//    @inlinable
    public /*mutating*/ func append(_ element: Data) throws {
        try autoreleasepool {
            // update the IndexPage and store that too??? Or store the IndexPage only after a number of changes have occurred.
//            try _currentPage.appendNode(createNode(with: element))
            try appendNode(createNode(with: element))
//            try _currentPage.store(using: _fileHandle) // store All ... perhaps later???
        }
    }
//    @inlinable
    public func remove(at position: Index) throws {
        try autoreleasepool {
            let node = try getNodeFor(position: position)
            _currentPage.removeNode(at: indexRelativeToCurrentPage(position))
            // TODO: Move the old node+data for reuse.
            try addNodeToFreePool(node)
            
//            try _currentPage.store(using: _fileHandle) // store All ... perhaps later???
            totalCount -= 1
            totalUsedCount -= Address(node.used)
            try adjustCurrentPageIfRequired()
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
            totalUsedCount += Address(element.count)
        }
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
