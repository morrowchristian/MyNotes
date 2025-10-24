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
                        Toggle(block.content, isOn: .constant(false)) // Placeholder for now
                    case .calendarEvent:
                        Text("Event: \(block.content)")
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
                        let newBlock = Block(id: UUID(), type: newBlockType, content: newBlockContent)
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

