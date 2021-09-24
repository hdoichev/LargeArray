//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/24/21.
//

import Foundation

func _load<T>(into binaryObject: inout T, from data: Data) throws {
    guard MemoryLayout<T>.size <= data.count else { throw LAErrors.InvalidReadBufferSize }
    try data.withUnsafeBytes{ buffer in
        let in_buffer = buffer.bindMemory(to: T.self)
        guard in_buffer.count >= 1 else { throw LAErrors.InvalidReadBufferSize }
        binaryObject.self = in_buffer[0]
    }
}
func _store<T>(from binaryObject: T) throws -> Data {
    var data = Data(count: MemoryLayout<T>.size)
    data.withUnsafeMutableBytes { buffer in
        let out_buffer = buffer.bindMemory(to: T.self)
        out_buffer[0] = binaryObject
    }
    return data
}

