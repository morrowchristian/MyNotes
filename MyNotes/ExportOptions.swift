//  ExportOptions.swift
//  MyNotes
//
//  Roadmap item 10 — Export Options: Markdown, PDF, and Print for the
//  current page. The conversion and rendering helpers are pure and
//  separate from the UI (MarkdownExporter / PDFExporter), so they can
//  be tested on their own; PageView only wires them to a toolbar Menu.
//  Nothing here changes the data model, persistence, or sync.

import SwiftUI
import UIKit
import CoreGraphics

// MARK: - Markdown Export

/// Converts a page's blocks to a Markdown string. Pure function —
/// no UI, no persistence — so it can be unit-tested on its own.
enum MarkdownExporter {
    /// The whole page as Markdown: the title as a `#` heading, then
    /// one block per section (blank line between blocks). Blocks with
    /// nothing to export (an empty calendar, an empty text block) are
    /// skipped.
    static func markdown(for page: Page) -> String {
        var parts: [String] = ["# \(page.title)"]
        for block in page.blocks {
            if let text = markdown(for: block), !text.isEmpty {
                parts.append(text)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// The Markdown for one block, or nil when the block has nothing
    /// to export.
    static func markdown(for block: Block) -> String? {
        switch block.type {
        case .text:
            return block.content.isEmpty ? nil : block.content
        case .todo:
            guard !block.content.isEmpty else { return nil }
            return "- [\(block.isCompleted ? "x" : " ")] \(block.content)"
        case .quote:
            guard !block.content.isEmpty else { return nil }
            return block.content
                .components(separatedBy: .newlines)
                .map { "> \($0)" }
                .joined(separator: "\n")
        case .code:
            guard !block.content.isEmpty else { return nil }
            return "```\n\(block.content)\n```"
        case .divider:
            return "---"
        case .image:
            // Markdown has no embedded photo here — a placeholder line.
            return "[Image]"
        case .toggle:
            var lines: [String] = []
            if !block.content.isEmpty {
                lines.append("**\(block.content)**")
            }
            for line in block.detailLines {
                lines.append("- \(line)")
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        case .calendar:
            let dates = block.events.keys.sorted()
            guard !dates.isEmpty else { return nil }
            let lines = dates.compactMap { date -> String? in
                guard let event = block.events[date] else { return nil }
                return "- \(ExportDateFormatter.string(from: date)): \(event.text)"
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        case .link:
            return block.content.isEmpty ? nil : block.content
        }
    }
}

// MARK: - Shared export helpers

extension Block {
    /// A toggle block's detail body as its non-empty lines (one item
    /// per line, whitespace trimmed). Empty for other block types
    /// (their `detail` is always "").
    var detailLines: [String] {
        detail
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// The "MMM d, yyyy" date used in exports (e.g. "Nov 26, 2026").
/// A single shared formatter; only ever called on the main thread.
enum ExportDateFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

// MARK: - PDF Export

/// A simple read-only rendering of a page, used only to render the
/// PDF. It is deliberately NOT the interactive PageView editor —
/// TextEditors, pickers, and sheets do not render well to PDF. The
/// layout is a plain vertical stack at US Letter width (612pt) with
/// 36pt margins, forced to the light colour scheme so it prints
/// black-on-white even when the app is in dark mode.
struct ExportablePageView: View {
    let page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(page.title)
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.black)
            Text("Created: \(AppData.formatTimestamp(page.createdAt))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(page.blocks) { block in
                exportBlockView(block)
            }
        }
        .padding(36)
        .frame(width: 612, alignment: .topLeading)
        .background(Color.white)
    }

    @ViewBuilder
    private func exportBlockView(_ block: Block) -> some View {
        switch block.type {
        case .text:
            Text(block.content)
                .font(.body)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .todo:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: block.isCompleted ? "checkmark.square" : "square")
                    .foregroundStyle(.black)
                Text(block.content)
                    .font(.body)
                    .foregroundStyle(.black)
                    .strikethrough(block.isCompleted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3)
                Text(block.content)
                    .font(.body)
                    .italic()
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .code:
            Text(block.content)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .divider:
            Divider()
        case .image:
            if let data = block.imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("[Image]")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        case .toggle:
            VStack(alignment: .leading, spacing: 4) {
                if !block.content.isEmpty {
                    Text(block.content)
                        .font(.body)
                        .bold()
                        .foregroundStyle(.black)
                }
                ForEach(block.detailLines.indices, id: \.self) { index in
                    Text("• \(block.detailLines[index])")
                        .font(.body)
                        .foregroundStyle(.black)
                        .padding(.leading, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .calendar:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(block.events.sorted(by: { $0.key < $1.key })), id: \.key) { date, event in
                    Text("\(ExportDateFormatter.string(from: date)): \(event.text)")
                        .font(.body)
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .link:
            Text(block.content)
                .font(.body)
                .foregroundStyle(.blue)
                .underline()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Renders a page to PDF data with ImageRenderer (iOS 16+). The PDF
/// is a single page at US Letter width (612pt); its height is the
/// content's natural height, so a long page becomes one tall PDF page
/// (a follow-up could paginate it into Letter-height pages).
/// Must be called on the main thread (ImageRenderer is main-actor).
@MainActor
enum PDFExporter {
    static func pdfData(for page: Page) -> Data? {
        let content = ExportablePageView(page: page)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = .init(width: 612, height: nil)
        let data = NSMutableData()
        renderer.render { size, render in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            pdfContext.beginPDFPage(nil)
            render(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }
        return data.length > 0 ? data as Data : nil
    }
}

// MARK: - Export files

/// Turns an export into a shareable file: a filename-safe name from
/// the page title, and a write to the temporary directory (overwriting
/// any previous export with the same name). The share sheet receives
/// the file URL, so "Save to Files" saves a real .md/.pdf file.
enum ExportFile {
    static func safeFileName(from title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = title
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    static func temporaryFileURL(data: Data, fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Presenting the share / print sheets

/// Presents the iOS share sheet and the print sheet from a SwiftUI
/// button action. Both are presented from the key window's root view
/// controller (the SwiftUI host). On iPad the sheets are anchored to
/// the centre of the screen, so they do not need a bar-button anchor.
@MainActor
enum ExportPresenter {
    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    static func presentShareSheet(items: [Any]) {
        guard let rootVC = rootViewController() else { return }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        rootVC.present(activityVC, animated: true)
    }

    static func presentPrintSheet(pdfData: Data, jobName: String) {
        guard let rootVC = rootViewController() else { return }
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .general
        printController.printInfo = printInfo
        printController.printingItem = pdfData
        let anchor = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
        printController.present(from: anchor, in: rootVC.view, animated: true, completionHandler: nil)
    }
}
