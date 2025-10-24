//  SidebarView.swift
import SwiftUI
import Foundation

struct SidebarView: View {
    @ObservedObject var appData: AppData
    
    @State private var showingTemplatePicker = false
    @State private var chosenTemplate: Template = .blank
    
    var body: some View {
        List {
            Section(header: Text("Pages")) {
                ForEach($appData.pages) { $page in
                    NavigationLink(destination: PageView(page: $page, appData: appData)) {
                        Text(page.title)
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
                    Text("Choose a template")
                        .font(.title2)
                    
                    Picker("Template", selection: $chosenTemplate) {
                        ForEach(Template.allCases) { tmpl in
                            Text(tmpl.rawValue).tag(tmpl)
                        }
                    }
                    .pickerStyle(.inline)
                    
                    Button("Create") {
                        let newPage = Page(
                            id: UUID(),
                            title: "New Page",
                            markdown: chosenTemplate.markdown
                        )
                        appData.pages.append(newPage)
                        showingTemplatePicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .navigationTitle("Workspace")
    }
}
