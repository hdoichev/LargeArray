//
//  LargeArray.swift
//
//
//  Created by Hristo Doichev on 9/17/21.
//
import Foundation

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
    public init?(path: String, maxPerPage: Index = 1024) {
        if FileManager.default.fileExists(atPath: path) == false {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let fh = FileHandle(forUpdatingAtPath: path) {
            _fileHandle = fh
        } else {
            return nil
        }
        //
        _header = Header()
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
    func splitCurrentPage() throws {
        var newPage = IndexPage(address: _fileHandle.seekToEndOfFile(), maxNodes: _maxElementsPerPage)
        newPage.info._prev = _currentPage.info._address
        newPage.info._next = _currentPage.info._next
        // Update the _curPage.info._next page to point to the newPage.
        if _currentPage.info._next > 0 {
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
    func indexRelativeToCurrentPage(_ index: Index) -> Index {
        return index - _currentPage_startIndex
    }
    ///
    func isItemIndexInCurrentPage(index: Index) -> Bool {
        return _currentPage.isValidIndex(indexRelativeToCurrentPage(index))
    }
    ///
    /*mutating*/
    func loadPageFor(index: Index) throws {
        guard isItemIndexInCurrentPage(index: index) == false else { return }
        try _currentPage.store(using: _fileHandle)
        let traverseUp = (index < _currentPage_startIndex)
        while isItemIndexInCurrentPage(index: index) == false {
            if _currentPage.info._availableNodes > 0 {
                if traverseUp != (index < _currentPage_startIndex) {
                    throw LAErrors.IndexMismatch
                }
            }
//            guard traverseUp == (index < _currentPage_startIndex) && (_currentPage.info._availableNodes > 0) else { throw LAErrors.IndexMismatch }
            let addressToLoad = traverseUp ? _currentPage.info._prev : _currentPage.info._next
            guard addressToLoad != 0 else {
                throw LAErrors.CorruptedPageAddress
            }
            if traverseUp == false { _currentPage_startIndex += _currentPage.info._availableNodes }
            try _currentPage.load(using: _fileHandle, from: addressToLoad, what: .Info)
            if traverseUp == true { _currentPage_startIndex -= _currentPage.info._availableNodes }
        }
        try _currentPage.load(using: _fileHandle, from: _currentPage.info._address, what: .Nodes)
    }
    ///
    /*mutating*/
    func getNodeFor(index: Index) throws -> Node {
        try loadPageFor(index: index)
        return _currentPage.node(at: indexRelativeToCurrentPage(index))
    }
    ///
    func addNodeToFreePool(_ node: Node) {
        if _header._startFreeAddress == 0 {
//            _freeNodes = LargeArray()
        }
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
        get {
            do {
                return try autoreleasepool {
                    return try getNodeData(getNodeFor(index: position))
                }
            } catch {
                fatalError("\(error.localizedDescription) - Position: \(position)")
            }
        }
        set {
            do {
                try autoreleasepool {
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
            if _currentPage.isFull {
                try createNewCurrentPage()
            }
            
            // update the IndexPage and store that too??? Or store the IndexPage only after a number of changes have occurred.
            try _currentPage.appendNode(createNode(with: element))
//            try _currentPage.store(using: _fileHandle) // store All ... perhaps later???
            totalCount += 1
        }
    }
//    @inlinable
    public func remove(at position: Index) throws {
        try autoreleasepool {
            let node = try getNodeFor(index: position)
            _currentPage.removeNode(at: indexRelativeToCurrentPage(position))
            // TODO: Move the old node+data for reuse.
            addNodeToFreePool(node)
            
//            try _currentPage.store(using: _fileHandle) // store All ... perhaps later???
            totalCount -= 1
            adjustCurrentPageIfRequired()
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
            try loadPageFor(index: position)
            if _currentPage.isFull {
                // Split into two pages and then insert the item into one of them.
                try splitCurrentPage()
                try loadPageFor(index: position)
            }
            try _currentPage.insertNode(createNode(with: element), at: indexRelativeToCurrentPage(position))
            totalCount += 1
        }
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
