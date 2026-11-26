//  PageView.swift
import SwiftUI
import Combine
import PhotosUI

// MARK: - Event Color
extension EventColor {
    /// The SwiftUI color for this event color.
    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        }
    }
}

// MARK: - Undo Coordinator (Class)
final class PageUndoCoordinator: ObservableObject {
    @Published var showingUndo = false
    @Published var deletedBlocks: [Block] = []
    @Published var deletedIndices: IndexSet = []
    
    private var pageBinding: Binding<Page>
    private let undoManager: UndoManager
    
    init(page: Binding<Page>, undoManager: UndoManager) {
        self.pageBinding = page
        self.undoManager = undoManager
    }
    
    func delete(at offsets: IndexSet) {
        deletedBlocks = offsets.map { pageBinding.wrappedValue.blocks[$0] }
        deletedIndices = offsets
        
        undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.performUndo()
        }
        
        withAnimation {
            pageBinding.wrappedValue.blocks.remove(atOffsets: offsets)
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
            for (block, index) in zip(deletedBlocks, deletedIndices) {
                pageBinding.wrappedValue.blocks.insert(block, at: index)
            }
            showingUndo = false
        }
    }
}

// MARK: - Main View
struct PageView: View {
    @Binding var page: Page
    @ObservedObject var appData: AppData
    // The selected page, shared with MainView/SidebarView. A link block
    // sets this to its target page's id to navigate to it.
    @Binding var selectedPageID: UUID?
    // Global Search (roadmap item 9): the query typed in the sidebar.
    // Owned by MainView; read-only here. Matching blocks are tinted
    // so the user can see where the query occurs in this page.
    let searchQuery: String

    @StateObject private var undoCoordinator: PageUndoCoordinator

    // Initialize coordinator
    init(page: Binding<Page>, appData: AppData, selectedPageID: Binding<UUID?>, searchQuery: String) {
        self._page = page
        self.appData = appData
        self._selectedPageID = selectedPageID
        self.searchQuery = searchQuery
        let coordinator = PageUndoCoordinator(page: page, undoManager: appData.undoManager)
        self._undoCoordinator = StateObject(wrappedValue: coordinator)
    }

    @State private var selectedBlockType: BlockType = .text
    @State private var newContent: String = ""
    @State private var currentMonth = Date()
    @State private var showingEventSheet = false
    @State private var selectedDate: Date?
    @State private var eventText: String = ""
    @State private var eventColor: EventColor = .blue
    @State private var editingBlockID: UUID?
    @State private var previewDate: Date?
    @State private var previewBlockID: UUID?
    @State private var showingImagePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingLinkPicker = false
    // The text in the "Add tag..." field.
    @State private var newTagText = ""
    // @ mention state: which text block has an active "@" and the
    // query typed after it. Nil/empty when no mention is active.
    @State private var mentionBlockID: UUID?
    @State private var mentionQuery: String = ""
    // Which text block's editor has focus. When focus leaves the block
    // with the active @ mention, the suggestions dismiss.
    @FocusState private var focusedTextBlockID: UUID?

    /// The active Global Search query, trimmed. Empty when the user
    /// is not searching (a query of only whitespace counts as no
    /// search). Used to tint matching blocks in the list below.
    private var activeSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack {
            // Title + Created At
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $page.title)
                    .themeFont(.largeTitle, theme: appData.theme)
                    .bold()
                Text("Created: \(AppData.formatTimestamp(page.createdAt))")
                    .font(.subheadline)
                    .foregroundStyle(Color.appMutedText)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Tags
            tagEditor
                .padding(.top, 4)

            // Block List
            List {
                ForEach(page.blocks.indices, id: \.self) { index in
                    blockView(for: index)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        // Global Search highlight: a block whose text
                        // matches the query gets a light yellow row
                        // tint, so the match is visible without
                        // opening it. TextEditor cannot show attributed
                        // text, so the match is highlighted at the
                        // block level (a tint), not inside the editor.
                        // No query means no tint.
                        .listRowBackground(
                            blockMatchesSearch(page.blocks[index], query: activeSearchQuery)
                                ? Color.yellow.opacity(0.2)
                                : Color.clear
                        )
                }
                .onDelete { indices in
                    undoCoordinator.delete(at: indices)
                }
                .onMove { indices, newOffset in
                    page.blocks.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(PlainListStyle())

            // Add Block Bar
            HStack {
                Picker("Add Layout", selection: $selectedBlockType) {
                    ForEach(BlockType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: icon(for: type))
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)

                if !selectedBlockType.hidesContentInput {
                    TextField("Content...", text: $newContent)
                        .textFieldStyle(.roundedBorder)
                }

                Button("Add") {
                    addBlock()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(.systemBackground))

            Spacer()

            // Undo Snackbar
            if undoCoordinator.showingUndo {
                undoSnackbar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Export (roadmap item 10): one entry point, three options
            // for the current page — Markdown, PDF, or Print.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        exportAsMarkdown()
                    } label: {
                        Label("Export as Markdown", systemImage: "doc.text")
                    }
                    Button {
                        exportAsPDF()
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        printPage()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingEventSheet) {
            EventEditSheet(
                date: selectedDate ?? Date(),
                text: $eventText,
                color: $eventColor,
                onSave: { text, color in
                    saveEvent(text: text, color: color)
                }
            )
        }
        .onShake {
            if appData.undoManager.canUndo {
                appData.undoManager.undo()
            }
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let jpegData = downscaledJPEGData(from: data) {
                    await MainActor.run {
                        page.blocks.append(Block(id: UUID(), type: .image, imageData: jpegData))
                        selectedPhoto = nil
                    }
                } else {
                    await MainActor.run { selectedPhoto = nil }
                }
            }
        }
        .sheet(isPresented: $showingLinkPicker) {
            PagePickerSheet(
                pages: appData.pages.filter { $0.id != page.id },
                onPick: { target in
                    page.blocks.append(Block(id: UUID(), type: .link, content: target.title, linkedPageID: target.id))
                }
            )
        }
        .onChange(of: focusedTextBlockID) { _, newValue in
            // Focus moved away from the block with the active @ mention
            // (to another block, or nowhere) — dismiss the suggestions.
            if newValue != mentionBlockID {
                clearMention()
            }
        }
    }

    // MARK: - Tag Editor
    /// The page's tags as chips, plus a compact field to add one.
    /// Tags are shown with a "#" prefix; the × on a chip removes it.
    /// Adding normalizes the text (lowercase, no "#", first word
    /// only) and ignores duplicates and empties. Mutating page.tags
    /// writes through the page binding to appData.pages, so tags
    /// persist with the page (same mechanism as the title/blocks).
    private var tagEditor: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(page.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(.caption)
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(Color.appMutedText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(10)
                }
                TextField("Add tag...", text: $newTagText)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onSubmit { addTag() }
                Button("Add") { addTag() }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
        }
    }

    private func addTag() {
        guard let tag = Page.normalizedTag(newTagText) else {
            newTagText = ""
            return
        }
        if !page.tags.contains(tag) {
            page.tags.append(tag)
        }
        newTagText = ""
    }

    private func removeTag(_ tag: String) {
        page.tags.removeAll { $0 == tag }
    }

    // MARK: - Block View
    @ViewBuilder
    private func blockView(for index: Int) -> some View {
        let block = $page.blocks[index]
        switch block.wrappedValue.type {
        case .text:
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: block.content)
                    .themeFont(.body, theme: appData.theme)
                    .frame(minHeight: 100)
                    .background(Color.appCardBackground)
                    .cornerRadius(12)
                    .padding(4)
                    .focused($focusedTextBlockID, equals: block.wrappedValue.id)
                    .onChange(of: block.wrappedValue.content) { _, newValue in
                        updateMention(for: newValue, in: block.wrappedValue.id)
                    }
                // @ mention suggestions for this block, if it has an
                // active "@" being typed.
                if mentionBlockID == block.wrappedValue.id {
                    mentionSuggestionsView(at: index)
                }
            }
        case .todo:
            HStack {
                Image(systemName: block.wrappedValue.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundColor(appData.theme.accentColor)
                    .font(.title2)
                    .onTapGesture {
                        page.blocks[index].isCompleted.toggle()
                    }
                TextField("Task", text: block.content)
                    .themeFont(.body, theme: appData.theme)
                    .strikethrough(block.wrappedValue.isCompleted)
            }
        case .calendar:
            calendarBlockView(block: block)
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 4)
                TextEditor(text: block.content)
                    .themeFont(.body, theme: appData.theme)
                    .italic()
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
            }
            .padding(10)
            .background(Color.appCardBackground)
            .cornerRadius(12)
        case .code:
            TextEditor(text: block.content)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Color(white: 0.92))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(red: 0.11, green: 0.12, blue: 0.15))
                .cornerRadius(12)
        case .divider:
            Divider()
                .padding(.vertical, 8)
        case .image:
            if let data = block.wrappedValue.imageData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
            } else {
                Text("Image unavailable")
                    .font(.subheadline)
                    .foregroundStyle(Color.appMutedText)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color.appCardBackground)
                    .cornerRadius(12)
            }
        case .toggle:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        page.blocks[index].isExpanded.toggle()
                    } label: {
                        Image(systemName: block.wrappedValue.isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(appData.theme.accentColor)
                            .font(.subheadline)
                            .frame(minWidth: 28, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    TextField("Toggle title", text: block.content)
                        .font(.headline)
                }
                if block.wrappedValue.isExpanded {
                    TextEditor(text: block.detail)
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                }
            }
            .padding(10)
            .background(Color.appCardBackground)
            .cornerRadius(12)
        case .link:
            linkBlockView(block: block)
        }
    }

    // MARK: - Calendar Block
    private func calendarBlockView(block: Binding<Block>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth)!
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
                Spacer()
                Text(currentMonth, format: .dateTime.year().month())
                    .font(.headline)
                Spacer()
                Button {
                    currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth)!
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.horizontal)

            let days = generateDaysInMonth(for: currentMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .foregroundColor(Color.appMutedText)
                }
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        let event = block.wrappedValue.events[date.startOfDay]
                        Button {
                            handleDateTap(for: date, in: block.wrappedValue)
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.system(size: 16))
                                    .fontWeight(isToday(date) ? .bold : .regular)
                                    .foregroundStyle(.primary)
                                if let event = event {
                                    Circle().fill(event.color.color).frame(width: 8, height: 8)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isToday(date) ? Color.appTodayHighlight : Color.clear)
                            )
                        }
                    } else {
                        Color.clear.frame(height: 54)
                    }
                }
            }
            .padding(.horizontal)

            // Event preview — shown when a date with an event is tapped.
            if let previewDay = previewDate,
               previewBlockID == block.wrappedValue.id,
               let event = block.wrappedValue.events[previewDay] {
                eventPreviewCard(date: previewDay, event: event, block: block)
            }

            if !block.wrappedValue.events.isEmpty {
                Divider()
                Text("Events")
                    .font(.subheadline)
                    .padding(.top)
                ForEach(Array(block.wrappedValue.events.sorted(by: { $0.key < $1.key })), id: \.key) { date, event in
                    HStack {
                        Circle().fill(event.color.color).frame(width: 8, height: 8)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(Color.appMutedText)
                        Text(event.text)
                        Spacer()
                        Button("Edit") {
                            openEventEditor(for: date, in: block.wrappedValue)
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Event Preview Card
    @ViewBuilder
    private func eventPreviewCard(date: Date, event: CalendarEvent, block: Binding<Block>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(event.color.color).frame(width: 10, height: 10)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).bold()
                Spacer()
                Button {
                    previewDate = nil
                    previewBlockID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Color.appMutedText)
                }
                .buttonStyle(.borderless)
            }
            Text(event.text)
                .font(.body)
            HStack(spacing: 12) {
                Button("Edit") {
                    openEventEditor(for: date, in: block.wrappedValue)
                }
                .buttonStyle(.bordered)
                Button("Delete") {
                    deleteEvent(for: date, in: block.wrappedValue.id)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color.appElevatedBackground)
        .cornerRadius(12)
    }

    // MARK: - Add Block
    private func addBlock() {
        // Image blocks are added from the photo picker, not from typed content.
        if selectedBlockType == .image {
            showingImagePicker = true
            return
        }

        // Link blocks are added from the page picker, not from typed content.
        if selectedBlockType == .link {
            showingLinkPicker = true
            return
        }

        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedBlockType == .calendar || selectedBlockType == .divider else { return }
        
        var newBlock = Block(id: UUID(), type: selectedBlockType)
        if selectedBlockType != .calendar && selectedBlockType != .divider {
            newBlock.content = trimmed
        }
        page.blocks.append(newBlock)
        newContent = ""
    }

    // MARK: - Image Block
    /// Downscales an image to a max dimension of 1200px and compresses
    /// it to JPEG, so image blocks stay small in the saved JSON.
    private func downscaledJPEGData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1200
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    // MARK: - Link Block
    /// A link block: a tappable row that navigates to the target page.
    /// If the target page was deleted, it degrades to a muted,
    /// non-tappable "(deleted)" row instead of crashing.
    @ViewBuilder
    private func linkBlockView(block: Binding<Block>) -> some View {
        let resolved = block.wrappedValue.linkedPageID
            .flatMap { id in appData.pages.first(where: { $0.id == id }) }
        if let target = resolved {
            Button {
                selectedPageID = target.id
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(appData.theme.accentColor)
                    Text(block.wrappedValue.content.isEmpty ? target.title : block.wrappedValue.content)
                        .foregroundStyle(appData.theme.accentColor)
                        .underline()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.appMutedText)
                }
                .padding(12)
                .background(Color.appCardBackground)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(Color.appMutedText)
                Text("\(block.wrappedValue.content) (deleted)")
                    .foregroundStyle(Color.appMutedText)
                Spacer()
            }
            .padding(12)
            .background(Color.appCardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - @ Mentions (Page Links)
    /// Pages whose titles match the @ mention query (case-insensitive),
    /// excluding the current page. An empty query matches all other
    /// pages, so typing "@" alone lists every page to link to.
    private func suggestions(for query: String) -> [Page] {
        let others = appData.pages.filter { $0.id != page.id }
        guard !query.isEmpty else { return others }
        return others.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// Updates the @ mention state for a text block. A mention is
    /// active when the text's last "@" starts a word (at the start of
    /// the text, or preceded by whitespace) and only non-whitespace
    /// characters follow it — i.e. the user is typing a page title
    /// right after "@". The word-boundary check keeps email addresses
    /// like "bob@example.com" from triggering suggestions.
    private func updateMention(for text: String, in blockID: UUID) {
        guard let atIndex = text.lastIndex(of: "@") else {
            clearMention()
            return
        }
        let afterAt = String(text[text.index(after: atIndex)...])
        let precededByBoundary: Bool = {
            if atIndex == text.startIndex { return true }
            return text[text.index(before: atIndex)].isWhitespace
        }()
        let isCleanQuery = !afterAt.contains(where: { $0.isWhitespace })
        if precededByBoundary && isCleanQuery {
            mentionBlockID = blockID
            mentionQuery = afterAt
        } else {
            clearMention()
        }
    }

    private func clearMention() {
        mentionBlockID = nil
        mentionQuery = ""
    }

    /// Inserts a link block right after the text block at `index`,
    /// pointing at `target`, and dismisses the suggestions. The "@..."
    /// text the user typed is left as-is in the text block. The insert
    /// position is clamped so a stale index can never crash.
    private func insertLinkBlock(after index: Int, target: Page) {
        let link = Block(id: UUID(), type: .link, content: target.title, linkedPageID: target.id)
        page.blocks.insert(link, at: min(index + 1, page.blocks.count))
        clearMention()
    }

    /// The @ suggestion list shown under a text block with an active
    /// mention: matching page titles, one tap inserts the link.
    @ViewBuilder
    private func mentionSuggestionsView(at index: Int) -> some View {
        let matches = suggestions(for: mentionQuery)
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(matches) { target in
                    Button {
                        insertLinkBlock(after: index, target: target)
                    } label: {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(Color.appMutedText)
                            Text(target.title)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                    if target.id != matches.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }

    // MARK: - Undo Snackbar
    @ViewBuilder
    private func undoSnackbar() -> some View {
        HStack {
            let count = undoCoordinator.deletedBlocks.count
            Text("\(count == 1 ? "Block" : "\(count) blocks") deleted")
                .font(.subheadline)
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

    // MARK: - Calendar Helpers
    private func handleDateTap(for date: Date, in block: Block) {
        let day = date.startOfDay
        if block.events[day] != nil {
            // This date has an event — show the preview. Tapping the
            // same date again hides it.
            if previewDate == day && previewBlockID == block.id {
                previewDate = nil
                previewBlockID = nil
            } else {
                previewDate = day
                previewBlockID = block.id
            }
        } else {
            // No event yet — go straight to creating one.
            previewDate = nil
            previewBlockID = nil
            openEventEditor(for: date, in: block)
        }
    }

    private func openEventEditor(for date: Date, in block: Block) {
        selectedDate = date
        if let event = block.events[date.startOfDay] {
            eventText = event.text
            eventColor = event.color
        } else {
            eventText = ""
            // A new event defaults to the theme accent color.
            eventColor = appData.theme.accent.eventColor
        }
        editingBlockID = block.id
        showingEventSheet = true
    }

    private func saveEvent(text: String, color: EventColor) {
        guard let blockID = editingBlockID,
              let pageIndex = appData.pages.firstIndex(where: { $0.id == page.id }),
              let blockIndex = appData.pages[pageIndex].blocks.firstIndex(where: { $0.id == blockID }),
              let date = selectedDate else { return }

        let key = date.startOfDay
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            appData.pages[pageIndex].blocks[blockIndex].events.removeValue(forKey: key)
        } else {
            appData.pages[pageIndex].blocks[blockIndex].events[key] = CalendarEvent(text: trimmed, color: color)
        }
    }

    private func deleteEvent(for date: Date, in blockID: UUID) {
        guard let pageIndex = appData.pages.firstIndex(where: { $0.id == page.id }),
              let blockIndex = appData.pages[pageIndex].blocks.firstIndex(where: { $0.id == blockID }) else { return }
        appData.pages[pageIndex].blocks[blockIndex].events.removeValue(forKey: date.startOfDay)
        previewDate = nil
        previewBlockID = nil
    }

    private func generateDaysInMonth(for date: Date) -> [Date?] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: date) else { return [] }
        let firstDay = interval.start
        let weekday = Calendar.current.component(.weekday, from: firstDay) - 1
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 0

        var days: [Date?] = Array(repeating: nil, count: weekday)
        for day in 1...daysInMonth {
            if let dayDate = Calendar.current.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(dayDate)
            }
        }
        return days
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func icon(for type: BlockType) -> String {
        switch type {
        case .text: return "doc.text"
        case .todo: return "checklist"
        case .calendar: return "calendar"
        case .quote: return "quote.opening"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .divider: return "minus"
        case .image: return "photo"
        case .toggle: return "list.bullet"
        case .link: return "link"
        }
    }

    // MARK: - Export (roadmap item 10)
    /// Exports the current page as Markdown and opens the share sheet
    /// so it can be saved to Files, sent, etc.
    @MainActor
    private func exportAsMarkdown() {
        let markdown = MarkdownExporter.markdown(for: page)
        let fileName = "\(ExportFile.safeFileName(from: page.title)).md"
        guard let url = ExportFile.temporaryFileURL(data: Data(markdown.utf8), fileName: fileName) else { return }
        ExportPresenter.presentShareSheet(items: [url])
    }

    /// Renders the current page to PDF and opens the share sheet.
    @MainActor
    private func exportAsPDF() {
        guard let pdfData = PDFExporter.pdfData(for: page) else { return }
        let fileName = "\(ExportFile.safeFileName(from: page.title)).pdf"
        guard let url = ExportFile.temporaryFileURL(data: pdfData, fileName: fileName) else { return }
        ExportPresenter.presentShareSheet(items: [url])
    }

    /// Renders the current page to PDF and opens the print sheet.
    @MainActor
    private func printPage() {
        guard let pdfData = PDFExporter.pdfData(for: page) else { return }
        ExportPresenter.presentPrintSheet(pdfData: pdfData, jobName: page.title)
    }
}

// MARK: - Page Picker Sheet
/// Sheet for picking the target page of a new link block.
/// Shows all pages except the current one.
struct PagePickerSheet: View {
    let pages: [Page]
    let onPick: (Page) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    Text("No other pages to link to yet.")
                        .foregroundStyle(Color.appMutedText)
                        .padding()
                } else {
                    List(pages) { target in
                        Button {
                            onPick(target)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundStyle(Color.appMutedText)
                                Text(target.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link to Page")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Event Edit Sheet
struct EventEditSheet: View {
    let date: Date
    @Binding var text: String
    @Binding var color: EventColor
    let onSave: (String, EventColor) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Event on \(date.formatted(date: .abbreviated, time: .omitted))") {
                    TextField("Enter event...", text: $text, axis: .vertical)
                        .lineLimit(3...)
                }
                Section("Color") {
                    HStack(spacing: 16) {
                        ForEach(EventColor.allCases, id: \.self) { eventColor in
                            Button {
                                color = eventColor
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(eventColor.color)
                                        .frame(width: 32, height: 32)
                                    if color == eventColor {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                            .font(.caption.bold())
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Edit Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text, color)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Shake Gesture
extension View {
    func onShake(_ action: @escaping () -> Void) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                action()
            }
    }
}

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}

// MARK: - Date Extension
extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
