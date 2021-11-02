//
//  LANode.swift
//  
//
//  Created by Hristo Doichev on 9/27/21.
//

import Foundation
import Allocator

///
struct LANode: Codable {
    var chunk_address: Address = Address.invalid
    var used: Int = 0
    var reserved: Int = 0
}

extension LANode: CustomStringConvertible {
    var description: String {
        String("ChunksAddress = \(self.chunk_address), Used = \(self.used), Reserved = \(self.reserved)")
    }
}

extension LANode: Equatable {
    static func == (lhs: LANode, rhs: LANode) -> Bool {
        return (lhs.chunk_address == rhs.chunk_address &&
                lhs.used == rhs.used &&
                lhs.reserved == rhs.reserved)
    }
}

@available(macOS 10.15.4, *)
extension LANode {
    mutating func load(using fileHandle: FileHandle, from address: Address) throws {
        guard let nodeData = try fileHandle.read(from: address, upToCount: MemoryLayout<LANode>.size) else { throw LAErrors.ErrorReadingData }
        try _load(into: &self, from: nodeData)
    }
    func store(using fileHandle: FileHandle, at address: Address) throws {
        try fileHandle.write(_store(from: self), at: address)
    }
    func loadData(using fileHandle: FileHandle) throws -> Data {
        return try Data.load(start: self.chunk_address, upTo: self.used, using: fileHandle)
    }
    func getChunksForData(using fileHandle: FileHandle) throws -> Allocator.Chunks {
        var chunks = Allocator.Chunks()
        var n = LANode()
        var loadAddress = self.chunk_address
        while loadAddress != Address.invalid {
            try n.load(using: fileHandle, from: loadAddress)
            chunks.append(Allocator.Chunk(address: loadAddress, count: n.reserved))
            loadAddress = n.chunk_address
        }
        return chunks
    }
    /// Read the Chunks from storage and deallocate them using the allocator
    static func deallocate(start address: Address, using storage: StorageSystem) throws {
        var n = LANode()
        var loadAddress = address
        while loadAddress != Address.invalid {
            try n.load(using: storage.fileHandle, from: loadAddress)
            storage.allocator.deallocate(Allocator.Chunk(address: loadAddress, count: n.reserved))
            // TODO: Invalidate the stored chunk???
            //   Overwrite the address with Int.max
            loadAddress = n.chunk_address
        }
    }
}

@available(macOS 10.15.4, *)
extension Data {
    /// Update the nodes used data starting at startNodeAddress
    func update(startNodeAddress: Address, using fileHandle: FileHandle) throws {
        var updateAddress = startNodeAddress
        try self.withUnsafeBytes { buffer in
            let overhead = MemoryLayout<LANode>.size
            var n = LANode()
            var bufPosition = 0
            var remaining = buffer.count
            while updateAddress != Int.max && remaining > 0 {
                try n.load(using: fileHandle, from: updateAddress)
                guard n.used != 0 else { throw LAErrors.InvalidAllocatedSize }
                var useCount = Swift.min(remaining, n.reserved - overhead)
                remaining -= useCount
                if remaining == 0 {
                    // negative marks the end of this update. Use negative value when loading Data to determine the last chunk in the chain
                    useCount = -useCount
                }
                if useCount != n.used {
                    n.used = useCount
                    try n.store(using: fileHandle, at: updateAddress)
                }
                try buffer.baseAddress!.store(fromOffset: bufPosition, byteCount: Swift.abs(n.used), using: fileHandle)
                bufPosition += n.used
                updateAddress = n.chunk_address
            }
        }
    }
    func store(with chunks: Allocator.Chunks, using fileHandle: FileHandle) throws {
        guard ((self.count + chunks.count * MemoryLayout<LANode>.size) <= chunks.allocatedCount) else { throw LAErrors.InvalidAllocatedSize }
        try self.withUnsafeBytes { buffer in
            var bufPosition = 0
            var remaining = buffer.count
            let overhead = MemoryLayout<LANode>.size
            for i in 0..<chunks.count {
                // Store info about this chunk
                let nextChunkAddress = (i+1 < chunks.count) ? chunks[i+1].address: Int.max
                if remaining > 0 {
                    var usedCount = Swift.min(remaining, chunks[i].count - overhead)
                    remaining -= usedCount
                    guard usedCount > 0 else { throw LAErrors.InvalidAllocatedSize }
                    if remaining == 0 {
                        usedCount = -usedCount
                    }
                    try LANode(chunk_address: nextChunkAddress,
                               used: usedCount, reserved: chunks[i].count)
                        .store(using: fileHandle, at: chunks[i].address)
                    // This is a nasty case from const to mutable. It is done only to avoid copying data when saving to file.
                    try buffer.baseAddress!.store(fromOffset: bufPosition, byteCount: Swift.abs(usedCount), using: fileHandle)
                    bufPosition += usedCount
                } else {
                    // Empty node.
                    try LANode(chunk_address: nextChunkAddress,
                               used: 0, reserved: chunks[i].count)
                        .store(using: fileHandle, at: chunks[i].address)

                }
            }
        }
    }
    static func load(start address: Address, upTo byteCount: Int, using fileHandle: FileHandle) throws -> Data {
        guard byteCount > 0 else { return Data() }
//        var data = Data(repeating: 0, count: byteCount)
        var data = Data(capacity: byteCount)
        var n = LANode()
        var loadAddress = address
//        try data.withUnsafeMutableBytes { buffer in
        // The Data is guaranteed to be in this form:
        //  LANode + Data
        // Where the LANode.used is the size of the Data
        while loadAddress != Address.invalid && data.count < byteCount {
            try n.load(using: fileHandle, from: loadAddress)
            if n.used < 0 {
                guard Swift.abs(n.used) + data.count == byteCount else { throw LAErrors.InvalidReadBufferSize }
                n.used = -n.used
            }
            guard n.used > 0 else { throw LAErrors.InvalidAllocatedSize }
            let toRead = Swift.min(n.used, byteCount - data.count)
            guard let chunkData = try fileHandle.read(bytesCount: toRead) else { throw LAErrors.ErrorReadingData }
            data += chunkData
            loadAddress = n.chunk_address
        }
//        }
        return data
    }
    static func load(start address: Address, using fileHandle: FileHandle) throws -> Data {
        //        var data = Data(repeating: 0, count: byteCount)
        var data = Data()
        var n = LANode()
        var loadAddress = address
        // The Data is guaranteed to be in this form:
        //  LANode + Data
        // Where the LANode.used is the size of the data
        while loadAddress != Address.invalid {
            try n.load(using: fileHandle, from: loadAddress)
            guard n.used != 0 else { throw LAErrors.InvalidAllocatedSize }
            guard let chunkData = try fileHandle.read(bytesCount: Swift.abs(n.used)) else { throw LAErrors.ErrorReadingData }
            data += chunkData
            loadAddress = n.chunk_address
            // if this is the last chunk ... the loading is done
            if n.used < 0 {
                break
            }
        }
        return data
    }
}
