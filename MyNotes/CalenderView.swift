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
        List(events) { event in
            Text(event.content)
        }
        .navigationTitle("Calendar")
    }
}
