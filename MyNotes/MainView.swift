//  MainView.swift
import SwiftUI

struct MainView: View {
    @StateObject private var appData = AppData()
    @State private var selectedPageID: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(appData: appData, selectedPageID: $selectedPageID)
        } detail: {
            if let selectedID = selectedPageID,
               let pageIndex = appData.pages.firstIndex(where: { $0.id == selectedID }) {
                let pageBinding = Binding(
                    get: { appData.pages[pageIndex] },
                    set: { newPage in
                        appData.pages[pageIndex] = newPage
                    }
                )
                PageView(page: pageBinding, appData: appData, selectedPageID: $selectedPageID)
            } else {
                Text("Select a page")
                    .font(.title2)
                    .foregroundColor(.secondary)
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
