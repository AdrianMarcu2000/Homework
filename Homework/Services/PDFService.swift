//
//  PDFService.swift
//  Homework
//
//  Service for PDF handling, page extraction, and text extraction
//

import Foundation
import PDFKit
import UIKit
import OSLog

class PDFService {
    static let shared = PDFService()

    private init() {}

    // MARK: - PDF Page Data

    struct PDFPageData {
        let pageNumber: Int
        let pageImage: UIImage
        let extractedText: String?
        let hasNativeText: Bool // true if PDF has native text, false if needs OCR
    }

    // MARK: - PDF Loading

    /// Load a PDF document from data
    func loadPDF(from data: Data) -> PDFDocument? {
        AppLogger.image.info("Loading PDF document from data (\(data.count) bytes)")
        guard let document = PDFDocument(data: data) else {
            AppLogger.image.error("Failed to create PDFDocument from data")
            return nil
        }
        AppLogger.image.info("PDF loaded successfully with \(document.pageCount) pages")
        return document
    }

    // MARK: - Page Extraction

    /// Extract all pages from PDF as PDFPageData array
    func extractPages(from document: PDFDocument) -> [PDFPageData] {
        AppLogger.image.info("Extracting pages from PDF with \(document.pageCount) pages")

        var pages: [PDFPageData] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                AppLogger.image.warning("Failed to extract page \(pageIndex + 1)")
                continue
            }

            // Extract text from PDF page
            let text = page.string
            let hasNativeText = text != nil && !text!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Render page as image
            guard let pageImage = renderPageAsImage(page: page) else {
                AppLogger.image.warning("Failed to render page \(pageIndex + 1) as image")
                continue
            }

            let pageData = PDFPageData(
                pageNumber: pageIndex + 1,
                pageImage: pageImage,
                extractedText: text,
                hasNativeText: hasNativeText
            )

            pages.append(pageData)

            AppLogger.image.info("Extracted page \(pageIndex + 1): hasNativeText=\(hasNativeText), textLength=\(text?.count ?? 0)")
        }

        return pages
    }

    /// Extract a single page from PDF
    func extractPage(from document: PDFDocument, pageIndex: Int) -> PDFPageData? {
        AppLogger.image.info("Extracting single page \(pageIndex + 1) from PDF")

        guard pageIndex >= 0 && pageIndex < document.pageCount else {
            AppLogger.image.error("Invalid page index: \(pageIndex + 1) (PDF has \(document.pageCount) pages)")
            return nil
        }

        guard let page = document.page(at: pageIndex) else {
            AppLogger.image.error("Failed to get page at index \(pageIndex)")
            return nil
        }

        // Extract text from PDF page
        let text = page.string
        let hasNativeText = text != nil && !text!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Render page as image
        guard let pageImage = renderPageAsImage(page: page) else {
            AppLogger.image.error("Failed to render page \(pageIndex + 1) as image")
            return nil
        }

        let pageData = PDFPageData(
            pageNumber: pageIndex + 1,
            pageImage: pageImage,
            extractedText: text,
            hasNativeText: hasNativeText
        )

        AppLogger.image.info("Page \(pageIndex + 1) extracted: hasNativeText=\(hasNativeText), textLength=\(text?.count ?? 0)")

        return pageData
    }

    // MARK: - Page Rendering

    /// Render a PDF page as UIImage at high resolution
    private func renderPageAsImage(page: PDFPage) -> UIImage? {
        let pageBounds = page.bounds(for: .mediaBox)

        // Use 2x scale for high quality rendering
        let scale: CGFloat = 2.0
        let scaledSize = CGSize(
            width: pageBounds.width * scale,
            height: pageBounds.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: scaledSize)

        let image = renderer.image { context in
            // Fill white background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))

            // Scale context
            context.cgContext.scaleBy(x: scale, y: scale)

            // Flip coordinate system to match PDF coordinates
            context.cgContext.translateBy(x: 0, y: pageBounds.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)

            // Render PDF page
            page.draw(with: .mediaBox, to: context.cgContext)
        }

        return image
    }

    // MARK: - Text Extraction

    /// Extract text from all pages concatenated
    func extractAllText(from document: PDFDocument) -> String {
        AppLogger.image.info("Extracting all text from PDF")

        var allText = ""

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }

            allText += "--- Page \(pageIndex + 1) ---\n"
            allText += pageText
            allText += "\n\n"
        }

        AppLogger.image.info("Extracted \(allText.count) characters from \(document.pageCount) pages")

        return allText
    }
}
