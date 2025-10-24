//
//  DataModel.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import Foundation
import Combine

enum BlockType: String, Codable, CaseIterable {
    case text
    case todo
    case calendarEvent
}

struct Block: Identifiable, Codable {
    let id: UUID
    var type: BlockType
    var content: String
    var isCompleted: Bool = false
    var date: Date? = nil // For calendar events
}

struct Page: Identifiable, Codable {
    let id: UUID
    var title: String
    var blocks: [Block] = []
}

class AppData: ObservableObject {
    @Published var pages: [Page] = [] {
        didSet { saveData() }
    }
    
    init() {
        loadData()
    }
    
    func saveData() {
        guard let encoded = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(encoded, forKey: "pages")
    }
    
    func loadData() {
        guard let data = UserDefaults.standard.data(forKey: "pages"),
              let decoded = try? JSONDecoder().decode([Page].self, from: data) else { return }
        pages = decoded
    }
}
