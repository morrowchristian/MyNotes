//
//  PageView.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import SwiftUI

struct PageView: View {
    let page: Page
    @ObservedObject var appData: AppData
    @State private var newBlockContent = ""
    @State private var newBlockType: BlockType = .text
    
    var body: some View {
        VStack {
            Text(page.title).font(.largeTitle)
            List {
                ForEach(page.blocks) { block in
                    switch block.type {
                    case .text:
                        Text(block.content)
                    case .todo:
                        Toggle(block.content, isOn: Binding(
                            get: { block.isCompleted },
                            set: { newValue in
                                if let pageIndex = appData.pages.firstIndex(where: { $0.id == page.id }),
                                   let blockIndex = appData.pages[pageIndex].blocks.firstIndex(where: { $0.id == block.id }) {
                                    appData.pages[pageIndex].blocks[blockIndex].isCompleted = newValue
                                    appData.saveData()
                                }
                            }
                        ))
                    case .calendarEvent:
                        HStack {
                            DatePicker("", selection: .constant(Date()), displayedComponents: .date)
                            Text(block.content)
                        }
                    }
                }
            }
            HStack {
                Picker("Type", selection: $newBlockType) {
                    Text("Text").tag(BlockType.text)
                    Text("To-Do").tag(BlockType.todo)
                    Text("Event").tag(BlockType.calendarEvent)
                }
                TextField("Add block...", text: $newBlockContent)
                Button("Add") {
                    if !newBlockContent.isEmpty {
                        let newBlock: Block
                        if newBlockType == .todo {
                            newBlock = Block(id: UUID(), type: newBlockType, content: newBlockContent, isCompleted: false)
                        } else {
                            newBlock = Block(id: UUID(), type: newBlockType, content: newBlockContent)
                        }
                        if let index = appData.pages.firstIndex(where: { $0.id == page.id }) {
                            appData.pages[index].blocks.append(newBlock)
                            appData.saveData()
                            newBlockContent = ""
                        }
                    }
                }
            }.padding()
        }
    }
}

