//  SidebarView.swift
import SwiftUI
import Foundation

struct SidebarView: View {
    @ObservedObject var appData: AppData
    @Binding var selectedPageID: UUID?
    
    @State private var showingTemplatePicker = false
    @State private var chosenTemplate: Template = .blank
    @State private var newTitle = "New Page"
    
    var body: some View {
        List(selection: $selectedPageID) {
            Section(header: Text("Pages")) {
                ForEach(appData.pages) { page in
                    NavigationLink(value: page.id) {
                        VStack(alignment: .leading) {
                            Text(page.title)
                            Text(AppData.formatTimestamp(page.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indices in
                    appData.pages.remove(atOffsets: indices)
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
        }
        .navigationTitle("Workspace")
    }
}
