//  WidgetViews.swift
//  MyNotesWidget
//
//  The widget UI: small shows the most recent page, medium shows a
//  short list of the most recent pages. System colors only, so both
//  follow the system light/dark appearance with no extra work.
//  Tapping a page deep-links into it in the app (mynotes://page/<id>);
//  the placeholder has no links, so tapping it just opens the app.

import SwiftUI
import WidgetKit

struct MyNotesWidgetEntryView: View {
    var entry: MyNotesEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(pages: entry.pages, isPlaceholder: entry.isPlaceholder)
        case .systemMedium:
            MediumWidgetView(pages: entry.pages, isPlaceholder: entry.isPlaceholder)
        default:
            SmallWidgetView(pages: entry.pages, isPlaceholder: entry.isPlaceholder)
        }
    }
}

// MARK: - Small: the most recent page

struct SmallWidgetView: View {
    let pages: [WidgetPageSummary]
    let isPlaceholder: Bool

    var body: some View {
        if let page = pages.first {
            VStack(alignment: .leading, spacing: 4) {
                Text("MyNotes")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(page.title)
                    .font(.headline)
                    .lineLimit(2)
                if !page.preview.isEmpty {
                    Text(page.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(isPlaceholder ? nil : widgetURL(for: page.id))
        } else {
            // No pages at all (the provider normally substitutes the
            // sample placeholder, so this is only a safety net).
            Text("No pages yet")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Medium: the most recent pages, up to 4

struct MediumWidgetView: View {
    let pages: [WidgetPageSummary]
    let isPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Notes")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(pages.prefix(4)) { page in
                MediumWidgetRow(page: page, isPlaceholder: isPlaceholder)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MediumWidgetRow: View {
    let page: WidgetPageSummary
    let isPlaceholder: Bool

    /// The first line of the preview (the medium row shows one line).
    private var firstLine: String {
        page.preview.components(separatedBy: .newlines).first ?? ""
    }

    var body: some View {
        let row = VStack(alignment: .leading, spacing: 1) {
            Text(page.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
            if !firstLine.isEmpty {
                Text(firstLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if isPlaceholder {
            row
        } else if let url = widgetURL(for: page.id) {
            Link(destination: url) { row }
        } else {
            row
        }
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    MyNotesWidget()
} timeline: {
    MyNotesEntry(date: Date(), pages: [.sample], isPlaceholder: true)
    MyNotesEntry(
        date: Date(),
        pages: [
            WidgetPageSummary(
                id: UUID(),
                title: "Grocery list",
                preview: "Milk\nEggs, bread, coffee",
                blockCount: 3,
                createdAt: Date()
            ),
            WidgetPageSummary(
                id: UUID(),
                title: "Meeting notes",
                preview: "Ship the widget by Friday.",
                blockCount: 2,
                createdAt: Date()
            ),
        ],
        isPlaceholder: false
    )
}

#Preview(as: .systemMedium) {
    MyNotesWidget()
} timeline: {
    MyNotesEntry(
        date: Date(),
        pages: [
            WidgetPageSummary(
                id: UUID(),
                title: "Grocery list",
                preview: "Milk\nEggs, bread, coffee",
                blockCount: 3,
                createdAt: Date()
            ),
            WidgetPageSummary(
                id: UUID(),
                title: "Meeting notes",
                preview: "Ship the widget by Friday.",
                blockCount: 2,
                createdAt: Date()
            ),
        ],
        isPlaceholder: false
    )
}
