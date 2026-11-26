//  MainView.swift
import SwiftUI

struct MainView: View {
    @StateObject private var appData = AppData()
    @State private var selectedPageID: UUID?
    // Global Search (roadmap item 9): the query typed in the sidebar
    // search field. Owned here so both the sidebar (which filters the
    // page list) and the detail pane (which tints matching blocks)
    // see the same query. View-only state — never persisted, never
    // synced, never clears the selection.
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(appData: appData, selectedPageID: $selectedPageID, searchText: $searchText)
        } detail: {
            if let selectedID = selectedPageID,
               let pageIndex = appData.pages.firstIndex(where: { $0.id == selectedID }) {
                let pageBinding = Binding(
                    get: { appData.pages[pageIndex] },
                    set: { newPage in
                        appData.pages[pageIndex] = newPage
                    }
                )
                PageView(page: pageBinding, appData: appData, selectedPageID: $selectedPageID, searchQuery: searchText)
            } else {
                Text("Select a page")
                    .font(.title2)
                    .foregroundColor(Color.appMutedText)
            }
        }
        // The theme accent drives the app's tint: the sidebar
        // selection highlight and the prominent/bordered buttons
        // (Add, Create, tag Add) all follow it.
        .tint(appData.theme.accentColor)
    }
}

#Preview {
    MainView()
}
