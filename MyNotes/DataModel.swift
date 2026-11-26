//  DataModel.swift
import Foundation
import Combine
import SwiftUI
import WidgetKit

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
    case audio

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
        case .audio: return "Voice Note"
        }
    }

    /// Block types that are added without typing content first
    /// (the Add Block bar hides the content field for these).
    var hidesContentInput: Bool {
        switch self {
        case .calendar, .divider, .image, .link, .audio: return true
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
    /// Recorded audio for voice-note blocks (AAC / .m4a data). Nil
    /// for other types. Note: the audio rides along in the saved
    /// page JSON and the iCloud snapshot, so long recordings make
    /// the dataset bigger — there is no separate audio file store
    /// in v1.
    var audioData: Data? = nil
}

// MARK: - Block decoding (backward compatible)
// The imageData, isExpanded, detail, linkedPageID, and audioData
// fields were added after the first release, so pages saved by
// earlier versions do not have those keys. Decode them with
// decodeIfPresent so old data still loads. (The custom init lives
// in an extension so the memberwise initializer used by Templates
// and addBlock() is preserved.)
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
        audioData = try container.decodeIfPresent(Data.self, forKey: .audioData)
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

// MARK: - App Theme
/// The accent color of the app, stored by name (e.g. "blue") so it
/// encodes cleanly to JSON. The six colors are the same palette as
/// the calendar event colors, so a theme accent can double as the
/// default color for a new calendar event.
enum ThemeAccent: String, Codable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case purple
    case pink

    var displayName: String { rawValue.capitalized }

    /// The SwiftUI color for this accent.
    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    /// The calendar event color matching this accent (same six
    /// colors), used as the default color for a new calendar event.
    var eventColor: EventColor {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        }
    }
}

/// The font style of the app, stored by name (e.g. "serif") so it
/// encodes cleanly to JSON.
enum ThemeFont: String, Codable, CaseIterable {
    case system
    case serif
    case rounded

    var displayName: String {
        switch self {
        case .system: return "System"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        }
    }

    /// The SwiftUI font design for this style.
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        }
    }
}

/// The app theme: one accent color + one font style for the whole
/// app (global, not per-page). Stored by name so it encodes cleanly
/// to JSON. `AppTheme()` is the default (blue accent, System font).
struct AppTheme: Codable, Equatable {
    var accent: ThemeAccent = .blue
    var font: ThemeFont = .system

    /// The default theme: blue accent, System font.
    static let standard = AppTheme()

    /// The SwiftUI accent color for this theme.
    var accentColor: Color { accent.color }

    /// The SwiftUI font design for this theme.
    var fontDesign: Font.Design { font.design }
}

extension View {
    /// Applies a font at the given text style using the theme's font
    /// design, so the font choice is applied consistently wherever
    /// the theme font is used.
    func themeFont(_ style: Font.TextStyle, theme: AppTheme) -> some View {
        font(.system(style, design: theme.fontDesign))
    }
}


// MARK: - Dark Mode Colors (roadmap item 11)
// Semantic colors for the dark-mode polish: true black surfaces in
// dark mode, the exact system colors in light mode, so light mode is
// untouched. Each color is a dynamic UIColor that resolves per trait
// collection, so it follows the system appearance live (including a
// mid-session light/dark switch) with no @Environment plumbing at
// the call sites.
extension Color {
    /// Block/card background: the gray containers around text,
    /// quote, toggle, link, and image blocks, and the calendar
    /// block. Light: systemGray6 (unchanged). Dark: true black.
    static var appCardBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? .black : .systemGray6
        })
    }

    /// Elevated card background: a card that sits inside another
    /// card and must stay visible as a card in dark mode - the event
    /// preview card inside the (now black) calendar block. Light:
    /// systemBackground (unchanged). Dark: a near-black lift
    /// (#242424) so the card reads against the true-black page.
    /// (If you want it pure black too, change the dark value to
    /// .black - the card will blend into the calendar block.)
    static var appElevatedBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(white: 0.14, alpha: 1) : .systemBackground
        })
    }

    /// Muted/secondary text, slightly brighter in dark mode so it
    /// stays readable on true black. Light: secondaryLabel (exactly
    /// .secondary, unchanged). Dark: white at 0.72 - brighter than
    /// the default secondary label, which is white at 0.6 and reads
    /// dim on pure black.
    static var appMutedText: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(white: 0.72, alpha: 1) : .secondaryLabel
        })
    }

    /// The "today" cell fill in the calendar. Light: blue at 0.2
    /// (unchanged). Dark: blue at 0.38 - the 0.2 fill is washed out
    /// on true black. (systemBlue already brightens in dark mode;
    /// the higher opacity is what makes today unmistakable.)
    static var appTodayHighlight: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.systemBlue.withAlphaComponent(0.38) : UIColor.systemBlue.withAlphaComponent(0.2)
        })
    }
}

// MARK: - Home Screen Widget (roadmap item 12)
/// A lightweight summary of one page for the home-screen widget:
/// id, title, up to two lines of preview text, block count, and
/// creation date (the widget sorts newest first — Page has no
/// updated-at date, so creation date is the recency order).
/// The widget extension defines this same struct (same property
/// names and types) in its own WidgetData.swift — keep the two in
/// sync, or the widget fails to decode the summary and shows its
/// placeholder instead. No image data is ever shared: the summary
/// is text only, so it stays small.
struct WidgetPageSummary: Codable, Equatable {
    var id: UUID
    var title: String
    var preview: String
    var blockCount: Int
    var createdAt: Date

    /// The readable text of a page as up to two lines, for the
    /// widget preview. Text-like blocks contribute their content;
    /// toggle lists contribute the label and the items; calendar
    /// blocks contribute event text. Divider, image, and link
    /// blocks carry no readable text.
    static func preview(for page: Page) -> String {
        var lines: [String] = []
        for block in page.blocks {
            switch block.type {
            case .text, .todo, .quote, .code:
                lines.append(contentsOf: block.content.components(separatedBy: .newlines))
            case .toggle:
                lines.append(contentsOf: block.content.components(separatedBy: .newlines))
                lines.append(contentsOf: block.detail.components(separatedBy: .newlines))
            case .calendar:
                lines.append(contentsOf: block.events.values.flatMap { $0.text.components(separatedBy: .newlines) })
            case .divider, .image, .link, .audio:
                break
            }
        }
        let trimmed = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(trimmed.prefix(2)).joined(separator: "\n")
    }

    /// Summaries for the widget: the newest pages first, up to 8.
    static func summaries(for pages: [Page]) -> [WidgetPageSummary] {
        pages
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { page in
                WidgetPageSummary(
                    id: page.id,
                    title: page.title,
                    preview: preview(for: page),
                    blockCount: page.blocks.count,
                    createdAt: page.createdAt
                )
            }
    }
}

class AppData: ObservableObject {
    @Published var pages: [Page] = [] {
        didSet { saveData() }
    }

    @Published var folders: [Folder] = [] {
        didSet { saveFolders() }
    }

    @Published var theme: AppTheme = .standard {
        didSet { saveTheme() }
    }
    
    /// iCloud sync (roadmap item 8). Owns the CloudKit sync; the
    /// local UserDefaults persistence above stays the source of
    /// truth, so the app works fully offline when iCloud is
    /// unavailable.
    let syncManager: CloudKitSyncManager

    let undoManager = UndoManager()

    /// The App Group shared container the widget reads from, and the
    /// key the summary is written under. Nil until the App Group
    /// capability (group.morrowchristian.MyNotes) is enabled on the
    /// app target in Xcode — the mirror in saveWidgetSummary() is a
    /// no-op until then, and the local "pages" key stays the source
    /// of truth, so the app works exactly as before.
    static let widgetAppGroupID = "group.morrowchristian.MyNotes"
    static let widgetPagesKey = "widgetPages"

    /// The last summary written to the shared container, so the
    /// widget timeline is only reloaded when the summary actually
    /// changed (checking a todo, for example, does not change the
    /// preview text and needs no reload).
    private var lastWidgetSummaryData: Data?

    init() {
        // syncManager is a let constant with no default value, so
        // it must be assigned before any method on self is called —
        // otherwise Swift reports "'self' used before all stored
        // properties are initialized". attach(to:) stays last: it
        // seeds the change hash from the data the loads just read.
        syncManager = CloudKitSyncManager()
        loadData()
        loadFolders()
        loadTheme()
        syncManager.attach(to: self)
    }
    
    func saveData() {
        guard let encoded = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(encoded, forKey: "pages")
        saveWidgetSummary()
    }

    // MARK: - Home Screen Widget (roadmap item 12)
    /// Mirrors a lightweight summary of the pages into the shared
    /// App Group container so the widget extension can read it.
    /// Called from saveData(), so it runs whenever pages change.
    /// Safe no-op when the App Group is not configured yet
    /// (UserDefaults(suiteName:) returns nil) — the app keeps
    /// working exactly as before.
    func saveWidgetSummary() {
        guard let shared = UserDefaults(suiteName: Self.widgetAppGroupID) else { return }
        let summaries = WidgetPageSummary.summaries(for: pages)
        guard let encoded = try? JSONEncoder().encode(summaries) else { return }
        let changed = encoded != lastWidgetSummaryData
        lastWidgetSummaryData = encoded
        shared.set(encoded, forKey: Self.widgetPagesKey)
        // Tell WidgetKit the data changed so the widget refreshes
        // promptly. The system throttles reloads, so bursts of edits
        // are coalesced — and an unchanged summary skips the reload
        // entirely (see `changed` above).
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
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

    // MARK: - Theme
    func saveTheme() {
        guard let encoded = try? JSONEncoder().encode(theme) else { return }
        UserDefaults.standard.set(encoded, forKey: "appTheme")
    }

    /// Loads the theme. Data saved before themes existed has no
    /// "appTheme" key, so the theme stays the default (blue accent,
    /// System font). A corrupt value is ignored the same way.
    func loadTheme() {
        guard let data = UserDefaults.standard.data(forKey: "appTheme"),
              let decoded = try? JSONDecoder().decode(AppTheme.self, from: data) else { return }
        theme = decoded
    }
    
    static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return formatter.string(from: date)
    }
}
