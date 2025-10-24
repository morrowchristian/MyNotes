//  DataModel.swift
import Foundation
import Combine

enum BlockType: String, Codable, CaseIterable {
    case text
    case todo
    case calendar
    // TODO: Add more types
}

struct Block: Identifiable, Codable {
    let id: UUID
    var type: BlockType
    var content: String = ""
    var isCompleted: Bool = false
    var events: [Date: String] = [:]
}

struct Page: Identifiable, Codable {
    let id: UUID
    var title: String
    var createdAt: Date
    var blocks: [Block] = []
}

class AppData: ObservableObject {
    @Published var pages: [Page] = [] {
        didSet { saveData() }
    }
    
    init() { loadData() }
    
    func saveData() {
        guard let encoded = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(encoded, forKey: "pages")
    }
    
    func loadData() {
        guard let data = UserDefaults.standard.data(forKey: "pages"),
              let decoded = try? JSONDecoder().decode([Page].self, from: data) else { return }
        pages = decoded
    }
    
    static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return formatter.string(from: date)
    }
}
