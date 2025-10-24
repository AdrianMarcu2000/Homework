//
//  DrawingCanvasView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import PencilKit
import CoreData

/// A view that provides a drawing canvas for Apple Pencil input
struct DrawingCanvasView: View {
    let exercise: Exercise
    let homeworkItem: (any AnalyzableHomework)?
    @Binding var exerciseAnswers: [String: Data]?
    @Binding var canvasData: Data?

    // Convenience init for Item (backward compatibility)
    init(exercise: Exercise, homeworkItem: Item, canvasData: Binding<Data?>) {
        self.exercise = exercise
        self.homeworkItem = homeworkItem
        self._canvasData = canvasData

        // Create a binding that reads from and writes to Item's exerciseAnswers
        self._exerciseAnswers = Binding(
            get: { homeworkItem.exerciseAnswers },
            set: { newValue in
                homeworkItem.exerciseAnswers = newValue
                if let context = homeworkItem.managedObjectContext {
                    try? context.save()
                }
            }
        )
    }

    // Generic init for any AnalyzableHomework (including ClassroomAssignment)
    init(exercise: Exercise, imageData: Data?, exerciseAnswers: Binding<[String: Data]?>, canvasData: Binding<Data?>) {
        self.exercise = exercise
        self.homeworkItem = nil
        self._exerciseAnswers = exerciseAnswers
        self._canvasData = canvasData
    }

    @State private var canvas = PKCanvasView()
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pencil.tip")
                    .foregroundColor(.purple)
                Text("Your Answer")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                Spacer()
                Button(action: clearCanvas) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            CanvasRepresentable(
                canvas: $canvas,
                canvasData: $canvasData,
                exercise: exercise,
                exerciseAnswers: $exerciseAnswers
            )
            .frame(height: isExpanded ? 400 : 200)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
            )

            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    Text(isExpanded ? "Collapse" : "Expand")
                }
                .font(.caption)
                .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    private func clearCanvas() {
        canvas.drawing = PKDrawing()
        canvasData = nil
        saveCanvas()
    }

    private func saveCanvas() {
        // The actual saving is handled by the representable when the drawing changes
    }
}

/// UIViewRepresentable wrapper for PKCanvasView
struct CanvasRepresentable: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    @Binding var canvasData: Data?
    let exercise: Exercise
    @Binding var exerciseAnswers: [String: Data]?

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 2)
        canvas.delegate = context.coordinator

        // Load existing drawing if available
        if let data = canvasData,
           let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }

        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update drawing if canvasData changes
        if let data = canvasData,
           let drawing = try? PKDrawing(data: data),
           uiView.drawing.dataRepresentation() != data {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasRepresentable

        init(_ parent: CanvasRepresentable) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Save the drawing data asynchronously to avoid modifying state during view update
            let drawing = canvasView.drawing
            let drawingData = drawing.dataRepresentation()

            DispatchQueue.main.async {
                self.parent.canvasData = drawingData

                // Save to Core Data
                self.parent.saveDrawing(data: drawingData)
            }
        }
    }

    private func saveDrawing(data: Data?) {
        // Get or create exercise answers dictionary
        var answers = exerciseAnswers ?? [:]

        // Store the drawing data for this exercise
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)"
        answers[key] = data

        // Update the binding (which will trigger save in the parent)
        exerciseAnswers = answers
    }
}
