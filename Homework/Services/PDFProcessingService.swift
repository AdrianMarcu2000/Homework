//
//  PDFProcessingService.swift
//  Homework
//
//  Created by Claude on 22.10.2025.
//

import UIKit
import PDFKit
import OSLog

/// Service for processing PDF files and extracting pages as images
class PDFProcessingService {
    static let shared = PDFProcessingService()

    private init() {}

    /// Loads a PDF from data and returns the page count
    func getPageCount(from pdfData: Data) -> Int? {
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            AppLogger.image.error("Failed to load PDF document")
            return nil
        }

        let pageCount = pdfDocument.pageCount
        AppLogger.image.info("PDF has \(pageCount) pages")
        return pageCount
    }

    /// Extracts a specific page from a PDF as an image
    ///
    /// - Parameters:
    ///   - pdfData: The PDF file data
    ///   - pageIndex: Zero-based page index (0 = first page)
    ///   - scale: Resolution scale (1.0 = 72 DPI, 2.0 = 144 DPI, 3.0 = 216 DPI)
    /// - Returns: UIImage of the extracted page
    func extractPage(from pdfData: Data, pageIndex: Int, scale: CGFloat = 2.0) -> UIImage? {
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            AppLogger.image.error("Failed to load PDF document")
            return nil
        }

        guard pageIndex >= 0 && pageIndex < pdfDocument.pageCount else {
            AppLogger.image.error("Page index \(pageIndex) out of bounds (0-\(pdfDocument.pageCount - 1))")
            return nil
        }

        guard let page = pdfDocument.page(at: pageIndex) else {
            AppLogger.image.error("Failed to get page at index \(pageIndex)")
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pageRect.width * scale, height: pageRect.height * scale))

        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))

            ctx.cgContext.translateBy(x: 0, y: renderer.format.bounds.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: ctx.cgContext)
        }

        AppLogger.image.info("Successfully extracted page \(pageIndex + 1) from PDF (scale: \(scale)x)")
        return image
    }

    /// Extracts multiple pages from a PDF as images
    ///
    /// - Parameters:
    ///   - pdfData: The PDF file data
    ///   - pageIndices: Array of zero-based page indices to extract
    ///   - scale: Resolution scale (1.0 = 72 DPI, 2.0 = 144 DPI, 3.0 = 216 DPI)
    /// - Returns: Array of UIImages corresponding to the requested pages
    func extractPages(from pdfData: Data, pageIndices: [Int], scale: CGFloat = 2.0) -> [UIImage] {
        var images: [UIImage] = []

        for pageIndex in pageIndices {
            if let image = extractPage(from: pdfData, pageIndex: pageIndex, scale: scale) {
                images.append(image)
            }
        }

        AppLogger.image.info("Extracted \(images.count) pages from PDF")
        return images
    }

    /// Combines multiple images into a single vertical image
    ///
    /// - Parameters:
    ///   - images: Array of images to combine
    ///   - spacing: Vertical spacing between images (default: 20)
    /// - Returns: Combined image
    func combineImages(_ images: [UIImage], spacing: CGFloat = 20) -> UIImage? {
        guard !images.isEmpty else {
            AppLogger.image.error("Cannot combine empty array of images")
            return nil
        }

        // Calculate total size
        let maxWidth = images.map { $0.size.width }.max() ?? 0
        let totalHeight = images.map { $0.size.height }.reduce(0, +) + (CGFloat(images.count - 1) * spacing)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: maxWidth, height: totalHeight))

        let combinedImage = renderer.image { ctx in
            // White background
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))

            var yOffset: CGFloat = 0

            for image in images {
                // Center image horizontally
                let xOffset = (maxWidth - image.size.width) / 2
                image.draw(at: CGPoint(x: xOffset, y: yOffset))
                yOffset += image.size.height + spacing
            }
        }

        AppLogger.image.info("Combined \(images.count) images into single image (width: \(maxWidth), height: \(totalHeight))")
        return combinedImage
    }

    /// Checks if a file is a PDF based on its MIME type or extension
    func isPDF(mimeType: String?, fileName: String?) -> Bool {
        // Check MIME type
        if let mimeType = mimeType?.lowercased() {
            if mimeType == "application/pdf" {
                return true
            }
        }

        // Check file extension
        if let fileName = fileName?.lowercased() {
            if fileName.hasSuffix(".pdf") {
                return true
            }
        }

        return false
    }

    /// Checks if a file is an image based on its MIME type or extension
    func isImage(mimeType: String?, fileName: String?) -> Bool {
        // Check MIME type
        if let mimeType = mimeType?.lowercased() {
            if mimeType.hasPrefix("image/") {
                return true
            }
        }

        // Check file extension
        if let fileName = fileName?.lowercased() {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp", "tiff", "tif"]
            for ext in imageExtensions {
                if fileName.hasSuffix(".\(ext)") {
                    return true
                }
            }
        }

        return false
    }
}
