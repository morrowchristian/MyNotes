//  DataModel.swift
import Foundation
import Combine

enum BlockType: String, Codable, CaseIterable {
    case text
    case todo
    case calendar
    // TODO: Add more types
}

/// The color an event is shown with in the calendar, stored by name
/// (e.g. "blue") so it encodes cleanly to JSON.
enum EventColor: String, Codable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case purple
    case pink
}

/// A calendar event: the note text plus the color it is shown with.
/// Events saved by earlier versions are plain strings; see init(from:).
struct CalendarEvent: Codable {
    var text: String
    var color: EventColor

    init(text: String, color: EventColor = .blue) {
        self.text = text
        self.color = color
    }

    // MARK: - Migration
    // Earlier versions stored events as [Date: String]. Accept either a
    // plain string (old format — default color blue) or the new object,
    // so existing saved events still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self.text = text
            self.color = .blue
        } else {
            let object = try container.decode(CalendarEventObject.self)
            self.text = object.text
            self.color = object.color ?? .blue
        }
    }

    /// The new on-disk shape for an event.
    private struct CalendarEventObject: Decodable {
        var text: String
        var color: EventColor?
    }
}

struct Block: Identifiable, Codable {
    let id: UUID
    var type: BlockType
    var content: String = ""
    var isCompleted: Bool = false
    var events: [Date: CalendarEvent] = [:]
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
    
    let undoManager = UndoManager()
    
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
