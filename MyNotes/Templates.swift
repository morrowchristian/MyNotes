//
//  Templates.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import Foundation

enum Template: String, CaseIterable, Identifiable {
    case blank = "Blank"
    case todo   = "To-Do List"
    case calendar = "Calendar"

    var id: Self { self }

    var markdown: String {
        switch self {
        case .blank:
            return "# New Page\n\nStart typing **Markdown** here…"
        case .todo:
            return """
            # To-Do List

            - [ ] Buy milk
            - [ ] Call mom
            - [ ] Finish project

            Add more with `- [ ]`
            """
        case .calendar:
            return """
            # Calendar

            | Date       | Event                | Notes |
            |------------|----------------------|-------|
            | 2025-10-25 | Team meeting        | Bring laptop |
            | 2025-11-01 | Doctor appointment  | 10 am |

            Use tables or `## YYYY-MM-DD` headings.
            """
        }
    }
}
