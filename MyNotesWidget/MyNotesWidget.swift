//  MyNotesWidget.swift
//  MyNotesWidget
//
//  The home-screen widget (roadmap item 12). Small shows the most
//  recent page; medium shows the most recent pages (up to 4).
//  Tapping a page opens it in the app. See README.md in this folder
//  for the Xcode setup — this file belongs to the Widget Extension
//  target, not the app target.

import WidgetKit
import SwiftUI

@main
struct MyNotesWidget: Widget {
    let kind: String = "MyNotesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MyNotesProvider()) { entry in
            MyNotesWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("MyNotes")
        .description("Your most recent notes, right on the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
