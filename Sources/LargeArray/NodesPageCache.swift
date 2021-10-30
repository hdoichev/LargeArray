//
//  File.swift
//  
//
//  Created by Hristo Doichev on 10/27/21.
//

import Foundation

///
@available(macOS 10.15.4, *)
class NodesPageCache {
    class Cache {
        var info: PageInfo = PageInfo()
        var nodes: Nodes = Nodes()
        var changes: Int = 0
        init(_ info: PageInfo, _ nodes: Nodes, _ changes: Int = 0) {
            self.info = info
            self.nodes = nodes
            self.changes = changes
        }
    }
    typealias PagesCache = [Address:Cache]
    var fileHandle: FileHandle
    var pages: PagesCache = PagesCache()
    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }
    /// Store all dirty pages to storage.
    public func flush() {
        pages.forEach { (k, v) in
            if v.changes > 0 {
                try? v.nodes.update(to: v.info, using: fileHandle)
                v.changes = 0
            }
        }
    }
    /// Remove the cached
    func purge(_ address: Address) {
        pages.removeValue(forKey: address)
    }
    ///
    func updateCache(_ pageInfo: PageInfo, block: (inout Cache)->Void) {
        guard nil == pages[pageInfo.address] else { block(&(pages[pageInfo.address]!)); return}
        guard let nd = try? Data.load(start: pageInfo.address,
                                      upTo: MemoryLayout<LANode>.size * pageInfo.count, using: fileHandle) else { fatalError("Failed to load cache for nodes. address:\(pageInfo.address), itemsCount: \(pageInfo.count)") }
        var nodes = Nodes(repeating: LANode(), count: Int(pageInfo.count))
        nodes.reserveCapacity(pageInfo.maxCount)
        nodes.withUnsafeMutableBufferPointer { nd.copyBytes(to: $0) }
        pages[pageInfo.address] = Cache(pageInfo, nodes)
        block(&(pages[pageInfo.address]!))
//        if pageInfo.address != page.info.address {
//            storeCache()
//            page.info = pageInfo
//            guard let nd = try? Data.load(start: page.info.address,
//                                          upTo: MemoryLayout<LANode>.size * page.info.count, using: fileHandle) else { fatalError("Failed to load cache for nodes. address:\(page.info.address), itemsCount: \(page.info.count)") }
//            page.nodes = Nodes(repeating: LANode(), count: Int(page.info.count))
//            page.nodes.reserveCapacity(page.info.maxCount)
//            page.nodes.withUnsafeMutableBufferPointer { nd.copyBytes(to: $0) }
//            page.dirty = false
//        }
    }
    func node(pageInfo: PageInfo, at position: Int) -> LANode {
        var n = LANode()
        updateCache(pageInfo) { n = $0.nodes[position] }
        return n
//        return pages[pageInfo.address]!.nodes[position]
    }
    func access(pageInfo: PageInfo, block: (inout Nodes)->Void) {
        updateCache(pageInfo) {
            block(&$0.nodes)
            $0.changes += 1
            if $0.changes > 15 {
                try? $0.nodes.update(to: $0.info, using: fileHandle)
                $0.changes = 0
            }
        }
//        block(&pages[pageInfo.address]!.nodes)
//        pages[pageInfo.address]!.dirty = true
    }
    func access(node position: Int, pageInfo: PageInfo, block: (inout LANode)->Void) {
        updateCache(pageInfo) {
            block(&$0.nodes[position])
            $0.changes += 1
            if $0.changes > 15 {
                try? $0.nodes.update(to: $0.info, using: fileHandle)
                $0.changes = 0
            }
        }
//        block(&pages[pageInfo.address]!.nodes[position])
//        pages[pageInfo.address]!.dirty = true
    }
}
