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

    /// A one-line description of what the template contains, for the
    /// Templates Gallery card. Factual only — what its initial
    /// blocks are.
    var galleryDescription: String {
        switch self {
        case .blank: return "A blank page to start from."
        case .notes: return "Two text blocks for quick notes."
        case .todo: return "Two to-do items to check off."
        case .calendar: return "A calendar block for events."
        case .journal: return "A dated text block for today's entry."
        case .meeting: return "An agenda with two action items."
        case .project: return "Goals, notes, and a calendar for a project."
        }
    }

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
