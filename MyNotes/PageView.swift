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
    @State private var editingBlockID: UUID?

    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                TextField("Title", text: $page.title)
                    .font(.largeTitle)
                Text("Created: \(AppData.formatTimestamp(page.createdAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom)

            // Fixed: Use ForEach with indices + .onDelete on List
            List {
                ForEach(page.blocks.indices, id: \.self) { index in
                    blockView(for: index)
                }
                .onDelete { indices in
                    page.blocks.remove(atOffsets: indices)
                }
                .onMove { indices, newOffset in
                    page.blocks.move(fromOffsets: indices, toOffset: newOffset)
                }
            }

            HStack {
                Picker("Add Layout", selection: $selectedBlockType) {
                    ForEach(BlockType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                .pickerStyle(.menu)

                if selectedBlockType != .calendar {
                    TextField("Content...", text: $newContent)
                }

                Button("Add") {
                    addBlock()
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(page.title)
        .sheet(isPresented: $showingEventSheet) {
            EventEditSheet(
                date: selectedDate ?? Date(),
                text: $eventText,
                onSave: { text in
                    guard let blockID = editingBlockID,
                          let pageIndex = appData.pages.firstIndex(where: { $0.id == page.id }),
                          let blockIndex = appData.pages[pageIndex].blocks.firstIndex(where: { $0.id == blockID }) else { return }
                    
                    let dateKey = selectedDate?.startOfDay ?? Date().startOfDay
                    if text.isEmpty {
                        appData.pages[pageIndex].blocks[blockIndex].events.removeValue(forKey: dateKey)
                    } else {
                        appData.pages[pageIndex].blocks[blockIndex].events[dateKey] = text
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func blockView(for index: Int) -> some View {
        let block = $page.blocks[index]
        switch block.wrappedValue.type {
        case .text:
            TextEditor(text: block.content)
                .frame(minHeight: 100)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        case .todo:
            HStack {
                // Fixed: Use iOS-compatible checkbox
                Image(systemName: block.wrappedValue.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundColor(.blue)
                    .onTapGesture {
                        page.blocks[index].isCompleted.toggle()
                    }
                TextField("Task", text: block.content)
            }
        case .calendar:
            calendarBlockView(block: block)
        }
    }

    private func calendarBlockView(block: Binding<Block>) -> some View {
        VStack(alignment: .leading) {
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
                        .buttonStyle(.borderless)
                    }
                }
            }
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
        editingBlockID = block.id
        showingEventSheet = true
    }

    private func generateDaysInMonth(for date: Date) -> [Date?] {
        guard
            let monthInterval = Calendar.current.dateInterval(of: .month, for: date),
            let daysInMonth = Calendar.current.range(of: .day, in: .month, for: date)?.count
        else { return [] }

        let firstDay = monthInterval.start
        let weekday = Calendar.current.component(.weekday, from: firstDay) - 1
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
