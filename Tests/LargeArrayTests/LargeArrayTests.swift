import XCTest
import Compression
@testable import LargeArray

@available(macOS 10.15.4, *)
final class LargeArrayTests: XCTestCase {
    let file_path = "/Users/hristo/test/LargeArray/Test.LargeArray"
    let file_path2 = "/Users/hristo/test/LargeArray/Test2.LargeArray"
    let elements_count = 10
    ///
    override func setUp() {
        [file_path, file_path2].forEach { path in
            if FileManager.default.fileExists(atPath: path) {
                do { try FileManager.default.removeItem(atPath: path) }
                catch { fatalError("Can not remove test file: \(path)")}
            }
        }
    }
    ///
    func testCreateEmptyLargeArray() {
        func create() {
            let la = LargeArray(path: file_path, capacity: 16*1024*1024)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            print("Version: \(la._header)")
        }
        create()
        // read the file
        func readFile() {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            print("Version: \(la._header)")
        }
        readFile()
    }
    ///
    func testAppendNode() {
        func createFile() {
            guard let la = LargeArray(path: file_path, capacity: 16*1024*1024) else { XCTFail("LargeArray init failed"); return }
            XCTAssertNoThrow( try la.append(Data(repeating: 0, count: 10)))
        }
        createFile()
        // read the file
        func readFile() {
            guard let _ = LargeArray(path: file_path) else { XCTFail("LargeArray init failed"); return }
//            la[0].dump()
        }
        readFile()
    }
    ///
    func testAppendMultipleNodes() {
        let numElements = 1024*2
        func create() {
            guard let la = LargeArray(path: file_path, capacity: 16*1024*1024) else { XCTFail("LargeArray init failed"); return }
            for i in 0..<numElements {
                XCTAssertNoThrow( try la.append(Data(repeating: UInt8(i % 128), count: 10)))
            }
        }
        create()
        // read the file
        func readFile() {
            guard let la = LargeArray(path: file_path) else { XCTFail("LargeArray init failed"); return }
//            for i in stride(from: 0, to: numElements, by: 100) {
//            }
            for i in 0..<numElements {
                la[i].forEach{XCTAssertEqual($0, UInt8(i % 128))}
            }

            for n in la { XCTAssertEqual(n.count, 10) }
            la.forEach { XCTAssertEqual($0.count, 10) }
            
            la[0] = Data(repeating: 19, count: 19)
            XCTAssertEqual(la[0].count, 19)
            print(la)
        }
        readFile()
    }
    ///
    func testAppendManyNodeToArrayPerformance() {
        let numElements = 1024*100
        let la = LargeArray(path: file_path, maxPerPage: 32)
        XCTAssertNotNil(la)
        guard let la = la else { return }
        let d = Data(repeating: 0xfa, count: Int.random(in: 1500..<1501))
        measure {
            do {
                for _ in 0..<numElements {
                    try la.append(d)
                }
            } catch {
                print(error)
                XCTFail()
            }
        }
        print(la)
    }
    ///
    func testTraverseAllElementsInArrayPerformance() {
        let numElements = 1024*10
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 0..<numElements {
                try la.append(Data(repeating: UInt8(i % 128), count: Int.random(in: 1000..<1501)))
            }
            print(la)
            measure {
                for _ in 0..<5 {
                    for i in 0..<32 {
                        for idx in stride(from: i, to: numElements, by: 32) {
                            XCTAssertTrue((1000..<1501).contains(la[idx].count))
                        }
                    }
                }
//                print(la._storage.pageCache.cacheCounter, la._storage.pageCache._cacheMiss)
            }
        } catch {}
    }
    ///
    func testRemoveElements_PageMid() {
        let numElements = 1024*3
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for _ in 0..<numElements { try la.append(Data(repeating: 1, count: 100)) }
            la[1024] = Data(repeating: 2, count: 100)
            for i in 1024..<2048 { la[i] = Data(repeating: 2, count: 100) }
            print(la)
            la[1024].forEach { XCTAssertEqual($0, 2) }
            // remove all elements from the second page
            XCTAssertNoThrow(try la.removeSubrange(1024..<2048))
            la[1024].forEach { XCTAssertEqual($0, 1) }
            la[0].forEach { XCTAssertEqual($0, 1) }
            la.forEach { $0.forEach { XCTAssertEqual($0, 1) } }
            print(la)
        } catch {}
    }
    func testRemoveElements_PageLast() {
        let numElements = 1024*3
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for _ in 0..<numElements { try la.append(Data(repeating: 1, count: 100)) }
            la[2048] = Data(repeating: 2, count: 100)
            for i in 2048..<3072 { la[i] = Data(repeating: 2, count: 100) }
            print(la)
            la[2048].forEach { XCTAssertEqual($0, 2) }
            // remove all elements from the second pate
            XCTAssertNoThrow(try la.removeSubrange(2048..<3072))
            la[1024].forEach { XCTAssertEqual($0, 1) }
            la[0].forEach { XCTAssertEqual($0, 1) }
            la.forEach { $0.forEach { XCTAssertEqual($0, 1) } }
            print(la)
        } catch {}
    }
    func testRemoveElements_PageFirst() {
        let numElements = 1024*3
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for _ in 0..<numElements { try la.append(Data(repeating: 1, count: 100)) }
            la[0] = Data(repeating: 2, count: 100)
            for i in 0..<1024 { la[i] = Data(repeating: 2, count: 100) }
            print(la)
            la[0].forEach { XCTAssertEqual($0, 2) }
            // remove all elements from the second page
            XCTAssertNoThrow(try la.removeSubrange(0..<1024))
            la[1024].forEach { XCTAssertEqual($0, 1) }
            la[0].forEach { XCTAssertEqual($0, 1) }
            la.forEach { $0.forEach { XCTAssertEqual($0, 1) }}
            print(la)
        } catch {}
    }
    func testRemoveElements_PagePartial() {
        let maxPerPage = 1024
        let elementSize = 100
        do {
            let la = LargeArray(path: file_path, maxPerPage: maxPerPage)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 1..<4 {
                let d = Data(repeating: UInt8(i), count: elementSize)
                for _ in 0..<1024 { try la.append(d) }
            }
            print(la)
            XCTAssertNoThrow(try la.removeSubrange(2048+100..<3072)) // remove elements from the third page
            XCTAssertNoThrow(try la.removeSubrange(1024+100..<2048)) // remove elements from the second page
            XCTAssertNoThrow(try la.removeSubrange(0+100..<1024)) // remove elements from the first page

            for i in 0..<100 { la[i].forEach { XCTAssertEqual($0, 1) }}
            for i in 100..<200 { la[i].forEach { XCTAssertEqual($0, 2) }}
            for i in 200..<300 { la[i].forEach { XCTAssertEqual($0, 3) }}

            print(la)
            print("Used count: \(la.totalUsedBytesCount), Free count: \(la.totalFreeBytesCount)")
            if let la2 = LargeArray(path: file_path2, maxPerPage: maxPerPage) {
                try la.forEach { d in
                    try la2.append(d)
                }
//                print("Used count: \(la2.totalUsedBytesCount), Free count: \(la2.totalFreeBytesCount)")
            }
        } catch {}
    }
    ///
    func testRemoveElements_All() {
        let maxPerPage = 1024
        let elementsCount = 1024//*1024*10
        let elementSize = 100
        do {
            let la = LargeArray(path: file_path, maxPerPage: maxPerPage)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 1..<4 {
                let d = Data(repeating: UInt8(i), count: elementSize)
                for _ in 0..<elementsCount { try la.append(d) }
            }
            //            let d = Data(repeating: UInt8(9), count: elementSize)
            //            for _ in 0..<elementsCount { try la.append(d) }
            print(la)
            XCTAssertNoThrow(try la.removeSubrange(0..<la.count)) // remove all elements
//            try la.insert(Data(repeating: 1, count: elementSize), at: 0)
            try la.append(Data(repeating: 1, count: elementSize))
            print(la)
        } catch {}
    }
    ///
    func testInsertElement_PageSplit() {
        do {
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 1..<3 {
                for _ in 0..<1024 { try la.append(Data(repeating: UInt8(i), count: 100)) }
            }
            print(la)
            XCTAssertNoThrow(try la.insert(Data(repeating: 4, count: 100), at: 1024))
            la[1024].forEach{XCTAssertEqual($0, 4)}
            XCTAssertNoThrow(try la.insert(Data(repeating: 3, count: 100), at: 1023))
            la[1023].forEach{XCTAssertEqual($0, 3)}
            print(la)
        } catch {
            XCTFail()
        }
    }
    ///
    func testAppendArrays() {
        do {
            let elementsCount = 1*1024
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            // Ints
            for i in 0..<elementsCount { try autoreleasepool { try la.append([Int](repeating: i, count: i)) } }
            for i in 0..<elementsCount {
                autoreleasepool {
                let ints: [Int] = la[i]
                XCTAssertEqual(i, ints.count)
                ints.forEach { XCTAssertEqual($0, i) }
                }
            }
            // Floats
            for i in 0..<elementsCount { try autoreleasepool { try la.append([Float](repeating: Float(i), count: i)) } }
            for i in 0..<elementsCount {
                autoreleasepool {
                    let floats: [Float] = la[i + 1024]
                    XCTAssertEqual(i, floats.count)
                    floats.forEach { XCTAssertEqual($0, Float(i)) }
                }
            }
            // String
            for i in 0..<elementsCount { try autoreleasepool { try la.append([String](repeating: "\(i)", count: i)) } }
            for i in 0..<elementsCount {
                autoreleasepool {
                    let strings: [String] = la[i + 2048]
                    XCTAssertEqual(i, strings.count)
                    strings.forEach { XCTAssertEqual($0, "\(i)") }
                }
            }

            print(la)
        } catch {
            XCTFail()
        }
    }
    ///
    func test_ScalerValues() {
        do {
            let elementsCount = 1*1024
            let la = LargeArray(path: file_path)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            // Ints
            for i in 0..<elementsCount { try autoreleasepool { try la.append(i) } }
            for i in 0..<elementsCount {
                autoreleasepool {
                    XCTAssertEqual(la[i], i)
                }
            }
            // Floats
            for i in 0..<elementsCount { try autoreleasepool { try la.append(Float(i*i)) } }
            for i in 0..<elementsCount {
                autoreleasepool {
                    XCTAssertEqual(la[i + 1024], Float(i*i))
                }
            }
            // String
            for i in 0..<elementsCount { try autoreleasepool { try la.append("\(i+i)") } }
            for i in 0..<elementsCount {
                autoreleasepool {
                    XCTAssertEqual(la[i + 2048], "\(i+i)")
                }
            }
            
//            let a = la[0..<10]
//            a.forEach { print($0) }
            print(la)
        } catch {
            XCTFail()
        }
    }
}
