//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/27/21.
//

import XCTest
import Compression
@testable import LargeArray

@available(macOS 10.15.4, *)
final class FreeArrayTests: XCTestCase {
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
    func testRemoveElements() {
        let numElements = 10*1
        do {
            let la = FreeArray(path: file_path, maxPerPage: 10)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 0..<numElements { try la.append(Data(repeating: UInt8(i), count: 10)) }
            la[0].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 0) } }
            // remove all elements from the second pate
            XCTAssertNoThrow(try la.remove(at: 0))
//            XCTAssertNoThrow(try la.removeSubrange(1024..<2048))
            la[0].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } }
            print(la)
        } catch {}
        // just read the file and verify the contents
        let la = FreeArray(path: file_path, maxPerPage: 10)
        XCTAssertNotNil(la)
        guard let la = la else { return }
        la[0].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 1) } }
        XCTAssertEqual(la.totalUsedBytesCount, 90)
        XCTAssertEqual(la.totalFreeBytesCount, 10)
        print(la)
        print("Used count: \(la.totalUsedBytesCount), Free count: \(la.totalFreeBytesCount)")
    }
    ///
    func testRemoveElements_ReclaimFreeSpace() {
        let numElements = 1024*1
        do {
            let la = FreeArray(path: file_path, maxPerPage: 10)
            XCTAssertNotNil(la)
            guard let la = la else { return }
            for i in 0..<numElements { try la.append(Data(repeating: UInt8(i%16), count: 10)) }
            la[0].withUnsafeBytes { p in p.bindMemory(to: UInt8.self).forEach { XCTAssertEqual($0, 0) } }
            // remove all elements from the second pate
            for _ in 0..<512 {
                XCTAssertNoThrow(try la.remove(at: Int.random(in: 0..<la.count)))
            }
            print(la)
            print("Used count: \(la.totalUsedBytesCount), Free count: \(la.totalFreeBytesCount)")
            try la.purgeFreeSpace()
        } catch {}
    }

}
