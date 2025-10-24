//
//  DataModel.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import Foundation
import Combine

struct Block: Identifiable, Codable {
    let id: UUID
    var type: BlockType
    var content: String
}

enum BlockType: String, Codable {
    case text
    case todo
    case calendarEvent
}

class AppData: ObservableObject {
    @Published var pages: [Page] = []
    
    init() {
        loadData()
    }
    
    func saveData() {
        if let encoded = try? JSONEncoder().encode(pages) {
            UserDefaults.standard.set(encoded, forKey: "pages")
        }
    }
    
    func loadData() {
        if let data = UserDefaults.standard.data(forKey: "pages"),
           let decoded = try? JSONDecoder().decode([Page].self, from: data) {
            pages = decoded
        }
    }
}

struct Page: Identifiable, Codable {
    let id: UUID
    var title: String
    var blocks: [Block] = []
}
