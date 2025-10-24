//
//  MyNotesTests.swift
//  MyNotesTests
//

import XCTest
@testable import MyNotes

final class MyNotesTests: XCTestCase {

    var appData: AppData!

    override func setUp() {
        super.setUp()
        appData = AppData()
        appData.pages = []
        UserDefaults.standard.removeObject(forKey: "pages")
    }

    override func tearDown() {
        appData = nil
        super.tearDown()
    }

    // MARK: - Persistence
    func testSaveAndLoadPages() {
        let page = Page(id: UUID(), title: "Test", markdown: "# Hello")
        appData.pages = [page]
        appData.saveData()

        let loaded = AppData()
        XCTAssertEqual(loaded.pages.count, 1)
        XCTAssertEqual(loaded.pages[0].title, "Test")
        XCTAssertEqual(loaded.pages[0].markdown, "# Hello")
    }

    // MARK: - CRUD
    func testCreateAndDeletePage() {
        let page = Page(id: UUID(), title: "New", markdown: "")
        appData.pages.append(page)
        XCTAssertEqual(appData.pages.count, 1)

        appData.pages.removeAll()
        XCTAssertTrue(appData.pages.isEmpty)
    }

    // MARK: - Templates
    func testTemplateBlank() {
        XCTAssertTrue(Template.blank.markdown.contains("# New Page"))
    }

    func testTemplateToDo() {
        XCTAssertTrue(Template.todo.markdown.contains("- [ ] Buy milk"))
    }

    func testTemplateCalendar() {
        XCTAssertTrue(Template.calendar.markdown.contains("2025-10-25"))
    }

    // MARK: - Markdown → AttributedString (Pure Logic)
    func testMarkdownToAttributedString() throws {
        let markdown = "**Bold** and *italic*"
        let attributed = try AttributedString(markdown: markdown)

        let boldRange = attributed.range(of: "Bold")
        XCTAssertNotNil(boldRange)
        XCTAssertTrue(attributed[boldRange!].font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }
}
