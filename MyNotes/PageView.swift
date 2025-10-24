//  PageView.swift
import SwiftUI
import Combine

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
    @State private var editingBlockID: UUID?

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
                        Label(type.rawValue.capitalized, systemImage: icon(for: type))
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)

                if selectedBlockType != .calendar {
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
                onSave: { text in
                    saveEvent(text: text)
                }
            )
        }
        .onShake {
            if appData.undoManager.canUndo {
                appData.undoManager.undo()
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
        }
    }

    // MARK: - Calendar Block
    private func calendarBlockView(block: Binding<Block>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("<") {
                    currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth)!
                }
                .font(.title2)
                Spacer()
                Text(currentMonth, format: .dateTime.year().month())
                    .font(.headline)
                Spacer()
                Button(">") {
                    currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth)!
                }
                .font(.title2)
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
                        let hasEvent = block.wrappedValue.events[date.startOfDay] != nil
                        Button {
                            openEventEditor(for: date, in: block.wrappedValue)
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.system(size: 14))
                                if hasEvent {
                                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isToday(date) ? Color.blue.opacity(0.2) : Color.clear)
                            )
                        }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            .padding(.horizontal)

            if !block.wrappedValue.events.isEmpty {
                Divider()
                Text("Events")
                    .font(.subheadline)
                    .padding(.top)
                ForEach(Array(block.wrappedValue.events.sorted(by: { $0.key < $1.key })), id: \.key) { date, note in
                    HStack {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                        Text(note)
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

    // MARK: - Add Block
    private func addBlock() {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedBlockType == .calendar else { return }
        
        var newBlock = Block(id: UUID(), type: selectedBlockType)
        if selectedBlockType != .calendar {
            newBlock.content = trimmed
        }
        page.blocks.append(newBlock)
        newContent = ""
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
    private func openEventEditor(for date: Date, in block: Block) {
        selectedDate = date
        eventText = block.events[date.startOfDay] ?? ""
        editingBlockID = block.id
        showingEventSheet = true
    }

    private func saveEvent(text: String) {
        guard let blockID = editingBlockID,
              let pageIndex = appData.pages.firstIndex(where: { $0.id == page.id }),
              let blockIndex = appData.pages[pageIndex].blocks.firstIndex(where: { $0.id == blockID }),
              let date = selectedDate else { return }

        let key = date.startOfDay
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            appData.pages[pageIndex].blocks[blockIndex].events.removeValue(forKey: key)
        } else {
            appData.pages[pageIndex].blocks[blockIndex].events[key] = trimmed
        }
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
        }
    }
}

// MARK: - Event Edit Sheet
struct EventEditSheet: View {
    let date: Date
    @Binding var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Event on \(date.formatted(date: .abbreviated, time: .omitted))") {
                    TextField("Enter event...", text: $text, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle("Edit Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
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
