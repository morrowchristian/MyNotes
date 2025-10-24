//  PageView.swift
import SwiftUI

struct PageView: View {
    @Binding var page: Page
    @ObservedObject var appData: AppData
    
    @State private var selectedBlockType: BlockType = .text
    @State private var newContent: String = ""
    @State private var currentMonth = Date()
    
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
                Button("<") { currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth)! }
                Text(currentMonth, format: .dateTime.year().month())
                Button(">") { currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth)! }
            }
            
            let days = generateDaysInMonth(for: currentMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day).font(.headline)
                }
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        let event = block.wrappedValue.events[date.startOfDay] ?? ""
                        Button(action: { editEvent(for: date, in: block) }) {
                            VStack {
                                Text("\(Calendar.current.component(.day, from: date))")
                                if !event.isEmpty {
                                    Circle().fill(Color.blue).frame(width: 5, height: 5)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(isToday(date) ? Color.gray.opacity(0.3) : Color.clear)
                        }
                    } else {
                        Text("")  // Spacer for offset
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func addBlock() {
        var newBlock = Block(id: UUID(), type: selectedBlockType)
        if selectedBlockType != .calendar {
            newBlock.content = newContent
        }
        page.blocks.append(newBlock)
        newContent = ""
    }
    
    private func editEvent(for date: Date, in block: Binding<Block>) {
        // Simple alert for editing
        let alert = UIAlertController(title: "Event for \(date.formatted(date: .abbreviated, time: .omitted))", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = block.wrappedValue.events[date.startOfDay] ?? ""
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let text = alert.textFields?[0].text ?? ""
            if text.isEmpty {
                block.events.removeValue(forKey: date.startOfDay)
            } else {
                block.events[date.startOfDay] = text
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
    
    private func generateDaysInMonth(for date: Date) -> [Date?] {
        guard let range = Calendar.current.range(of: .day, in: .month, for: date) else { return [] }
        let days = (1...range.count).map { day in
            Calendar.current.date(bySetting: .day, value: day, of: date)!
        }
        let firstWeekday = Calendar.current.component(.weekday, from: days.first!) - 1
        return Array(repeating: nil, count: firstWeekday) + days
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
