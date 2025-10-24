//
//  PDFPageSelectorView.swift
//  Homework
//
//  Created by Claude on 22.10.2025.
//

import SwiftUI
import PDFKit
import OSLog

/// View for selecting pages from a PDF document (max 3 pages)
struct PDFPageSelectorView: View {
    let pdfData: Data
    let onConfirm: ([Int]) -> Void
    let onCancel: () -> Void

    @State private var selectedPages: Set<Int> = []
    @State private var pdfDocument: PDFDocument?
    @State private var pageCount: Int = 0
    @State private var thumbnails: [Int: UIImage] = [:]

    private let maxPages = 3

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with instructions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Select up to \(maxPages) pages for analysis")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if selectedPages.count > 0 {
                        Text("\(selectedPages.count) of \(maxPages) pages selected")
                            .font(.caption)
                            .foregroundColor(selectedPages.count == maxPages ? .orange : .blue)
                            .fontWeight(.medium)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))

                Divider()

                // Page grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(0..<pageCount, id: \.self) { pageIndex in
                            PageThumbnailCell(
                                pageIndex: pageIndex,
                                pageCount: pageCount,
                                isSelected: selectedPages.contains(pageIndex),
                                thumbnail: thumbnails[pageIndex]
                            ) {
                                togglePage(pageIndex)
                            }
                        }
                    }
                    .padding()
                }

                Divider()

                // Bottom action buttons
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }

                    Button(action: confirmSelection) {
                        Text("Analyze \(selectedPages.count) Page\(selectedPages.count == 1 ? "" : "s")")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Group {
                                    if selectedPages.isEmpty {
                                        Color.gray
                                    } else {
                                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                    }
                                }
                            )
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(selectedPages.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Select Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Select All") {
                        selectFirstThreePages()
                    }
                    .disabled(pageCount <= maxPages && selectedPages.count == pageCount)
                }
            }
        }
        .onAppear {
            loadPDF()
        }
    }

    // MARK: - Actions

    private func loadPDF() {
        guard let document = PDFDocument(data: pdfData) else {
            AppLogger.image.error("Failed to load PDF document in page selector")
            return
        }

        pdfDocument = document
        pageCount = document.pageCount
        AppLogger.ui.info("Loaded PDF with \(pageCount) pages for selection")

        // Generate thumbnails for all pages
        DispatchQueue.global(qos: .userInitiated).async {
            for pageIndex in 0..<pageCount {
                if let thumbnail = generateThumbnail(for: pageIndex, document: document) {
                    DispatchQueue.main.async {
                        thumbnails[pageIndex] = thumbnail
                    }
                }
            }
        }

        // Auto-select first 3 pages if more than 3 pages
        if pageCount > maxPages {
            selectFirstThreePages()
        }
    }

    private func generateThumbnail(for pageIndex: Int, document: PDFDocument) -> UIImage? {
        guard let page = document.page(at: pageIndex) else { return nil }

        let pageRect = page.bounds(for: .mediaBox)
        let thumbnailSize = CGSize(width: 200, height: 200 * (pageRect.height / pageRect.width))

        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: thumbnailSize))

            let scale = thumbnailSize.width / pageRect.width
            ctx.cgContext.translateBy(x: 0, y: thumbnailSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    private func togglePage(_ pageIndex: Int) {
        if selectedPages.contains(pageIndex) {
            selectedPages.remove(pageIndex)
            AppLogger.ui.info("Deselected page \(pageIndex + 1)")
        } else {
            if selectedPages.count < maxPages {
                selectedPages.insert(pageIndex)
                AppLogger.ui.info("Selected page \(pageIndex + 1)")
            } else {
                AppLogger.ui.info("Cannot select more than \(maxPages) pages")
            }
        }
    }

    private func selectFirstThreePages() {
        selectedPages = Set(0..<min(maxPages, pageCount))
        AppLogger.ui.info("Auto-selected first \(selectedPages.count) pages")
    }

    private func confirmSelection() {
        let sortedPages = selectedPages.sorted()
        AppLogger.ui.info("User confirmed selection of \(sortedPages.count) pages: \(sortedPages.map { $0 + 1 })")
        onConfirm(sortedPages)
    }
}

// MARK: - Page Thumbnail Cell

private struct PageThumbnailCell: View {
    let pageIndex: Int
    let pageCount: Int
    let isSelected: Bool
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    // Thumbnail or placeholder
                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                            )
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 150)
                            .cornerRadius(8)
                            .overlay(
                                ProgressView()
                            )
                    }

                    // Selection indicator
                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .background(
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 24, height: 24)
                                    )
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }
                }

                // Page number
                Text("Page \(pageIndex + 1)")
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    // Create a simple PDF for preview
    let pdfData = Data()
    PDFPageSelectorView(
        pdfData: pdfData,
        onConfirm: { pages in
            print("Selected pages: \(pages)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
