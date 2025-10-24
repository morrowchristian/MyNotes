//  PageView.swift
import SwiftUI

struct PageView: View {
    @Binding var page: Page
    @ObservedObject var appData: AppData
    
    @State private var editedTitle: String
    @State private var editedMarkdown: String
    @State private var isEditing = true
    @State private var showingGuides = false
    
    init(page: Binding<Page>, appData: AppData) {
        self._page = page
        self.appData = appData
        _editedTitle = State(initialValue: page.wrappedValue.title)
        _editedMarkdown = State(initialValue: page.wrappedValue.markdown)
    }
    
    var body: some View {
        VStack {
            TextField("Title", text: $editedTitle, onCommit: save)
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .padding(.bottom)
            
            if isEditing {
                TextEditor(text: $editedMarkdown)
                    .font(.body.monospaced())
                    .onChange(of: editedMarkdown) { _ in save() }
            } else {
                ScrollView {
                    Text(editedMarkdown)
                        .markdownTextStyle()
                        .padding()
                }
            }
            
            HStack {
                Button(isEditing ? "Preview" : "Edit") {
                    isEditing.toggle()
                }
                Spacer()
                Button("Guides") { showingGuides = true }
            }
            .padding()
        }
        .navigationTitle(page.title)
        .sheet(isPresented: $showingGuides) {
            MarkdownGuideSheet()
        }
    }
    
    private func save() {
        page.title = editedTitle
        page.markdown = editedMarkdown
    }
}

// Robust markdown rendering (works on iOS 16+)
extension Text {
    func markdownTextStyle() -> some View {
        self
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownGuideSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                Text("""
                # Markdown Quick Guide

                ## Headers
                `# Big Title` → largest  
                `## Smaller` → smaller  

                ## Lists
                `- Milk`  
                `1. First step`

                ## Checklists
                `- [ ] Not done`  
                `- [x] Done`

                ## Style
                `**bold**` → **bold**  
                `*italic*` → *italic*

                ## Links
                `[Apple](https://apple.com)`

                ## Tables (for calendars!)
                | Date       | Event          |
                |------------|----------------|
                | 2025-10-25 | Team meeting   |
                | 2025-11-01 | Doctor visit   |

                ## Date Headings
                `## 2025-10-25` → auto-group events
                """)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Markdown Guide")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { }
                }
            }
        }
    }
}
