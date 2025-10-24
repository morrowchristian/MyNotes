//
//  MyNotesUITests.swift
//  MyNotesUITests
//

import XCTest

final class MyNotesUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testAddPageWithTemplate() {
        // Tap "Add Page"
        app.buttons["Add Page"].tap()

        // Choose "To-Do List"
        let todoCell = app.tables.cells.containing(.staticText, identifier: "To-Do List").firstMatch
        XCTAssertTrue(todoCell.waitForExistence(timeout: 2))
        todoCell.tap()

        // Tap "Create"
        app.buttons["Create"].tap()

        // Verify page appears
        let pageTitle = app.navigationBars["New Page"].identifier
        XCTAssertTrue(app.staticTexts["To-Do List"].waitForExistence(timeout: 2))
    }

    func testEditAndPreviewMarkdown() {
        // Add a blank page
        app.buttons["Add Page"].tap()
        app.tables.cells.containing(.staticText, identifier: "Blank").firstMatch.tap()
        app.buttons["Create"].tap()

        // Edit
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.typeText("**Bold Text**")

        // Preview
        app.buttons["Preview"].tap()
        XCTAssertTrue(app.staticTexts["Bold Text"].waitForExistence(timeout: 2))

        // Go back to edit
        app.buttons["Edit"].tap()
        XCTAssertTrue(editor.value as? String == "**Bold Text**")
    }

    func testOpenMarkdownGuide() {
        app.buttons["Add Page"].tap()
        app.tables.cells.firstMatch.tap()
        app.buttons["Create"].tap()

        app.buttons["Guides"].tap()
        XCTAssertTrue(app.navigationBars["Markdown Guide"].waitForExistence(timeout: 2))
        app.buttons["Close"].tap()
    }

    func testDeletePage() {
        app.buttons["Add Page"].tap()
        app.tables.cells.containing(.staticText, identifier: "Blank").firstMatch.tap()
        app.buttons["Create"].tap()

        // Swipe to delete
        let pageCell = app.tables.cells.firstMatch
        pageCell.swipeLeft()
        app.buttons["Delete"].tap()

        XCTAssertFalse(pageCell.exists)
    }
}
