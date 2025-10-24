//
//  MainView.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import SwiftUI

struct MainView: View {
    @StateObject private var appData = AppData()
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            Text("Select a page")
        }
    }
}

struct SidebarView: View {
    @ObservedObject var appData: AppData
    
    var body: some View {
        List {
            Section(header: Text("Pages")) {
                ForEach(appData.pages) { page in
                    NavigationLink(destination: PageView(page: page, appData: appData)) {
                        Text(page.title)
                    }
                }
            }
            Button("Add Page") {
                let newPage = Page(title: "New Page")
                appData.pages.append(newPage)
                appData.saveData()
            }
        }
        .navigationTitle("Workspace")
    }
}

#Preview {
    MainView()
}
