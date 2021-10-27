//
//  NodesPage.swift
//  
//
//  Created by Hristo Doichev on 9/24/21.
//

import Foundation
import Allocator
import HArray

typealias Nodes = ContiguousArray<LANode>
///
@available(macOS 10.15.4, *)
public struct PageInfo: Codable {
    var address: Address = Address.invalid
    var count: LargeArray.Index = 0
    var maxCount: LargeArray.Index = 0
}
///
@available(macOS 10.15.4, *)
class NodesPage: Codable {
    private var _info: PageInfo
    private var _storage: StorageSystem?
    //
    var info: PageInfo {
        get { return _info }
        set {
            if _info != newValue {
                _info = newValue
            }
        }
    }
    ///
    enum CodingKeys: String, CodingKey {
        case i
    }
    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        _info = try values.decode(PageInfo.self, forKey: .i)
        _storage = nil
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_info, forKey: .i)
    }
    ///
    init(maxNodes: LargeArray.Index, using storage: StorageSystem) throws {
        _storage = storage
        guard let chunks = _storage!.allocator.allocate(maxNodes * MemoryLayout<LANode>.size, overhead: MemoryLayout<LANode>.size) else { throw LAErrors.AllocationFailed }
        _info = PageInfo(address: chunks[0].address, count: 0, maxCount: maxNodes)
        
        let d = Data(repeating: 0, count: maxNodes * MemoryLayout<LANode>.size)
        try d.store(with: chunks, using: _storage!.fileHandle)
    }
    /// Deallocate the page and remove it from the prev/next chain,
    /// by linking the prev and next to one another
    ///
    func deallocate() throws {
        try LANode.deallocate(start: _info.address, using: _storage!)
        // remove this page from the prev and next pages.
        _info = PageInfo()
    }
}

@available(macOS 10.15.4, *)
extension NodesPage: Storable {
    typealias StorageAllocator = StorageSystem
    typealias Index = Int
    typealias Element = LANode
    var startIndex: Int { 0 }
    var endIndex: Int { _info.count }
    var capacity: Int {
        self._info.maxCount
    }
    var count: Int { _info.count }
    func index(after i: Int) -> Int { i + 1 }
    
    var allocator: StorageAllocator? {
        get { _storage }
        set(newValue) { _storage = newValue! }
    }
    
    func replace(with elements: [Element]) {
        guard elements.count <= _info.maxCount else { fatalError("Invalid number of elements") }
        _storage!.pageCache.access(pageInfo: _info) {
            $0 = Nodes(elements)
        }
        _info.count = elements.count
    }
    
    func append(_ elements: [Element]) {
        guard _info.count + elements.count <= _info.maxCount else { fatalError("Appending to full node") }
        _storage!.pageCache.access(pageInfo: _info) {
            $0 += elements
        }
        _info.count += elements.count
    }
    
    func append(_ element: Element) {
        guard _info.count <= _info.maxCount else { fatalError("Appending to full node") }
        _storage!.pageCache.access(pageInfo: _info) {
            $0.append(element)
        }
        _info.count += 1
    }
    
    func insert(_ element: Element, at position: Int) {
        guard _info.count <= _info.maxCount else { fatalError("Inserting into full node") }
        _storage!.pageCache.access(pageInfo: _info) {
            $0.insert(element, at: position)
        }
        _info.count += 1
    }
    
    func remove(at position: Int) -> Element {
        var r: Element = LANode()
        _storage!.pageCache.access(pageInfo: _info) {
            r = $0.remove(at: position)
        }
        _info.count -= 1
        return r
    }
    subscript(position: Int) -> LANode {
        get {
            _storage!.pageCache.node(pageInfo: _info, at: position)
        }
        set(newValue) {
            _storage!.pageCache.access(pageInfo: _info) { $0[position] = newValue }
        }
    }
    func notInUse() {
        try? deallocate()
    }
}

@available(macOS 10.15.4, *)
extension NodesPage: CustomStringConvertible {
    var description: String {
        return """
        Page(AvailableNodes: \(_info.count)
        """
    }
}

@available(macOS 10.15.4, *)
extension PageInfo: Equatable {
}

extension Address {
    static var invalid: Address { return Address.max }
}

@available(macOS 10.15.4, *)
extension Nodes {
    func store(to info: PageInfo, with chunks: Allocator.Chunks, using fileHandle: FileHandle) throws {
        var nodesData = Data(repeating: 0, count: MemoryLayout<LANode>.size * Int(info.maxCount))
        nodesData.withUnsafeMutableBytes { dest in self.withUnsafeBytes { source in dest.copyBytes(from: source) }}
        try nodesData.store(with: chunks, using: fileHandle) // TODO: What about error handling???
    }
    func update(to info: PageInfo, using fileHandle: FileHandle) throws {
        var nodesData = Data(repeating: 0, count: MemoryLayout<LANode>.size * Int(info.maxCount))
        nodesData.withUnsafeMutableBytes { dest in self.withUnsafeBytes { source in dest.copyBytes(from: source) }}
        try nodesData.update(startNodeAddress: info.address, using: fileHandle) // TODO: What about error handling???
    }
}
