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

#Preview {
    MainView()
}
