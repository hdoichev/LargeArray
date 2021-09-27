//
//  File.swift
//  
//
//  Created by Hristo Doichev on 9/27/21.
//

import Foundation

///
struct Node: Codable {
    var address: Address = 0
    var used: Int = 0
    var reserved: Int = 0
}

extension Node {
    func dump() {
        print("Address = \(self.address), Used = \(self.used), Reserved = \(self.reserved)")
    }
}

extension Node: Equatable {
    static func == (lhs: Node, rhs: Node) -> Bool {
        return
        (lhs.address == rhs.address &&
         lhs.used == rhs.used &&
         lhs.reserved == rhs.reserved)
    }
}

extension Node: CustomStringConvertible {
    var description: String {
        "Node(address: \(address), used: \(used), reserved: \(reserved))"
    }
}
