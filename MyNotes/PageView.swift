//  PageView.swift
import SwiftUI

struct PageView: View {
    @Binding var page: Page
    @ObservedObject var appData: AppData
    
    @State private var selectedBlockType: BlockType = .text
    @State private var newContent: String = ""
    @State private var currentMonth = Date()
    @State private var showingEventSheet = false
    @State private var selectedDate: Date?
    @State private var eventText: String = ""
    @State private var editingBlock: Block?

    var body: some View {
        VStack {
            TextField("Title", text: $page.title)
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .padding(.bottom)
            
            List {
                ForEach($page.blocks) { $block in
                    blockView(for: $block)
                }
                .onDelete { indices in
                    page.blocks.remove(atOffsets: indices)
                }
            }
            
            HStack {
                Picker("Add Layout", selection: $selectedBlockType) {
                    ForEach(BlockType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                if selectedBlockType != .calendar {
                    TextField("Content...", text: $newContent)
                }
                
                Button("Add") {
                    addBlock()
                }
            }
            .padding()
        }
        .navigationTitle(page.title)
        .sheet(isPresented: $showingEventSheet) {
            EventEditSheet(
                date: selectedDate!,
                text: $eventText,
                onSave: { text in
                    guard let block = editingBlock else { return }
                    let dateKey = selectedDate!.startOfDay
                    if text.isEmpty {
                        if var pageBlocks = appData.pages.first(where: { $0.id == page.id })?.blocks {
                            if let idx = pageBlocks.firstIndex(where: { $0.id == block.id }) {
                                pageBlocks[idx].events.removeValue(forKey: dateKey)
                                if let pageIdx = appData.pages.firstIndex(where: { $0.id == page.id }) {
                                    appData.pages[pageIdx].blocks = pageBlocks
                                }
                            }
                        }
                    } else {
                        if var pageBlocks = appData.pages.first(where: { $0.id == page.id })?.blocks {
                            if let idx = pageBlocks.firstIndex(where: { $0.id == block.id }) {
                                pageBlocks[idx].events[dateKey] = text
                                if let pageIdx = appData.pages.firstIndex(where: { $0.id == page.id }) {
                                    appData.pages[pageIdx].blocks = pageBlocks
                                }
                            }
                        }
                    }
                    editingBlock = nil
                    selectedDate = nil
                    eventText = ""
                }
            )
        }
    }
    
    @ViewBuilder
    private func blockView(for block: Binding<Block>) -> some View {
        switch block.wrappedValue.type {
        case .text:
            TextEditor(text: block.content)
        case .todo:
            Toggle(block.wrappedValue.content, isOn: block.isCompleted)
        case .calendar:
            calendarBlockView(block: block)
        }
    }
    
    private func calendarBlockView(block: Binding<Block>) -> some View {
        VStack {
            HStack {
                Button("<") {
                    currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth)!
                }
                Spacer()
                Text(currentMonth, format: .dateTime.year().month())
                    .font(.headline)
                Spacer()
                Button(">") {
                    currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth)!
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
                        let hasEvent = block.wrappedValue.events[date.startOfDay] != nil
                        Button {
                            openEventEditor(for: date, in: block.wrappedValue)
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.system(size: 14))
                                if hasEvent {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 6, height: 6)
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
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func addBlock() {
        var newBlock = Block(id: UUID(), type: selectedBlockType)
        if selectedBlockType != .calendar {
            newBlock.content = newContent
        }
        page.blocks.append(newBlock)
        newContent = ""
    }
    
    private func openEventEditor(for date: Date, in block: Block) {
        selectedDate = date
        eventText = block.events[date.startOfDay] ?? ""
        editingBlock = block
        showingEventSheet = true
    }
    
    private func generateDaysInMonth(for date: Date) -> [Date?] {
        guard
            let monthInterval = Calendar.current.dateComponents([.year, .month], from: date).date,
            let daysInMonth = Calendar.current.range(of: .day, in: .month, for: monthInterval)
        else { return [] }
        
        let firstDay = monthInterval
        let weekday = Calendar.current.component(.weekday, from: firstDay) - 1
        let days = daysInMonth.compactMap { day -> Date? in
            Calendar.current.date(bySetting: .day, value: day, of: monthInterval)
        }
        
        return Array(repeating: nil, count: weekday) + days
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
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
                Section("Event for \(date.formatted(date: .abbreviated, time: .omitted))") {
                    TextField("Enter event...", text: $text)
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

// MARK: - Date Extension
extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
