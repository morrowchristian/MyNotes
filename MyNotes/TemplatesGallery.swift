//  TemplatesGallery.swift
//  MyNotes
//
//  The Templates Gallery (roadmap item 15): a browsable gallery of
//  page templates — the 7 built-in templates plus the user's own
//  custom templates (saved from a page via "Save as Template").
//  Tapping a card creates a new page from that template and opens
//  it. There is no community backend: everything is local. Custom
//  templates are NOT synced to iCloud in v1 (the item-8 snapshot
//  covers pages + folders + theme only).

import SwiftUI

/// A one-line summary of the blocks a template creates, e.g.
/// "2 text blocks" or "1 text block, 2 to-do blocks". Blocks are
/// grouped by type in the order they first appear, so the summary
/// follows the template's layout. An empty template reads "No blocks".
func templateBlockSummary(_ blocks: [Block]) -> String {
    guard !blocks.isEmpty else { return "No blocks" }
    var counts: [(type: BlockType, count: Int)] = []
    for block in blocks {
        if let index = counts.firstIndex(where: { $0.type == block.type }) {
            counts[index].count += 1
        } else {
            counts.append((type: block.type, count: 1))
        }
    }
    return counts.map { item in
        let name = item.type.displayName.lowercased()
        return "\(item.count) \(name) block\(item.count == 1 ? "" : "s")"
    }.joined(separator: ", ")
}

/// The Templates Gallery sheet: two sections — "Built-in" (the 7
/// templates from Templates.swift) and "My Templates" (custom
/// templates saved from a page). Tapping a card creates a new page
/// from that template and opens it. Custom templates delete with a
/// swipe (plain delete, no Undo — the template can be re-saved from
/// its source page any time, so nothing is lost that can't be remade).
struct TemplatesGalleryView: View {
    @ObservedObject var appData: AppData
    @Binding var selectedPageID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(Template.allCases) { template in
                        templateRow(
                            name: template.rawValue,
                            description: template.galleryDescription,
                            summary: templateBlockSummary(template.initialBlocks)
                        ) {
                            createPage(from: template.initialBlocks, title: template.rawValue)
                        }
                    }
                }
                Section("My Templates") {
                    if appData.customTemplates.isEmpty {
                        Text("No custom templates yet — save a page as a template to see it here.")
                            .foregroundStyle(Color.appMutedText)
                    } else {
                        ForEach(appData.customTemplates) { custom in
                            templateRow(
                                name: custom.name,
                                description: "Saved \(AppData.formatTimestamp(custom.createdAt))",
                                summary: templateBlockSummary(custom.blocks)
                            ) {
                                createPage(from: custom.instantiatedBlocks(), title: custom.name)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteCustomTemplate(custom)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Rows

    /// One template card: name, a one-line description, and the
    /// block summary. The whole row is the button — tapping it
    /// creates a page from the template.
    @ViewBuilder
    private func templateRow(name: String, description: String, summary: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color.appMutedText)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color.appMutedText)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// Creates a page from the given blocks and opens it. The title
    /// is the template's name, with a timestamp appended when a page
    /// with that title already exists — the same dedup rule as the
    /// sidebar's Create Page flow.
    private func createPage(from blocks: [Block], title: String) {
        var finalTitle = title
        let now = Date()
        if appData.pages.contains(where: { $0.title == finalTitle }) {
            finalTitle += " - \(AppData.formatTimestamp(now))"
        }
        let newPage = Page(
            id: UUID(),
            title: finalTitle,
            createdAt: now,
            blocks: blocks
        )
        appData.pages.append(newPage)
        selectedPageID = newPage.id
        dismiss()
    }

    /// Deletes a custom template. Plain delete, no Undo — the source
    /// page still exists, so the template can be re-saved any time.
    private func deleteCustomTemplate(_ template: CustomTemplate) {
        appData.customTemplates.removeAll { $0.id == template.id }
    }
}

#Preview {
    TemplatesGalleryView(appData: AppData(), selectedPageID: .constant(nil))
}
