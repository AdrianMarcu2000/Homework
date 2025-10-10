//
//  MathNotebookCanvasView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import PencilKit
import CoreData

/// A drawing canvas styled like a math notebook with grid paper
struct MathNotebookCanvasView: View {
    let exercise: AIAnalysisService.Exercise
    let homeworkItem: Item
    @Binding var canvasData: Data?

    @State private var canvas = PKCanvasView()
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "function")
                    .foregroundColor(.blue)
                Text("Show Your Work")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
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

            // Canvas with math notebook background
            ZStack {
                // Grid paper background
                MathNotebookBackground()

                MathCanvasRepresentable(
                    canvas: $canvas,
                    canvasData: $canvasData,
                    exercise: exercise,
                    homeworkItem: homeworkItem
                )
            }
            .frame(height: isExpanded ? 500 : 250)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )

            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    Text(isExpanded ? "Collapse" : "Expand Canvas")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
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

/// Math notebook grid paper background
struct MathNotebookBackground: View {
    let gridSize: CGFloat = 20
    let lineWidth: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Paper background color (slightly cream/beige)
                Color(red: 0.98, green: 0.97, blue: 0.95)

                // Vertical grid lines
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height

                    var x: CGFloat = gridSize
                    while x < width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                        x += gridSize
                    }
                }
                .stroke(Color.blue.opacity(0.15), lineWidth: lineWidth)

                // Horizontal grid lines
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height

                    var y: CGFloat = gridSize
                    while y < height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                        y += gridSize
                    }
                }
                .stroke(Color.blue.opacity(0.15), lineWidth: lineWidth)

                // Left margin line (red line like in notebooks)
                Path { path in
                    let marginX: CGFloat = 40
                    path.move(to: CGPoint(x: marginX, y: 0))
                    path.addLine(to: CGPoint(x: marginX, y: geometry.size.height))
                }
                .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
            }
        }
    }
}

/// UIViewRepresentable wrapper for PKCanvasView with math notebook styling
struct MathCanvasRepresentable: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    @Binding var canvasData: Data?
    let exercise: AIAnalysisService.Exercise
    let homeworkItem: Item

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        // Use pencil tool for more natural math writing
        canvas.tool = PKInkingTool(.pencil, color: .black, width: 1.5)
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear // Transparent to show grid background
        canvas.isOpaque = false

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
        var parent: MathCanvasRepresentable

        init(_ parent: MathCanvasRepresentable) {
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
        guard let context = homeworkItem.managedObjectContext else { return }

        context.perform {
            // Get or create exercise answers dictionary
            var answers = homeworkItem.exerciseAnswers ?? [:]

            // Store the drawing data for this exercise
            let key = "\(exercise.exerciseNumber)_\(exercise.startY)"
            answers[key] = data

            // Save back to Core Data
            homeworkItem.exerciseAnswers = answers

            do {
                try context.save()
            } catch {
                print("Error saving drawing: \(error)")
            }
        }
    }
}

#Preview {
    let mockExercise = AIAnalysisService.Exercise(
        exerciseNumber: "1",
        type: "mathematical",
        fullContent: "Solve: 2x + 5 = 15",
        startY: 0.3,
        endY: 0.35
    )

    let mockItem: Item = {
        let context = PersistenceController.preview.container.viewContext
        let item = Item(context: context)
        item.timestamp = Date()
        return item
    }()

    return MathNotebookCanvasView(
        exercise: mockExercise,
        homeworkItem: mockItem,
        canvasData: .constant(nil)
    )
    .padding()
}
