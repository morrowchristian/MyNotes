//
//  MyNotesTests.swift
//  MyNotesTests
//
//  Rewritten 2026-11-26: the model was refactored from markdown-based
//  to block-based (PRs #3-#9), so the old tests referencing
//  Page(id:title:markdown:) and Template.*.markdown no longer compile.
//  These tests cover the current block-based model instead. The old
//  markdown -> AttributedString test is dropped: the app no longer
//  stores content as markdown, and it referenced `.fontDescriptor`,
//  which does not exist on SwiftUI Font.

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
        let block = Block(id: UUID(), type: .text, content: "# Hello")
        let page = Page(id: UUID(), title: "Test", createdAt: Date(), blocks: [block])
        appData.pages = [page]
        appData.saveData()

        let loaded = AppData()
        XCTAssertEqual(loaded.pages.count, 1)
        XCTAssertEqual(loaded.pages[0].title, "Test")
        XCTAssertEqual(loaded.pages[0].blocks.count, 1)
        XCTAssertEqual(loaded.pages[0].blocks[0].type, .text)
        XCTAssertEqual(loaded.pages[0].blocks[0].content, "# Hello")
    }

    // MARK: - CRUD
    func testCreateAndDeletePage() {
        let page = Page(id: UUID(), title: "New", createdAt: Date(), blocks: [])
        appData.pages.append(page)
        XCTAssertEqual(appData.pages.count, 1)

        appData.pages.removeAll()
        XCTAssertTrue(appData.pages.isEmpty)
    }

    // MARK: - Templates
    func testTemplateBlank() {
        XCTAssertTrue(Template.blank.initialBlocks.isEmpty)
    }

    func testTemplateToDo() {
        let blocks = Template.todo.initialBlocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks.allSatisfy { $0.type == .todo })
        XCTAssertTrue(blocks.contains { $0.content == "Task 1" })
    }

    func testTemplateCalendar() {
        let blocks = Template.calendar.initialBlocks
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, .calendar)
    }

    func testTemplateNotes() {
        let blocks = Template.notes.initialBlocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks.allSatisfy { $0.type == .text })
    }
}
