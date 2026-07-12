//
//  Item.swift
//  TInyQuestDeck
//
//  Created by Joey Rubin on 6/21/26.
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
