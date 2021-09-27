import XCTest
import Compression
@testable import LargeArray

@available(macOS 10.15.4, *)
final class LargeArrayTests: XCTestCase {
    let file_path = "/Users/hristo/junk/Test.LargeArray"
    let elements_count = 10
    ///
    override func setUp() {
        if FileManager.default.fileExists(atPath: file_path) {
            do { try FileManager.default.removeItem(atPath: file_path) }
            catch { fatalError("Can not remove test file.")}
        }
    }
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
//        nodes.withUnsafeBytes { source in
//            nodesData.withUnsafeMutableBytes { dest in
//                dest.copyBytes(from: source)
//            }
//        }
        nodesData.withUnsafeBytes { bytes in
            let raw_nodes = bytes.bindMemory(to: Node.self)
//            raw_nodes.forEach { $0.dump() }
        }
        // now init the arrat from the data
        print("===")
        var loadedNodes = ContiguousArray<Node>(repeating: Node(address: 0, used: 0, reserved: 0), count: elements_count)
        loadedNodes.withUnsafeMutableBufferPointer { dest in
            nodesData.copyBytes(to: dest)
        }
        XCTAssertEqual(nodes, loadedNodes, "Nodes should be idnetical.")
//        loadedNodes.forEach { $0.dump() }
    }
    ///
    func testCreateEmptyLargeArray() {
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            print("Version: \(la._header)")
        } catch {}
        // read the file
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            print("Version: \(la._header)")
        } catch {}
    }
    ///
    func testAppendNode() {
        do {
            var la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard var la = la else { return }
            try la.append(Data(repeating: 0, count: 10))
        } catch {}
        // read the file
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            XCTAssertEqual(la._currentPage.info._availableNodes, 1)
//            la[0].dump()
        } catch {}
    }
    ///
    func testAppendMultipleNodes() {
        let numElements = 1024*2
        do {
            var la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard var la = la else { return }
            for i in 0..<numElements {
                try la.append(Data(repeating: UInt8(i % 128), count: 10))
            }
            print("Nodes.count = \(la._currentPage.info._availableNodes)")
        } catch {}
        // read the file
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard var la = la else { return }
//            XCTAssertEqual(la._currentPage._nodes.count, numElements)
//            for i in 0..<numElements {
//                la._currentPage._nodes[i].dump()
//            }
            for i in stride(from: 0, to: numElements, by: 100) {
                let node = try la.getNodeFor(index: i)
//                print("Index: \(i): \(node), \(la._currentPage)")
                print("Index: \(i): \(node)")
            }
            
            for n in la { XCTAssertEqual(n.count, 10) }
            la.forEach { XCTAssertEqual($0.count, 10) }
            
            la[0] = Data(repeating: 19, count: 19)
            XCTAssertEqual(la[0].count, 19)
            print(la)
//            print(MemoryLayout<Node>.description)
//            print(la._currentPage._nodes[10000].reserved)
        } catch {
            print(error)
        }
    }
    ///
    func testAppendManyNodeToArrayPerformance() {
        let numElements = 1024*10
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            measure {
                do {
                    for i in 0..<numElements {
                        XCTAssertNoThrow( try la.append(Data(repeating: UInt8(i % 128), count: Int.random(in: 100..<2000))))
                    }
                } catch {
                    XCTFail()
                }
            }
            print(la)
        } catch {}
    }
    ///
    func testTraverseAllElementsInArrayPerformance() {
        let numElements = 1024*100
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 0..<numElements {
                try la.append(Data(repeating: UInt8(i % 128), count: Int.random(in: 100..<2000)))
            }
            print(la)
            measure {
                for n in la {
//                    XCTAssertTrue((10..<2000).contains(n.count))
                    if (10..<2000).contains(n.count) == false {
                        print("ERROR")
                        break
                    }
                }
            }
//            measure {
//                la.forEach { XCTAssertEqual($0.count, 10) }
//            }
        } catch {}
    }
    ///
    func testRemoveElements_PageMid() {
        let numElements = 1024*3
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 0..<numElements { try la.append(Data(repeating: 1, count: 100)) }
            la[1024] = Data(repeating: 2, count: 100)
            for i in 1024..<2048 { la[i] = Data(repeating: 2, count: 100) }
            print(la)
            la[1024].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 2) } }
            // remove all elements from the second pate
            XCTAssertNoThrow(try la.removeSubrange(1024..<2048))
            la[1024].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } }
            la[0].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } }
            la.forEach { d in d.withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } } }
            print(la)
        } catch {}
    }
    func testRemoveElements_PageLast() {
        let numElements = 1024*3
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 0..<numElements { try la.append(Data(repeating: 1, count: 100)) }
            la[2048] = Data(repeating: 2, count: 100)
            for i in 2048..<3072 { la[i] = Data(repeating: 2, count: 100) }
            print(la)
            la[2048].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 2) } }
            // remove all elements from the second pate
            XCTAssertNoThrow(try la.removeSubrange(2048..<3072))
            la[1024].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } }
            la[0].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } }
            la.forEach { d in d.withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } } }
            print(la)
        } catch {}
    }
    func testRemoveElements_PageFirst() {
        let numElements = 1024*3
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 0..<numElements { try la.append(Data(repeating: 1, count: 100)) }
            la[0] = Data(repeating: 2, count: 100)
            for i in 0..<1024 { la[i] = Data(repeating: 2, count: 100) }
            print(la)
            la[0].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 2) } }
            // remove all elements from the second pate
            XCTAssertNoThrow(try la.removeSubrange(0..<1024))
            la[1024].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } }
            la[0].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } }
            la.forEach { d in d.withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } } }
            print(la)
        } catch {}
    }
    func testRemoveElements_PagePartial() {
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 1..<4 {
                for _ in 0..<1024 { try la.append(Data(repeating: UInt8(i), count: 100)) }
            }
            print(la)
            XCTAssertNoThrow(try la.removeSubrange(2048+100..<3072)) // remove elements from the third page
            XCTAssertNoThrow(try la.removeSubrange(1024+100..<2048)) // remove elements from the second page
            XCTAssertNoThrow(try la.removeSubrange(0+100..<1024)) // remove elements from the first page
            
            for i in 0..<100 { la[i].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } } }
            for i in 100..<200 { la[i].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 2) } } }
            for i in 200..<300 { la[i].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 3) } } }

            print(la)
        } catch {}
    }
    //
    func testInsertElement_PageSplit() {
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 1..<3 {
                for _ in 0..<1024 { try la.append(Data(repeating: UInt8(i), count: 100)) }
            }
            print(la)
            try la.insert(Data(repeating: 4, count: 100), at: 1024)
            la[1024].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 4) } }
            try la.insert(Data(repeating: 3, count: 100), at: 1023)
            la[1023].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 3) } }
            print(la)
        } catch {
            XCTFail()
        }
    }
    ///
    func testStoreLoadNode() {
        var node = Node()
        var node2 = Node()
        var data = Data(repeating: 0, count: MemoryLayout<Node>.size)
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
