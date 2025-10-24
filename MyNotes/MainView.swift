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
            SidebarView(appData: appData)
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
                ForEach(appData.pages, id: \.id) { page in
                    NavigationLink(destination: PageView(page: page, appData: appData)) {
                        Text(page.title)
                    }
                }
            }
            NavigationLink(destination: CalendarView(appData: appData)) {
                Text("Calendar")
            }
            Button("Add Page") {
                let newPage = Page(id: <#UUID#>, title: "New Page")
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
