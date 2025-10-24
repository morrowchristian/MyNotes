//
//  DataModel.swift
//  MyNotes
//
//  Created by Christian Morrow on 10/23/25.
//

import Foundation
import Combine

struct Page: Identifiable, Codable {
    let id: UUID
    var title: String
    var markdown: String = ""          // ← NEW
}

class AppData: ObservableObject {
    @Published var pages: [Page] = [] {
        didSet { saveData() }
    }
    
    init() { loadData() }
    
    func saveData() {
        guard let encoded = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(encoded, forKey: "pages")
    }
    
    func loadData() {
        guard let data = UserDefaults.standard.data(forKey: "pages"),
              let decoded = try? JSONDecoder().decode([Page].self, from: data) else { return }
        pages = decoded
    }
}
