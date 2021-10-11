//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/27/21.
//

import Foundation
import Allocator

///
struct Node: Codable {
    var chunk_address: Address = Address.invalid
    var used: Int = 0
    var reserved: Int = 0
}

extension Node {
    func dump() {
        print("ChunksAddress = \(self.chunk_address), Used = \(self.used), Reserved = \(self.reserved)")
    }
}

extension Node: Equatable {
    static func == (lhs: Node, rhs: Node) -> Bool {
        return (lhs.chunk_address == rhs.chunk_address &&
                lhs.used == rhs.used &&
                lhs.reserved == rhs.reserved)
    }
}

@available(macOS 10.15.4, *)
extension Node {
    mutating func load(using fileHandle: FileHandle, from address: Address) throws {
        guard let nodeData = try fileHandle.read(from: address, upToCount: MemoryLayout<Node>.size) else { throw LAErrors.ErrorReadingData }
        try _load(into: &self, from: nodeData)
    }
    func store(using fileHandle: FileHandle, at address: Address) throws {
        try fileHandle.write(_store(from: self), at: address)
    }
    func loadData(using fileHandle: FileHandle) throws -> (Data, Allocator.Chunks) {
        return try Data.loadFromNodes(start: self.chunk_address, byteCount: self.used, using: fileHandle)
    }
    func getChunksForData(using fileHandle: FileHandle) throws -> Allocator.Chunks {
        var chunks = Allocator.Chunks()
        var n = Node()
        var loadAddress = self.chunk_address
        while loadAddress != Address.max {
            try n.load(using: fileHandle, from: loadAddress)
            chunks.append(Allocator.Chunk(address: loadAddress, count: n.reserved))
            loadAddress = n.chunk_address
        }
        return chunks
    }
}

extension Node: CustomStringConvertible {
    var description: String {
        "Node(chunks_address: \(chunk_address), used: \(used), reserved: \(reserved))"
    }
}

@available(macOS 10.15.4, *)
extension Data {
    func storeWithNodes(chunks: Allocator.Chunks, using fileHandle: FileHandle) throws {
        guard ((self.count + chunks.count * MemoryLayout<Node>.size) <= chunks.allocatedCount) else { throw LAErrors.InvlaidAllocatedSize }
        try self.withUnsafeBytes { buffer in
            var bufPosition = 0
            let overhead = MemoryLayout<Node>.size
            for i in 0..<chunks.count {
                // Store info about this chunk
                let nextChunkAddress = (i+1 < chunks.count) ? chunks[i+1].address: Int.max
                let usedCount = Swift.min(self.count - bufPosition, chunks[i].count - overhead)
                guard usedCount > 0 else { throw LAErrors.InvlaidAllocatedSize }
                try Node(chunk_address: nextChunkAddress, used: usedCount, reserved: chunks[i].count)
                    .store(using: fileHandle, at: chunks[i].address)
                // This is a nasty case from const to mutable. It is done only to avoid copying data when saving to file.
                try buffer.baseAddress!.store(fromOffset: bufPosition, byteCount: usedCount, using: fileHandle)
                bufPosition += usedCount
            }
        }
    }
    static func loadFromNodes(start address: Address, byteCount: Int, using fileHandle: FileHandle) throws -> (Data,Allocator.Chunks) {
//        var data = Data(repeating: 0, count: byteCount)
        var data = Data(capacity: byteCount)
        var chunks = Allocator.Chunks()
        var n = Node()
        var loadAddress = address
        let overhead = MemoryLayout<Node>.size
//        try data.withUnsafeMutableBytes { buffer in
        // The Data is guaranteed to be in this form:
        //  Node
        //  Data
        // Where the Node.used is the size of the data
        while data.count != byteCount {
            guard loadAddress != Address.max else { throw LAErrors.InvlaidNodeAddress }
            try n.load(using: fileHandle, from: loadAddress)
            let loadCount = n.used - overhead
            guard loadCount > 0 else { throw LAErrors.InvlaidAllocatedSize }
            guard let chunkData = try fileHandle.read(bytesCount: loadCount) else { throw LAErrors.ErrorReadingData }
            chunks.append(Allocator.Chunk(address: loadAddress, count: n.reserved))
            data += chunkData
            loadAddress = n.chunk_address
        }
//        }
        return (data, chunks)
    }
}
