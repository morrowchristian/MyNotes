//  Templates.swift
import Foundation

enum Template: String, CaseIterable, Identifiable {
    case blank = "Blank"
    case notes = "Notes"
    case todo = "To-Do List"
    case calendar = "Calendar"
    case journal = "Journal"
    case meeting = "Meeting Notes"
    case project = "Project Tracker"

    var id: Self { self }

    var initialBlocks: [Block] {
        switch self {
        case .blank:
            return []
        case .notes:
            return [
                Block(id: UUID(), type: .text, content: "Note 1..."),
                Block(id: UUID(), type: .text, content: "Note 2...")
            ]
        case .todo:
            return [
                Block(id: UUID(), type: .todo, content: "Task 1"),
                Block(id: UUID(), type: .todo, content: "Task 2")
            ]
        case .calendar:
            return [Block(id: UUID(), type: .calendar, events: [:])]
        case .journal:
            let today = Date()
            return [Block(id: UUID(), type: .text, content: "# \(AppData.formatTimestamp(today))\n\nJournal entry...")]
        case .meeting:
            return [
                Block(id: UUID(), type: .text, content: "# Agenda\n\n- Item 1\n- Item 2"),
                Block(id: UUID(), type: .todo, content: "Action item 1"),
                Block(id: UUID(), type: .todo, content: "Action item 2")
            ]
        case .project:
            return [
                Block(id: UUID(), type: .todo, content: "Goal 1"),
                Block(id: UUID(), type: .text, content: "Project notes..."),
                Block(id: UUID(), type: .calendar, events: [:])
            ]
        }
    }
}
