//  MainView.swift
import SwiftUI

struct MainView: View {
    @StateObject private var appData = AppData()
    @State private var selectedPageID: UUID?
    
    var body: some View {
        NavigationSplitView {
            SidebarView(appData: appData, selectedPageID: $selectedPageID)
        } detail: {
            if let id = selectedPageID,
               let binding = Binding<Page>($appData.pages.first(where: { $0.id == id })) {
                PageView(page: binding, appData: appData)
            } else {
                Text("Select a page")
            }
        }
    }
}

#Preview {
    MainView()
}
