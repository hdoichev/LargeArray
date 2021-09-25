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
                        XCTAssertNoThrow( try la.append(Data(repeating: UInt8(i % 128), count: 10)))
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
        let numElements = 1024*10
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 0..<numElements {
                try la.append(Data(repeating: UInt8(i % 128), count: 10))
            }
            print(la)
            measure {
                for n in la { XCTAssertEqual(n.count, 10) }
            }
//            measure {
//                la.forEach { XCTAssertEqual($0.count, 10) }
//            }
        } catch {}
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
