//  DrawingBlock.swift
//  MyNotes
//
//  Roadmap item 14 — Handwriting / Apple Pencil: a drawing block
//  that lets the user handwrite or sketch inside a page with Apple
//  Pencil (or a finger — the canvas accepts any input, so it also
//  works with a mouse on the simulator). PencilKit (PKCanvasView)
//  handles the input, pressure, and palm rejection natively; there
//  is no custom stroke model — the drawing is a PKDrawing end to
//  end, serialized with dataRepresentation() into Block.drawingData,
//  so it rides along in the saved page JSON and the iCloud snapshot
//  like the other block data. Drawings are compact vector data, much
//  lighter than the audio or image blocks. A corrupt/unreadable
//  value is ignored and the block shows an empty canvas, never a
//  crash.
//
//  The canvas is a white sheet in both light and dark mode, so the
//  default dark ink always reads. The PencilKit tool picker (pen /
//  pencil / marker / eraser, colors, widths) floats while editing.
//  Pencil pressure is only testable on a real iPad — the simulator
//  draws with the mouse/finger at a fixed pressure.

import SwiftUI
import UIKit
import PencilKit

// MARK: - Drawing Image

/// Renders saved drawing data as an image, shared by the block's
/// view mode and the PDF export (both put it on a white background
/// — the ink is dark by default). Nil when there is no data, the
/// data is corrupt, or the drawing has no strokes.
enum DrawingBlockImage {
    static func image(for data: Data?) -> UIImage? {
        guard let data,
              let drawing = try? PKDrawing(data: data),
              !drawing.strokes.isEmpty else { return nil }
        // Pad the bounds a little so strokes at the edge are not
        // clipped by the render.
        let rect = drawing.bounds.insetBy(dx: -8, dy: -8)
        return drawing.image(from: rect, scale: UIScreen.main.scale)
    }
}

// MARK: - PencilKit Canvas (UIViewRepresentable)

/// A PKCanvasView bridged into SwiftUI. The canvas writes every
/// stroke back through the `drawing` binding (via the coordinator's
/// canvasViewDrawingDidChange), and the binding is only pushed down
/// into the canvas when it differs — otherwise the two would fight
/// over the user's in-progress strokes.
struct DrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        // A white sheet, so the ink reads the same in light and
        // dark mode (the default pen ink is dark).
        canvasView.backgroundColor = .white
        // Finger as well as Pencil: on iPad the default policy only
        // draws with Pencil, which would make finger drawing — and
        // the simulator's mouse — look broken.
        canvasView.drawingPolicy = .anyInput
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        // The tool picker needs a window, which the canvas does not
        // have in makeUIView — set it up once the canvas is in the
        // hierarchy. If the window is never available, drawing still
        // works with the default pen; only the tool picker is missing.
        if !context.coordinator.toolPickerConfigured, let window = uiView.window {
            let toolPicker = PKToolPicker.shared(for: window)
            toolPicker.setVisible(true, forFirstResponder: uiView)
            toolPicker.addObserver(uiView)
            uiView.becomeFirstResponder()
            context.coordinator.toolPickerConfigured = true
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        // Hide the floating tool picker when the canvas leaves the
        // hierarchy (edit mode ended), so it does not linger over
        // the page.
        if let window = uiView.window {
            PKToolPicker.shared(for: window).setVisible(false, forFirstResponder: uiView)
        }
        uiView.resignFirstResponder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvasView
        var toolPickerConfigured = false

        init(_ parent: DrawingCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

// MARK: - Drawing Block View

/// The drawing block: two modes.
/// (a) View mode — the saved drawing rendered as an image on a
/// white sheet, with an Edit button (tapping the image edits too);
/// an empty block shows a "Tap to draw or write" row instead.
/// (b) Edit mode — the live PKCanvasView (fixed 240pt height, so it
/// does not swallow the page) with the PencilKit tool picker, plus
/// Clear and Done. Done saves the drawing back through
/// onDrawingFinished; leaving the page mid-edit saves it too
/// (onDisappear), so a drawing is never lost. An empty canvas on
/// Done clears the block (nil data), so the empty state shows again.
struct DrawingBlockView: View {
    @Binding var block: Block
    var accentColor: Color
    /// Called with the serialized drawing when editing finishes.
    /// The caller (PageView) writes it into the block by id, so a
    /// block deleted mid-edit is a no-op instead of a crash through
    /// a stale binding. Nil clears the drawing.
    var onDrawingFinished: (Data?) -> Void

    /// Whether the live canvas is showing. The canvas edits
    /// `editingDrawing`; the block itself is only written on Done
    /// (or on disappear), so cancelling out of an edit does not
    /// touch the saved drawing — except that Done is the only way
    /// out of edit mode, and disappearing saves, so in practice an
    /// edit is always saved (v1 has no Cancel).
    @State private var isEditing = false
    @State private var editingDrawing = PKDrawing()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                // (b) Edit mode — live canvas + tool picker.
                DrawingCanvasView(drawing: $editingDrawing)
                    .frame(height: 240)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                HStack {
                    Button("Clear") {
                        editingDrawing = PKDrawing()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    Spacer()
                    Button("Done") {
                        finishEditing()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let image = DrawingBlockImage.image(for: block.drawingData) {
                // (a) View mode — saved drawing on a white sheet.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .background(Color.white)
                    .cornerRadius(12)
                    .onTapGesture { startEditing() }
                HStack {
                    Text("Drawing")
                        .font(.caption)
                        .foregroundStyle(Color.appMutedText)
                    Spacer()
                    Button("Edit") { startEditing() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            } else {
                // (a) Empty — no drawing saved yet.
                Button {
                    startEditing()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.and.scribble")
                            .foregroundStyle(accentColor)
                        Text("Tap to draw or write")
                            .font(.subheadline)
                            .foregroundStyle(Color.appMutedText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.appMutedText)
                    }
                    .padding(12)
                    .background(Color.appCardBackground)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear {
            // Leaving the page (or scrolling the row off-screen)
            // mid-edit saves the drawing instead of losing it.
            // A no-op when not editing: finishEditing already saved
            // and cleared the flag.
            if isEditing {
                finishEditing()
            }
        }
    }

    /// Loads the saved drawing into the edit canvas (or an empty
    /// canvas when there is none / the data is corrupt) and opens
    /// edit mode.
    private func startEditing() {
        if let data = block.drawingData,
           let drawing = try? PKDrawing(data: data) {
            editingDrawing = drawing
        } else {
            editingDrawing = PKDrawing()
        }
        isEditing = true
    }

    /// Saves the edit canvas back through the finish closure and
    /// closes edit mode. An empty canvas clears the block (nil),
    /// so the empty state shows again.
    private func finishEditing() {
        isEditing = false
        onDrawingFinished(editingDrawing.strokes.isEmpty ? nil : editingDrawing.dataRepresentation())
    }
}
