//
//  Item.swift
//  spatial-audio-calibrator
//
//  Created by Fedir Saienko on 10.03.26.
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
