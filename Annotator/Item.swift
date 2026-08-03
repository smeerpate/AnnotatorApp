//
//  Item.swift
//  Annotator
//
//  Created by Frederic Torreele on 03/08/2026.
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
