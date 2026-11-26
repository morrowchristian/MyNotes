//  DataModel.swift
import Foundation
import Combine

enum BlockType: String, Codable, CaseIterable {
    case text
    case todo
    case calendar
    case quote
    case code
    case divider
    case image
    case toggle
    case link

    /// The label shown for this type in the Add Block picker.
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .todo: return "To-Do"
        case .calendar: return "Calendar"
        case .quote: return "Quote"
        case .code: return "Code"
        case .divider: return "Divider"
        case .image: return "Image"
        case .toggle: return "Toggle List"
        case .link: return "Page Link"
        }
    }

    /// Block types that are added without typing content first
    /// (the Add Block bar hides the content field for these).
    var hidesContentInput: Bool {
        switch self {
        case .calendar, .divider, .image, .link: return true
        case .text, .todo, .quote, .code, .toggle: return false
        }
    }
}

/// The color an event is shown with in the calendar, stored by name
/// (e.g. "blue") so it encodes cleanly to JSON.
enum EventColor: String, Codable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case purple
    case pink
}

/// A calendar event: the note text plus the color it is shown with.
/// Events saved by earlier versions are plain strings; see init(from:).
struct CalendarEvent: Codable {
    var text: String
    var color: EventColor

    init(text: String, color: EventColor = .blue) {
        self.text = text
        self.color = color
    }

    // MARK: - Migration
    // Earlier versions stored events as [Date: String]. Accept either a
    // plain string (old format — default color blue) or the new object,
    // so existing saved events still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self.text = text
            self.color = .blue
        } else {
            let object = try container.decode(CalendarEventObject.self)
            self.text = object.text
            self.color = object.color ?? .blue
        }
    }

    /// The new on-disk shape for an event.
    private struct CalendarEventObject: Decodable {
        var text: String
        var color: EventColor?
    }
}

struct Block: Identifiable, Codable {
    let id: UUID
    var type: BlockType
    var content: String = ""
    var isCompleted: Bool = false
    var events: [Date: CalendarEvent] = [:]
    /// Photo data for image blocks (downscaled JPEG). Nil for other types.
    var imageData: Data? = nil
    /// Whether a toggle-list block is expanded.
    var isExpanded: Bool = true
    /// The body text of a toggle-list block (one item per line).
    var detail: String = ""
    /// The id of the page a link block points to. Nil for other types.
    var linkedPageID: UUID? = nil
}

// MARK: - Block decoding (backward compatible)
// The imageData, isExpanded, detail, and linkedPageID fields were
// added after the first release, so pages saved by earlier versions
// do not have those keys. Decode them with decodeIfPresent so old
// data still loads. (The custom init lives in an extension so the
// memberwise initializer used by Templates and addBlock() is preserved.)
extension Block {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(BlockType.self, forKey: .type)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        events = try container.decodeIfPresent([Date: CalendarEvent].self, forKey: .events) ?? [:]
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        linkedPageID = try container.decodeIfPresent(UUID.self, forKey: .linkedPageID)
    }
}

struct Page: Identifiable, Codable {
    let id: UUID
    var title: String
    var createdAt: Date
    var blocks: [Block] = []
    /// Tags for this page (e.g. "work", "personal"), stored without
    /// the "#" and lowercased. Used to filter the sidebar. Defaults
    /// to empty, so pages saved before tags existed still decode
    /// (the synthesized Codable uses decodeIfPresent for defaulted
    /// fields).
    var tags: [String] = []

    /// Normalize a typed tag: lowercase, strip a leading "#", trim
    /// whitespace, and take only the first word (a tag is a single
    /// word — a space ends it). Returns nil for an empty result.
    static func normalizedTag(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let space = text.firstIndex(where: { $0.isWhitespace }) {
            text = String(text[..<space])
        }
        text = text.lowercased()
        return text.isEmpty ? nil : text
    }
}

/// A folder groups pages in the sidebar. A page belongs to at most one
/// folder; a page in no folder is ungrouped and shows at the top level.
/// `isExpanded` is the sidebar collapse/expand state and persists.
struct Folder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var pageIDs: [UUID]
    var isExpanded: Bool
}

class AppData: ObservableObject {
    @Published var pages: [Page] = [] {
        didSet { saveData() }
    }

    @Published var folders: [Folder] = [] {
        didSet { saveFolders() }
    }
    
    let undoManager = UndoManager()
    
    init() {
        loadData()
        loadFolders()
    }
    
    func saveData() {
        guard let encoded = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(encoded, forKey: "pages")
    }
    
    func loadData() {
        guard let data = UserDefaults.standard.data(forKey: "pages"),
              let decoded = try? JSONDecoder().decode([Page].self, from: data) else { return }
        pages = decoded
    }

    // MARK: - Folders
    func saveFolders() {
        guard let encoded = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(encoded, forKey: "folders")
    }

    /// Loads the folders. Data saved before folders existed has no
    /// "folders" key, so the list stays empty and every page is
    /// ungrouped. Page ids are deduped across folders (first occurrence
    /// wins) so a page is never shown in two folders.
    func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: "folders") else { return }
        guard var decoded = try? JSONDecoder().decode([Folder].self, from: data) else { return }
        var seen: Set<UUID> = []
        for i in decoded.indices {
            decoded[i].pageIDs.removeAll { id in
                if seen.contains(id) { return true }
                seen.insert(id)
                return false
            }
        }
        folders = decoded
    }

    /// The folder holding this page, if any.
    func folderContaining(pageID: UUID) -> Folder? {
        folders.first { $0.pageIDs.contains(pageID) }
    }

    /// Move a page into a folder, or out to ungrouped when folderID is nil.
    /// A page belongs to at most one folder. Moving to the folder it is
    /// already in is a no-op, so its position in that folder is preserved.
    func movePage(_ pageID: UUID, to folderID: UUID?) {
        if let folderID, folderContaining(pageID: pageID)?.id == folderID {
            return
        }
        for i in folders.indices {
            folders[i].pageIDs.removeAll { $0 == pageID }
        }
        if let folderID, let index = folders.firstIndex(where: { $0.id == folderID }) {
            folders[index].pageIDs.append(pageID)
        }
    }

    /// Remove a page id from every folder (used when the page is deleted,
    /// so a folder never references a deleted page).
    func removePageFromFolders(_ pageID: UUID) {
        for i in folders.indices {
            folders[i].pageIDs.removeAll { $0 == pageID }
        }
    }

    /// Restore a page to a folder at a position (used by Undo). Does
    /// nothing if the folder no longer exists — the page stays ungrouped.
    func insertPage(_ pageID: UUID, intoFolder folderID: UUID, at index: Int) {
        removePageFromFolders(pageID)
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let clamped = min(max(index, 0), folders[folderIndex].pageIDs.count)
        folders[folderIndex].pageIDs.insert(pageID, at: clamped)
    }

    func setFolderExpanded(id: UUID, isExpanded: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isExpanded = isExpanded
    }

    func renameFolder(id: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = name
    }
    
    static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return formatter.string(from: date)
    }
}
