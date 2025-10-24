//
//  CalenderView.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import SwiftUI

struct CalendarView: View {
    @ObservedObject var appData: AppData
    
    var events: [Block] {
        appData.pages.flatMap { $0.blocks.filter { $0.type == .calendarEvent } }
    }
    
    var body: some View {
        List(events.sorted(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) })) { event in
            HStack {
                if let date = event.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                Text(event.content)
            }
        }
        .navigationTitle("Calendar")
    }
}
