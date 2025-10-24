//
//  SidebarView.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var appData: AppData
    
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
            
            NavigationLink(destination: CalendarView(appData: appData)) {
                Text("Calendar")
            }
            
            Button("Add Page") {
                let newPage = Page(id: UUID(), title: "New Page")
                appData.pages.append(newPage)
            }
        }
        .navigationTitle("Workspace")
    }
}
