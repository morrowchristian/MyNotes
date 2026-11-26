//  SidebarView.swift
import SwiftUI
import Foundation
import Combine

// MARK: - Undo Coordinator (Class)
final class SidebarUndoCoordinator: ObservableObject {
    @Published var showingUndo = false
    @Published var deletedPages: [Page] = []
    @Published var deletedIndices: IndexSet = []
    // Folder membership of each deleted page, for restoring it on Undo:
    // (page id, folder id, index within that folder's page list).
    private var deletedPageFolderInfo: [(pageID: UUID, folderID: UUID, indexInFolder: Int)] = []
    // Folder delete (undo restores the folder; its pages were never deleted).
    @Published var deletedFolder: Folder? = nil
    @Published var deletedFolderIndex: Int? = nil

    private var appData: AppData
    private var selectedPageID: Binding<UUID?>
    private var deletedSelectedPageID: UUID?

    init(appData: AppData, selectedPageID: Binding<UUID?>) {
        self.appData = appData
        self.selectedPageID = selectedPageID
    }

    /// Delete the given pages. The sidebar resolves the swiped rows to
    /// Page objects (the rows live in different sections — ungrouped and
    /// per-folder — so offsets into `appData.pages` would be wrong).
    func delete(pages: [Page]) {
        // Capture the pages and their positions in appData.pages, sorted
        // by index so Undo re-inserts them in ascending order.
        let indexed = pages.compactMap { page -> (Page, Int)? in
            guard let index = appData.pages.firstIndex(where: { $0.id == page.id }) else { return nil }
            return (page, index)
        }.sorted { $0.1 < $1.1 }
        deletedPages = indexed.map { $0.0 }
        deletedIndices = IndexSet(indexed.map { $0.1 })

        // Capture folder membership so Undo can restore it.
        deletedPageFolderInfo = deletedPages.compactMap { page -> (pageID: UUID, folderID: UUID, indexInFolder: Int)? in
            guard let folder = appData.folderContaining(pageID: page.id),
                  let indexInFolder = folder.pageIDs.firstIndex(of: page.id) else { return nil }
            return (pageID: page.id, folderID: folder.id, indexInFolder: indexInFolder)
        }

        // A page delete supersedes a pending folder-delete snackbar
        // (and vice versa) — the snackbar always describes the most
        // recent deletion, matching the UndoManager's top registration.
        deletedFolder = nil
        deletedFolderIndex = nil

        // Remember the selected page if it is among the deleted ones,
        // so Undo can re-select it.
        if let selected = selectedPageID.wrappedValue,
           deletedPages.contains(where: { $0.id == selected }) {
            deletedSelectedPageID = selected
        } else {
            deletedSelectedPageID = nil
        }

        appData.undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.performUndo()
        }

        withAnimation {
            for page in deletedPages {
                appData.removePageFromFolders(page.id)
            }
            appData.pages.removeAll { page in
                deletedPages.contains { $0.id == page.id }
            }
            if deletedSelectedPageID != nil {
                selectedPageID.wrappedValue = nil
            }
            showingUndo = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                self.showingUndo = false
            }
        }
    }

    private func performUndo() {
        withAnimation {
            for (page, index) in zip(deletedPages, deletedIndices) {
                let clamped = min(max(index, 0), appData.pages.count)
                appData.pages.insert(page, at: clamped)
                // Restore folder membership, if the folder still exists.
                // (If the folder was itself deleted since, the page
                // simply stays ungrouped.)
                if let info = deletedPageFolderInfo.first(where: { $0.pageID == page.id }) {
                    appData.insertPage(page.id, intoFolder: info.folderID, at: info.indexInFolder)
                }
            }
            if let restoredID = deletedSelectedPageID {
                selectedPageID.wrappedValue = restoredID
            }
            showingUndo = false
        }
    }

    /// Delete a folder. Its pages are NOT deleted — they become ungrouped.
    func deleteFolder(_ folder: Folder) {
        guard let index = appData.folders.firstIndex(where: { $0.id == folder.id }) else { return }
        deletedFolder = folder
        deletedFolderIndex = index

        // A folder delete supersedes a pending page-delete snackbar
        // (and vice versa).
        deletedPages = []
        deletedIndices = []
        deletedPageFolderInfo = []

        appData.undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.performFolderUndo()
        }

        withAnimation {
            appData.folders.remove(at: index)
            showingUndo = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                self.showingUndo = false
            }
        }
    }

    private func performFolderUndo() {
        withAnimation {
            if let folder = deletedFolder, let index = deletedFolderIndex {
                let clamped = min(max(index, 0), appData.folders.count)
                appData.folders.insert(folder, at: clamped)
            }
            showingUndo = false
        }
    }
}

struct SidebarView: View {
    @ObservedObject var appData: AppData
    @Binding var selectedPageID: UUID?

    @StateObject private var undoCoordinator: SidebarUndoCoordinator

    // Initialize coordinator
    init(appData: AppData, selectedPageID: Binding<UUID?>) {
        self.appData = appData
        self._selectedPageID = selectedPageID
        let coordinator = SidebarUndoCoordinator(appData: appData, selectedPageID: selectedPageID)
        self._undoCoordinator = StateObject(wrappedValue: coordinator)
    }

    @State private var showingTemplatePicker = false
    @State private var chosenTemplate: Template = .blank
    @State private var newTitle = "New Page"

    @State private var showingNewFolderAlert = false
    @State private var newFolderName = "New Folder"
    @State private var showingRenameAlert = false
    @State private var folderToRename: Folder? = nil
    @State private var renameText = ""

    // The tag the sidebar list is filtered by (nil = no filter).
    // View-only state — it does not change the data or the selection.
    @State private var selectedTag: String? = nil

    // Whether the Appearance (theme) settings sheet is showing.
    @State private var showingThemeSettings = false

    /// Every tag in use across pages, sorted alphabetically, deduped.
    /// The filter chips are derived from the current pages, so a tag
    /// that no longer exists on any page disappears on its own.
    private var allTags: [String] {
        Array(Set(appData.pages.flatMap { $0.tags })).sorted()
    }

    /// Whether a page passes the active tag filter (nil = no filter).
    private func matchesFilter(_ page: Page) -> Bool {
        guard let tag = selectedTag else { return true }
        return page.tags.contains(tag)
    }

    /// Ungrouped pages, filtered by the active tag (if any).
    private var visibleUngroupedPages: [Page] {
        ungroupedPages.filter(matchesFilter)
    }

    /// A folder's pages, filtered by the active tag (if any).
    private func visibleFolderPages(_ folder: Folder) -> [Page] {
        folderPages(folder).filter(matchesFilter)
    }

    /// Folders to show. With no filter, every folder (even an empty
    /// one, as before). With a filter, only folders that contain at
    /// least one matching page.
    private var visibleFolders: [Folder] {
        guard selectedTag != nil else { return appData.folders }
        return appData.folders.filter { !visibleFolderPages($0).isEmpty }
    }

    /// Pages in no folder, in `appData.pages` order. These show at the
    /// top level of the sidebar.
    private var ungroupedPages: [Page] {
        appData.pages.filter { page in
            appData.folderContaining(pageID: page.id) == nil
        }
    }

    /// A folder's pages, in the folder's order. Only pages that still
    /// exist are shown, so a stale id (e.g. a page deleted before its
    /// folder entry was cleaned up) never renders or crashes.
    private func folderPages(_ folder: Folder) -> [Page] {
        folder.pageIDs.compactMap { id in
            appData.pages.first { $0.id == id }
        }
    }

    /// Folders a page can be moved into (every folder except the one
    /// it is already in).
    private func moveTargets(for page: Page) -> [Folder] {
        let currentID = appData.folderContaining(pageID: page.id)?.id
        return appData.folders.filter { $0.id != currentID }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if !allTags.isEmpty {
                    tagFilterRow
                    Divider()
                }
                List(selection: $selectedPageID) {
                    if !visibleUngroupedPages.isEmpty {
                        Section(header: Text("Pages")) {
                            ForEach(visibleUngroupedPages) { page in
                                pageRow(page)
                            }
                        }
                    }

                    if !visibleFolders.isEmpty {
                        Section(header: Text("Folders")) {
                            ForEach(visibleFolders) { folder in
                                folderRow(folder)
                                if folder.isExpanded {
                                    ForEach(visibleFolderPages(folder)) { page in
                                        pageRow(page)
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                        }
                    }

                    Button("Add Page") {
                        showingTemplatePicker = true
                    }
                    .sheet(isPresented: $showingTemplatePicker) {
                        VStack(spacing: 20) {
                            Text("Create Page")
                                .font(.title2)

                            TextField("Title", text: $newTitle)
                                .textFieldStyle(.roundedBorder)

                            Picker("Template", selection: $chosenTemplate) {
                                ForEach(Template.allCases) { tmpl in
                                    Text(tmpl.rawValue).tag(tmpl)
                                }
                            }
                            .pickerStyle(.inline)

                            Button("Create") {
                                var finalTitle = newTitle
                                let now = Date()

                                if appData.pages.contains(where: { $0.title == finalTitle }) {
                                    finalTitle += " - \(AppData.formatTimestamp(now))"
                                }
                                let newPage = Page(
                                    id: UUID(),
                                    title: finalTitle,
                                    createdAt: now,
                                    blocks: chosenTemplate.initialBlocks
                                )
                                appData.pages.append(newPage)
                                selectedPageID = newPage.id
                                showingTemplatePicker = false
                                newTitle = "New Page"
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }

                    Button("New Folder") {
                        newFolderName = "New Folder"
                        showingNewFolderAlert = true
                    }
                }
                .alert("New Folder", isPresented: $showingNewFolderAlert) {
                    TextField("Name", text: $newFolderName)
                    Button("Create") {
                        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let folder = Folder(
                            id: UUID(),
                            name: name.isEmpty ? "New Folder" : name,
                            pageIDs: [],
                            isExpanded: true
                        )
                        appData.folders.append(folder)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Enter a name for the new folder.")
                }
                .alert("Rename Folder", isPresented: $showingRenameAlert) {
                    TextField("Name", text: $renameText)
                    Button("Rename") {
                        if let folder = folderToRename {
                            let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                appData.renameFolder(id: folder.id, to: name)
                            }
                        }
                        folderToRename = nil
                    }
                    Button("Cancel", role: .cancel) {
                        folderToRename = nil
                    }
                } message: {
                    Text("Enter a new name for the folder.")
                }
            }

            // Undo Snackbar
            if undoCoordinator.showingUndo {
                undoSnackbar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .navigationTitle("Workspace")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingThemeSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Appearance settings")
            }
        }
        .sheet(isPresented: $showingThemeSettings) {
            ThemeSettingsView(appData: appData)
        }
    }

    // MARK: - Tag Filter
    /// A horizontally scrollable row of tag chips ("All" + one per
    /// tag in use) at the top of the sidebar. Tapping a tag filters
    /// the page list to pages carrying it; tapping the same tag again
    /// (or "All") clears the filter. The filter is view-only state —
    /// it does not change the data, and it does not clear the
    /// selection: if the selected page is filtered out of the list,
    /// it stays selected and the detail pane still shows it.
    private var tagFilterRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tagFilterChip("All", isSelected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(allTags, id: \.self) { tag in
                        tagFilterChip("#\(tag)", isSelected: selectedTag == tag) {
                            selectedTag = (selectedTag == tag) ? nil : tag
                        }
                    }
                }
                .padding(.horizontal)
            }
            if let tag = selectedTag {
                HStack(spacing: 8) {
                    Text("Filtered by #\(tag)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Clear") { selectedTag = nil }
                        .font(.caption)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    private func tagFilterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? appData.theme.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    /// A page row: tap to select it, swipe to delete it, long-press for
    /// the Move to Folder menu.
    private func pageRow(_ page: Page) -> some View {
        NavigationLink(value: page.id) {
            VStack(alignment: .leading) {
                Text(page.title)
                    .themeFont(.body, theme: appData.theme)
                Text(AppData.formatTimestamp(page.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                undoCoordinator.delete(pages: [page])
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            if !moveTargets(for: page).isEmpty {
                Menu("Move to Folder") {
                    ForEach(moveTargets(for: page)) { folder in
                        Button(folder.name) {
                            appData.movePage(page.id, to: folder.id)
                        }
                    }
                }
            }
            if appData.folderContaining(pageID: page.id) != nil {
                Button("Remove from Folder") {
                    appData.movePage(page.id, to: nil)
                }
            }
        }
    }

    /// A folder row: tap the chevron/name to expand or collapse it.
    /// Long-press for Rename / Delete Folder.
    private func folderRow(_ folder: Folder) -> some View {
        Button {
            appData.setFolderExpanded(id: folder.id, isExpanded: !folder.isExpanded)
        } label: {
            HStack {
                Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                    .font(.headline)
                Spacer()
                Text("\(visibleFolderPages(folder).count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                folderToRename = folder
                renameText = folder.name
                showingRenameAlert = true
            }
            Button("Delete Folder", role: .destructive) {
                undoCoordinator.deleteFolder(folder)
            }
        }
    }

    // MARK: - Undo Snackbar
    @ViewBuilder
    private func undoSnackbar() -> some View {
        HStack {
            if let folder = undoCoordinator.deletedFolder {
                Text("Folder \"\(folder.name)\" deleted")
                    .font(.subheadline)
            } else {
                let count = undoCoordinator.deletedPages.count
                Text("\(count == 1 ? "Page" : "\(count) pages") deleted")
                    .font(.subheadline)
            }
            Spacer()
            Button("Undo") {
                appData.undoManager.undo()
            }
            .font(.subheadline).bold()
            .foregroundColor(appData.theme.accentColor)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}

// MARK: - Theme Settings Sheet
/// Settings sheet for the app theme: accent color + font style.
/// Changes apply immediately (the theme is @Published on AppData,
/// so the UI updates live) and persist to UserDefaults via the
/// theme's didSet. Reached from the gear button in the sidebar
/// toolbar.
struct ThemeSettingsView: View {
    @ObservedObject var appData: AppData
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Accent Color") {
                    HStack(spacing: 16) {
                        ForEach(ThemeAccent.allCases, id: \.self) { accent in
                            Button {
                                appData.theme.accent = accent
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 32, height: 32)
                                    if appData.theme.accent == accent {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                            .font(.caption.bold())
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.displayName)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Font Style") {
                    Picker("Font Style", selection: $appData.theme.font) {
                        ForEach(ThemeFont.allCases, id: \.self) { font in
                            Text(font.displayName).tag(font)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Reset to Default") {
                        appData.theme = .standard
                    }
                    .foregroundStyle(.red)
                } footer: {
                    Text("Default: blue accent, System font.")
                }
            }
            .navigationTitle("Appearance")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
