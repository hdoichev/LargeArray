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
        var dirty: Bool = false
        init(_ info: PageInfo, _ nodes: Nodes, _ dirty: Bool) {
            self.info = info
            self.nodes = nodes
            self.dirty = dirty
        }
    }
    typealias PagesCache = [Address:Cache]
    var fileHandle: FileHandle
    var pages: PagesCache = PagesCache()
//    var page = Cache(info: PageInfo(), nodes: Nodes())
    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }
    /// Store all dirty pages to storage.
    func flush() {
        pages.forEach { (k, v) in
            if v.dirty {
                try? v.nodes.update(to: v.info, using: fileHandle)
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
        pages[pageInfo.address] = Cache(pageInfo, nodes, false)
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
            $0.dirty = true
        }
//        block(&pages[pageInfo.address]!.nodes)
//        pages[pageInfo.address]!.dirty = true
    }
    func access(node position: Int, pageInfo: PageInfo, block: (inout LANode)->Void) {
        updateCache(pageInfo) {
            block(&$0.nodes[position])
            $0.dirty = true
        }
//        block(&pages[pageInfo.address]!.nodes[position])
//        pages[pageInfo.address]!.dirty = true
    }
}
