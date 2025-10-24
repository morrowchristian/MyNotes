//  Templates.swift
import Foundation

enum Template: String, CaseIterable, Identifiable {
    case blank = "Blank"
    case todo = "To-Do List"
    case calendar = "Calendar"

    var id: Self { self }

    var initialBlocks: [Block] {
        switch self {
        case .blank:
            return [Block(id: UUID(), type: .text, content: "Start typing here...")]
        case .todo:
            return [
                Block(id: UUID(), type: .todo, content: "Task 1"),
                Block(id: UUID(), type: .todo, content: "Task 2")
            ]
        case .calendar:
            return [Block(id: UUID(), type: .calendar, events: [:])]
        }
    }
}
