//
//  File.swift
//  
//
//  Created by Hristo Doichev on 10/27/21.
//

import Foundation
import Heap
/// Keep a set of NodePages in memory.
/// When the cash is full then reuse the oldest Cache that is available.
/// Reduce allocations of NodesCache pages and keep the number of memory under control.
@available(macOS 10.15.4, *)
class NodesPageCache {
    class Cache: Comparable, IndexAssignable {
        var assignedIndex: Int {
            get { return _assignedIndex }
            set { _assignedIndex = newValue }
        }
        
        // MARK: Heap compare
        static func < (lhs: NodesPageCache.Cache, rhs: NodesPageCache.Cache) -> Bool {
            return lhs._cacheAge < rhs._cacheAge
        }
        // MARK: Heap compare
        static func == (lhs: NodesPageCache.Cache, rhs: NodesPageCache.Cache) -> Bool {
            lhs._cacheAge == rhs._cacheAge
        }
        
        var _cacheAge: Int = 0
        var _assignedIndex: Int = -1
        var address: Address
        var nodes: Nodes = Nodes()
        var changes: Int = 0
        //
        init(_ address: Address, _ nodes: Nodes, _ changes: Int = 0) {
            self.address = address
            self.nodes = nodes
            self.changes = changes
        }
    }
    //
    typealias PagesCache = [Address:Cache]
    typealias PageHeapUsage = DHeap<Cache> // keep track of which pages can be discarded
    
    var fileHandle: FileHandle
    var pages: PagesCache = PagesCache()
    var heap: PageHeapUsage = PageHeapUsage(<)
    var maxHeap: Int
    var _cacheCounter: Int = 0
    var _cacheMiss: Int = 0
    ///
    init(_ fileHandle: FileHandle, heapSize: Int = 8*1024) {
        self.fileHandle = fileHandle
        self.maxHeap = heapSize
        for _ in 0..<self.maxHeap {
            heap.push(Cache(Address.invalid, Nodes()))
        }
    }
    ///
    deinit {
//        print("-- Cache misses: ", _cacheMiss)
    }
    /// Store all dirty pages to storage.
    public func flush() {
        pages.forEach { (k, v) in persistCache(v) }
    }
    func persistCache(_ cache: Cache) {
        if cache.changes > 0 {
            do {
                try cache.nodes.update(to: cache.address, using: fileHandle)
            } catch {
                fatalError("Unable to store Cache")
            }
            cache.changes = 0
        }
    }
    /// Remove the cached
    func purge(_ address: Address) {
        if let c = pages.removeValue(forKey: address) {
            c._cacheAge = 0
            c.changes = 0
            c.address = Address.invalid
            // Bring the new page to the top of the heap.
            heap.heapifySiftDown()
        }
    }
    var cacheCounter: Int {
        get { _cacheCounter }
        set {
            if newValue >= Int.max - 1 {
                _cacheCounter = 0
                heap.accessStorage { heapStorage in
                    for i in 0..<heapStorage.count {
                        _cacheCounter += 1
                        if heapStorage[i]._cacheAge > 0 {
                            heapStorage[i]._cacheAge = _cacheCounter
                        }
                    }
                }
            } else {
                _cacheCounter = newValue
            }
        }
    }
    ///
    func getOldestCache() -> Cache {
        guard let c = heap.top else { fatalError("Unable to allocate Cache") }
        return c
    }
    ///
    func updateCache(_ pageInfo: PageInfo, block: (inout Cache)->Void) {
        cacheCounter += 1
        let page = pages[pageInfo.address]
        guard nil == page else {
            guard var page = page else { return }
            block(&page)
            /// Have to update the cache age in the Heap.
            heap.update(at: page.assignedIndex) {
                $0._cacheAge = cacheCounter
            }
            return
        }
        // We dont have this page in the cache.
        // Get the oldest used page, persist it and then use it to store data for the new address.
        _cacheMiss += 1
        guard let nd = try? Data.load(start: pageInfo.address,
                                      upTo: MemoryLayout<LANode>.size * pageInfo.count, using: fileHandle) else { fatalError("Failed to load cache for nodes. address:\(pageInfo.address), itemsCount: \(pageInfo.count)") }
        var cache = getOldestCache()
        if cache.address != .invalid {
            persistCache(cache)
            pages.removeValue(forKey: cache.address) // oldest page is removed from the cache
            cache.nodes.removeAll(keepingCapacity: true)
        }
        for _ in 0..<pageInfo.count { cache.nodes.append(LANode()) }
        _ = cache.nodes.withUnsafeMutableBufferPointer { nd.copyBytes(to: $0) } // nodes page is updated
        cache.address = pageInfo.address // page info is updated
        cache._cacheAge = _cacheCounter
        pages[pageInfo.address] = cache // the updated cache is added back in
        block(&cache)
        heap.siftDown()
    }
    func node(pageInfo: PageInfo, at position: Int) -> LANode {
        var n = LANode()
        updateCache(pageInfo) {
            n = $0.nodes[position]
            $0._cacheAge = _cacheCounter
        }
        return n
    }
    func access(pageInfo: PageInfo, block: (inout Nodes)->Void) {
        updateCache(pageInfo) {
            block(&$0.nodes)
            $0._cacheAge = _cacheCounter
            $0.changes += 1
        }
    }
    func access(node position: Int, pageInfo: PageInfo, block: (inout LANode)->Void) {
        updateCache(pageInfo) {
            block(&$0.nodes[position])
            $0._cacheAge = _cacheCounter
            $0.changes += 1
        }
    }
}
