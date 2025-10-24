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
    var body: some View {
        List {
            Text("Notes")
            Text("To-Do")
            Text("Calendar")
        }
        .navigationTitle("Workspace")
    }
}

#Preview {
    MainView()
}
