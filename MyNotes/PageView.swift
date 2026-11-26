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
    
    @StateObject private var undoCoordinator: PageUndoCoordinator
    
    // Initialize coordinator
    init(page: Binding<Page>, appData: AppData) {
        self._page = page
        self.appData = appData
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

    var body: some View {
        VStack {
            // Title + Created At
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $page.title)
                    .font(.largeTitle)
                    .bold()
                Text("Created: \(AppData.formatTimestamp(page.createdAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Block List
            List {
                ForEach(page.blocks.indices, id: \.self) { index in
                    blockView(for: index)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
    }

    // MARK: - Block View
    @ViewBuilder
    private func blockView(for index: Int) -> some View {
        let block = $page.blocks[index]
        switch block.wrappedValue.type {
        case .text:
            TextEditor(text: block.content)
                .frame(minHeight: 100)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(4)
        case .todo:
            HStack {
                Image(systemName: block.wrappedValue.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundColor(.blue)
                    .font(.title2)
                    .onTapGesture {
                        page.blocks[index].isCompleted.toggle()
                    }
                TextField("Task", text: block.content)
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
                    .italic()
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
            }
            .padding(10)
            .background(Color(.systemGray6))
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
        case .toggle:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        page.blocks[index].isExpanded.toggle()
                    } label: {
                        Image(systemName: block.wrappedValue.isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.blue)
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
            .background(Color(.systemGray6))
            .cornerRadius(12)
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
                        .foregroundColor(.secondary)
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
                                if let event = event {
                                    Circle().fill(event.color.color).frame(width: 8, height: 8)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isToday(date) ? Color.blue.opacity(0.2) : Color.clear)
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
                            .foregroundStyle(.secondary)
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
        .background(Color(.systemGray6))
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
                        .foregroundStyle(.secondary)
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
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Add Block
    private func addBlock() {
        // Image blocks are added from the photo picker, not from typed content.
        if selectedBlockType == .image {
            showingImagePicker = true
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
            .foregroundColor(.blue)
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
            eventColor = .blue
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
