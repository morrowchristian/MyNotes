//  SidebarView.swift
import SwiftUI
import Foundation
import Combine

// MARK: - Undo Coordinator (Class)
final class SidebarUndoCoordinator: ObservableObject {
    @Published var showingUndo = false
    @Published var deletedPages: [Page] = []
    @Published var deletedIndices: IndexSet = []

    private var appData: AppData
    private var selectedPageID: Binding<UUID?>
    private var deletedSelectedPageID: UUID?

    init(appData: AppData, selectedPageID: Binding<UUID?>) {
        self.appData = appData
        self.selectedPageID = selectedPageID
    }

    func delete(at offsets: IndexSet) {
        deletedPages = offsets.map { appData.pages[$0] }
        deletedIndices = offsets

        // Remember the selected page if it is among the deleted ones,
        // so Undo can re-select it.
        if let selected = selectedPageID.wrappedValue,
           deletedPages.contains(where: { $0.id == selected }) {
            deletedSelectedPageID = selected
        } else {
            deletedSelectedPageID = nil
        }

        appData.undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.performUndo()
        }

        withAnimation {
            appData.pages.remove(atOffsets: offsets)
            if deletedSelectedPageID != nil {
                selectedPageID.wrappedValue = nil
            }
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
            for (page, index) in zip(deletedPages, deletedIndices) {
                appData.pages.insert(page, at: index)
            }
            if let restoredID = deletedSelectedPageID {
                selectedPageID.wrappedValue = restoredID
            }
            showingUndo = false
        }
    }
}

struct SidebarView: View {
    @ObservedObject var appData: AppData
    @Binding var selectedPageID: UUID?

    @StateObject private var undoCoordinator: SidebarUndoCoordinator

    // Initialize coordinator
    init(appData: AppData, selectedPageID: Binding<UUID?>) {
        self.appData = appData
        self._selectedPageID = selectedPageID
        let coordinator = SidebarUndoCoordinator(appData: appData, selectedPageID: selectedPageID)
        self._undoCoordinator = StateObject(wrappedValue: coordinator)
    }

    @State private var showingTemplatePicker = false
    @State private var chosenTemplate: Template = .blank
    @State private var newTitle = "New Page"

    var body: some View {
        ZStack(alignment: .bottom) {
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
                        undoCoordinator.delete(at: indices)
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

            // Undo Snackbar
            if undoCoordinator.showingUndo {
                undoSnackbar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .navigationTitle("Workspace")
    }

    // MARK: - Undo Snackbar
    @ViewBuilder
    private func undoSnackbar() -> some View {
        HStack {
            let count = undoCoordinator.deletedPages.count
            Text("\(count == 1 ? "Page" : "\(count) pages") deleted")
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
}
