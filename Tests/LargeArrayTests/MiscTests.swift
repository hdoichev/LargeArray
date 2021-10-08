//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/29/21.
//

import XCTest
import Compression
@testable import LargeArray

@available(macOS 10.15.4, *)
final class MiscTests: XCTestCase {
    let elements_count = 10

    ///
    func testStoreArrayToData() {
        var nodes = ContiguousArray<Node>(repeating: Node(address: 0, used: 0, reserved: 0), count: elements_count)
        let nodesDataSize = MemoryLayout<Node>.size * Int(elements_count)
        var nodesData = Data(count: nodesDataSize)
        for i in 0..<nodes.count {
            nodes[i].address = Address(i)
            nodes[i].used = i
            nodes[i].reserved = i
        }
        print("nodes.count = \(nodes.count)")
        print("nodesData.count = \(nodesData.count) (\(nodesDataSize))")
        
        nodesData.withUnsafeMutableBytes { dest in
            nodes.withUnsafeBytes { source in
                dest.copyBytes(from: source)
            }
        }
        nodesData.withUnsafeBytes { bytes in
            let raw_nodes = bytes.bindMemory(to: Node.self)
        }
        // now init the arrat from the data
        var loadedNodes = ContiguousArray<Node>(repeating: Node(address: 0, used: 0, reserved: 0), count: elements_count)
        loadedNodes.withUnsafeMutableBufferPointer { dest in
            nodesData.copyBytes(to: dest)
        }
        XCTAssertEqual(nodes, loadedNodes, "Nodes should be identical.")
        //        loadedNodes.forEach { $0.dump() }
    }
    ///
    func testStoreLoadNode() {
        var node = Node()
        var node2 = Node()
        var data = Data(repeating: 0, count: MemoryLayout<Node>.size)
        print("Info size: \(MemoryLayout<PageInfo>.size)")
        print("Header size: \(MemoryLayout<Header>.size)")
        print("Node size: \(MemoryLayout<Node>.size)")
        do {
            node.address = 8_555_777_333
            node.used = 123
            node.reserved = 456
            data = try _store(from: node)
            try _load(into: &node2, from: data)
            node2.dump()
            XCTAssertEqual(node, node2, "Nodes are the equal.")
        } catch {
            print("Error: \(error)")
        }
        print("data.count = \(data.count)")
    }
    ///
    func testStoreLoadNodePerformance() {
        var node = Node()
        var node2 = Node()
        var data = Data(repeating: 0, count: MemoryLayout<Node>.size)
        measure {
            do {
                for i in 0..<100_000 {
                    node.address = Address(i)
                    node.used = 123
                    node.reserved = 456
                    data = try _store(from: node)
                    try _load(into: &node2, from: data)
                    XCTAssertEqual(node, node2, "Nodes are the equal.")
                }
            } catch {
                print("Error: \(error)")
            }
        }
        print("data.count = \(data.count)")
    }
    ///
    func testJsonEncoder() {
        var a1 = ContiguousArray<Node>()
        let a1_2 = ContiguousArray<Node>(repeating: Node(), count: elements_count)
        a1.reserveCapacity(elements_count)
        for _ in 0..<elements_count {
            a1.append(Node(address: UInt64.random(in: 100_000_000..<8_000_000_000_000_000),
                           used: Int.random(in: 1_000_000..<8_000_000),
                           reserved: Int.random(in: 8_000_000..<16_000_000)))
        }
        print("\(a1.capacity) : \(a1_2.capacity)")
        let sdata1 = try! JSONEncoder().encode(a1)
        let sdata_lz4 = try! (sdata1 as NSData).compressed(using: .lz4)
        let sdata1_2 = try! JSONEncoder().encode(a1_2)
        let sdata_lz4_2 = try! (sdata1_2 as NSData).compressed(using: .lz4)
        print("sdata1000.count = \(sdata1.count) (\(sdata_lz4.count)) : \(sdata1_2.count) (\(sdata_lz4_2.count))")
//        if let JSONString = String(data: sdata1, encoding: String.Encoding.utf8) {
//            print(JSONString)
//        }
    }
    ///
    func testJsonEncoderNodeArray() {
        typealias NodeA = [UInt64]
        var a1 = Array<NodeA>()
        let a1_2 = Array<NodeA>(repeating: [0,0,0], count: elements_count)
        for _ in 0..<elements_count {
            a1.append([UInt64.random(in: 100_000_000..<8_000_000_000_000_000),
                       UInt64.random(in: 1_000_000..<8_000_000),
                       UInt64.random(in: 8_000_000..<16_000_000)])
        }
        print("\(a1.capacity) : \(a1_2.capacity)")
        let sdata1 = try! JSONEncoder().encode(a1)
        let sdata_lz4 = try! (sdata1 as NSData).compressed(using: .lz4)
        let sdata1_2 = try! JSONEncoder().encode(a1_2)
        let sdata_lz4_2 = try! (sdata1_2 as NSData).compressed(using: .lz4)
        print("sbata1000.count = \(sdata1.count) (\(sdata_lz4.count)) : \(sdata1_2.count) (\(sdata_lz4_2.count))")
//        if let JSONString = String(data: sdata1, encoding: String.Encoding.utf8) {
//            print(JSONString)
//        }
    }
    ///
    func testJsonEncoderContiguousNodeArray() {
        typealias NodeA = ContiguousArray<UInt64>
        var a1 = ContiguousArray<NodeA>()
        let a1_2 = ContiguousArray<NodeA>(repeating: [0,0,0], count: elements_count)
        //        a1.reserveCapacity(elements_count * (MemoryLayout<UInt64>.size + MemoryLayout<UInt64>.alignment) * 3)
        for _ in 0..<elements_count {
            a1.append([UInt64.random(in: 100_000_000..<8_000_000_000_000_000),
                       UInt64.random(in: 1_000_000..<8_000_000),
                       UInt64.random(in: 8_000_000..<16_000_000)])
        }
        print("\(a1.capacity) : \(a1_2.capacity)")
        let sdata1 = try! JSONEncoder().encode(a1)
        let sdata_lz4 = try! (sdata1 as NSData).compressed(using: .lz4)
        let sdata1_2 = try! JSONEncoder().encode(a1_2)
        let sdata_lz4_2 = try! (sdata1_2 as NSData).compressed(using: .lz4)
        print("sbata1000.count = \(sdata1.count) (\(sdata_lz4.count)) : \(sdata1_2.count) (\(sdata_lz4_2.count))")
//        if let JSONString = String(data: sdata1, encoding: String.Encoding.utf8) {
//            print(JSONString)
//        }
    }

}
