//
//  Item.swift
//  veogen
//
//  Created by Heavyshark on 6.06.2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
