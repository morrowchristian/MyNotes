//  Provider.swift
//  MyNotesWidget
//
//  The WidgetKit timeline: reads the page summaries from the shared
//  container and hands the widget a fresh entry. The timeline
//  refreshes every 15 minutes; the app also asks WidgetKit to
//  reload the timeline whenever the summary changes, so edits show
//  up promptly without waiting for this interval.

import WidgetKit
import SwiftUI

/// One widget refresh: the recent pages (newest first).
/// `isPlaceholder` is true when the app has not shared anything yet
/// — the widget shows its sample placeholder instead of a blank view,
/// and the placeholder has no deep links (tapping it just opens the
/// app).
struct MyNotesEntry: TimelineEntry {
    let date: Date
    let pages: [WidgetPageSummary]
    let isPlaceholder: Bool
}

struct MyNotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MyNotesEntry {
        MyNotesEntry(date: Date(), pages: [.sample], isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MyNotesEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MyNotesEntry>) -> Void) {
        let entry = entry()
        // Refresh every 15 minutes; the app also reloads the
        // timeline when the summary changes (see saveWidgetSummary
        // in the app's DataModel.swift).
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    /// Builds the current entry from the shared container. When the
    /// app has not written a summary yet (App Group not configured,
    /// or no pages), the widget shows its sample placeholder.
    private func entry() -> MyNotesEntry {
        if let pages = loadWidgetPages(), !pages.isEmpty {
            return MyNotesEntry(date: Date(), pages: pages, isPlaceholder: false)
        }
        return MyNotesEntry(date: Date(), pages: [.sample], isPlaceholder: true)
    }
}

extension WidgetPageSummary {
    /// Sample data for the widget placeholder / gallery preview and
    /// for when the app has not shared a summary yet. The view never
    /// deep-links from it (tapping the widget just opens the app).
    static var sample: WidgetPageSummary {
        WidgetPageSummary(
            id: UUID(),
            title: "Welcome to MyNotes",
            preview: "Create your first page to see it here.",
            blockCount: 1,
            createdAt: Date()
        )
    }
}
