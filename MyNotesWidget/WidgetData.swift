//  WidgetData.swift
//  MyNotesWidget
//
//  The data the widget reads: a lightweight summary of the user's
//  pages, written by the main app into the App Group shared
//  container. This file is self-contained — the widget extension
//  does NOT include the app's DataModel.swift, so the summary struct
//  is defined here too. It must keep the same shape (same property
//  names and types) as WidgetPageSummary in the app's
//  DataModel.swift, or the widget fails to decode the summary and
//  shows its placeholder instead.

import Foundation

/// The App Group shared container id. Must match the id in the App
/// Group capability on BOTH the app target and the widget target,
/// and the value in the app's DataModel.swift.
let widgetAppGroupID = "group.morrowchristian.MyNotes"

/// The key the app writes the encoded summaries under.
let widgetPagesKey = "widgetPages"

/// A lightweight summary of one page for the widget. Mirrors the
/// struct of the same name in the app's DataModel.swift.
struct WidgetPageSummary: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var preview: String
    var blockCount: Int
    var createdAt: Date
}

/// Reads the page summaries the app wrote to the shared container.
/// Returns nil when the App Group is not configured yet, when the
/// app has not written anything, or when the data does not decode —
/// the caller shows its placeholder in all of those cases.
func loadWidgetPages() -> [WidgetPageSummary]? {
    guard let shared = UserDefaults(suiteName: widgetAppGroupID),
          let data = shared.data(forKey: widgetPagesKey),
          let pages = try? JSONDecoder().decode([WidgetPageSummary].self, from: data) else {
        return nil
    }
    return pages
}

/// The deep link that opens a page in the app: mynotes://page/<id>.
/// The app handles it in MainView (.onOpenURL). The "mynotes" URL
/// scheme must be registered on the app target (see README.md) or
/// tapping a widget just opens the app. Returns nil only if the URL
/// somehow fails to build (a UUID string is always URL-safe, so in
/// practice this never happens).
func widgetURL(for pageID: UUID) -> URL? {
    var components = URLComponents()
    components.scheme = "mynotes"
    components.host = "page"
    components.path = "/\(pageID.uuidString)"
    return components.url
}
