//
//  PDFGenerationService.swift
//  Homework
//
//  Created by Claude on 18.10.2025.
//

import UIKit
import PDFKit
import PencilKit

/// Service for generating PDF documents from homework submissions
class PDFGenerationService {
    static let shared = PDFGenerationService()

    private init() {}

    /// Generates a PDF from homework submission
    ///
    /// - Parameters:
    ///   - assignment: The classroom assignment
    ///   - exercisesWithAnswers: Array of exercises paired with their answer data
    /// - Returns: PDF data
    func generateHomeworkPDF(
        assignment: ClassroomAssignment,
        exercisesWithAnswers: [(exercise: AIAnalysisService.Exercise, answer: Data?)]
    ) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let pdfData = try self.createPDF(
                        assignment: assignment,
                        exercisesWithAnswers: exercisesWithAnswers
                    )
                    continuation.resume(returning: pdfData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func createPDF(
        assignment: ClassroomAssignment,
        exercisesWithAnswers: [(exercise: AIAnalysisService.Exercise, answer: Data?)]
    ) throws -> Data {
        // Page setup
        let pageWidth: CGFloat = 612.0  // 8.5 inches at 72 DPI
        let pageHeight: CGFloat = 792.0 // 11 inches at 72 DPI
        let margin: CGFloat = 40.0
        let contentWidth = pageWidth - (margin * 2)

        // Create PDF context
        let pdfMetaData = [
            kCGPDFContextCreator: "Homework App",
            kCGPDFContextTitle: assignment.title
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        let data = renderer.pdfData { context in
            var currentY: CGFloat = margin

            // Start first page
            context.beginPage()

            // Title
            currentY = drawTitle(
                context: context,
                title: assignment.title,
                courseName: assignment.courseName,
                y: currentY,
                width: contentWidth,
                x: margin
            )

            currentY += 20

            // Draw each exercise and answer
            for (_, item) in exercisesWithAnswers.enumerated() {
                // Check if we need a new page
                if currentY > pageHeight - 200 {
                    context.beginPage()
                    currentY = margin
                }

                currentY = drawExercise(
                    context: context,
                    exerciseNumber: item.exercise.exerciseNumber,
                    fullContent: item.exercise.fullContent,
                    answerData: item.answer,
                    subject: item.exercise.subject,
                    imageData: assignment.imageData,
                    startY: item.exercise.startY,
                    endY: item.exercise.endY,
                    y: currentY,
                    width: contentWidth,
                    x: margin,
                    pageHeight: pageHeight,
                    pdfContext: context
                )

                currentY += 20
            }
        }

        return data
    }

    private func drawTitle(
        context: UIGraphicsPDFRendererContext,
        title: String,
        courseName: String,
        y: CGFloat,
        width: CGFloat,
        x: CGFloat
    ) -> CGFloat {
        var currentY = y

        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor.black
        ]
        let titleRect = CGRect(x: x, y: currentY, width: width, height: 30)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        currentY += 30

        // Course name
        let courseAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.gray
        ]
        let courseRect = CGRect(x: x, y: currentY, width: width, height: 20)
        courseName.draw(in: courseRect, withAttributes: courseAttributes)
        currentY += 20

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateString = "Submitted: \(dateFormatter.string(from: Date()))"
        let dateRect = CGRect(x: x, y: currentY, width: width, height: 20)
        dateString.draw(in: dateRect, withAttributes: courseAttributes)
        currentY += 20

        // Separator line
        context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
        context.cgContext.setLineWidth(1.0)
        context.cgContext.move(to: CGPoint(x: x, y: currentY))
        context.cgContext.addLine(to: CGPoint(x: x + width, y: currentY))
        context.cgContext.strokePath()
        currentY += 20

        return currentY
    }

    private func drawExercise(
        context: UIGraphicsPDFRendererContext,
        exerciseNumber: String,
        fullContent: String,
        answerData: Data?,
        subject: String?,
        imageData: Data?,
        startY: Double,
        endY: Double,
        y: CGFloat,
        width: CGFloat,
        x: CGFloat,
        pageHeight: CGFloat,
        pdfContext: UIGraphicsPDFRendererContext
    ) -> CGFloat {
        var currentY = y

        // Exercise header
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.systemBlue
        ]
        let headerText = "Exercise \(exerciseNumber)"
        let headerRect = CGRect(x: x, y: currentY, width: width, height: 25)
        headerText.draw(in: headerRect, withAttributes: headerAttributes)
        currentY += 30

        // Exercise image (if available)
        if let imageData = imageData,
           let fullImage = UIImage(data: imageData),
           let croppedImage = fullImage.crop(startY: startY, endY: endY, padding: 0.03) {
            let imageHeight: CGFloat = 120
            let imageWidth = width
            let imageRect = CGRect(x: x, y: currentY, width: imageWidth, height: imageHeight)

            // Draw image background
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(imageRect)

            // Draw image
            let aspectHeight = (croppedImage.size.height / croppedImage.size.width) * imageWidth
            let finalHeight = min(aspectHeight, imageHeight)
            let imageDrawRect = CGRect(x: x, y: currentY, width: imageWidth, height: finalHeight)
            croppedImage.draw(in: imageDrawRect)

            currentY += finalHeight + 10
        }

        // Exercise content
        let contentAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        let contentSize = (fullContent as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: contentAttributes,
            context: nil
        ).size
        let contentRect = CGRect(x: x, y: currentY, width: width, height: contentSize.height)
        fullContent.draw(in: contentRect, withAttributes: contentAttributes)
        currentY += contentSize.height + 15

        // Answer section
        let answerHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.darkGray
        ]
        let answerHeaderRect = CGRect(x: x, y: currentY, width: width, height: 20)
        "Your Answer:".draw(in: answerHeaderRect, withAttributes: answerHeaderAttributes)
        currentY += 25

        // Draw answer
        if let answerData = answerData,
           let drawing = try? PKDrawing(data: answerData) {
            // Use full canvas size (800x400) to match the canvas view
            let canvasSize = CGSize(width: 800, height: 400)
            let canvasAspectRatio = canvasSize.width / canvasSize.height

            // Calculate display dimensions
            let contentWidth = width - 20
            let answerHeight = contentWidth / canvasAspectRatio
            let answerWidth = width

            // Check if we need a new page for the answer
            if currentY + answerHeight + 20 > pageHeight - 40 {
                pdfContext.beginPage()
                currentY = 40
            }

            // Render full canvas with background
            let isMath = subject == "mathematics"
            let answerImage = renderFullCanvasImage(drawing: drawing, canvasSize: canvasSize, isMath: isMath)

            let answerRect = CGRect(x: x, y: currentY, width: answerWidth, height: answerHeight)

            // Draw border
            context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
            context.cgContext.setLineWidth(1.0)
            context.cgContext.stroke(answerRect)

            // Draw answer image
            answerImage.draw(in: answerRect)

            currentY += answerHeight + 10
        } else {
            // No answer provided
            let noAnswerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 11),
                .foregroundColor: UIColor.gray
            ]
            let noAnswerRect = CGRect(x: x, y: currentY, width: width, height: 20)
            "Not answered".draw(in: noAnswerRect, withAttributes: noAnswerAttributes)
            currentY += 25
        }

        // Separator line
        context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
        context.cgContext.setLineWidth(0.5)
        context.cgContext.move(to: CGPoint(x: x, y: currentY))
        context.cgContext.addLine(to: CGPoint(x: x + width, y: currentY))
        context.cgContext.strokePath()
        currentY += 5

        return currentY
    }

    /// Render the full canvas image with background, not cropped to drawing bounds
    private func renderFullCanvasImage(drawing: PKDrawing, canvasSize: CGSize, isMath: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            // Draw background
            if isMath {
                UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1.0).setFill()
            } else {
                UIColor.white.setFill()
            }
            context.fill(CGRect(origin: .zero, size: canvasSize))

            // Draw the full canvas drawing
            let drawingRect = CGRect(origin: .zero, size: canvasSize)
            drawing.image(from: drawingRect, scale: 1.0).draw(in: drawingRect)
        }
    }
}

// MARK: - Errors

enum PDFGenerationError: LocalizedError {
    case failedToGeneratePDF

    var errorDescription: String? {
        switch self {
        case .failedToGeneratePDF:
            return "Failed to generate PDF document"
        }
    }
}
