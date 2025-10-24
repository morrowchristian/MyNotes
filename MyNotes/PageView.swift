//
//  PageView.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import SwiftUI

struct PageView: View {
    @Binding var page: Page
    @ObservedObject var appData: AppData
    @State private var newBlockContent = ""
    @State private var newBlockType: BlockType = .text
    @State private var newEventDate = Date()
    
    var body: some View {
        VStack {
            TextField("Title", text: $page.title)
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .padding(.bottom)
            
            List {
                ForEach($page.blocks) { $block in
                    switch block.type {
                    case .text:
                        Text(block.content)
                    case .todo:
                        Toggle(block.content, isOn: $block.isCompleted)
                    case .calendarEvent:
                        HStack {
                            if let date = block.date {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                            }
                            Text(block.content)
                        }
                    }
                }
                .onDelete { indices in
                    page.blocks.remove(atOffsets: indices)
                }
            }
            
            Divider()
            
            HStack {
                Picker("Type", selection: $newBlockType) {
                    ForEach(BlockType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                TextField("Add block...", text: $newBlockContent)
                
                if newBlockType == .calendarEvent {
                    DatePicker("", selection: $newEventDate, displayedComponents: .date)
                        .labelsHidden()
                }
                
                Button("Add") {
                    guard !newBlockContent.isEmpty else { return }
                    let newBlock = Block(
                        id: UUID(),
                        type: newBlockType,
                        content: newBlockContent,
                        isCompleted: newBlockType == .todo ? false : false,
                        date: newBlockType == .calendarEvent ? newEventDate : nil
                    )
                    page.blocks.append(newBlock)
                    newBlockContent = ""
                }
            }
            .padding()
        }
        .navigationTitle(page.title)
    }
}
