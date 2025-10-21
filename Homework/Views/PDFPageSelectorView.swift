//
//  PDFPageSelectorView.swift
//  Homework
//
//  View for selecting a page from a multi-page PDF document
//

import SwiftUI
import OSLog

struct PDFPageSelectorView: View {
    let pages: [PDFService.PDFPageData]
    let onPageSelected: (PDFService.PDFPageData) -> Void

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, pageData in
                        PDFPageCard(pageData: pageData) {
                            AppLogger.ui.info("User selected page \(pageData.pageNumber) from PDF")
                            onPageSelected(pageData)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Select Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        AppLogger.ui.info("User cancelled PDF page selection")
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct PDFPageCard: View {
    let pageData: PDFService.PDFPageData
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Page thumbnail
            Image(uiImage: pageData.pageImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            // Page info
            VStack(alignment: .leading, spacing: 4) {
                Text("Page \(pageData.pageNumber)")
                    .font(.headline)

                HStack {
                    if pageData.hasNativeText {
                        Label("Native Text", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Needs OCR", systemImage: "camera.viewfinder")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    if let text = pageData.extractedText {
                        Text("\(text.count) chars")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .onTapGesture {
            onTap()
        }
    }
}

#Preview {
    PDFPageSelectorView(
        pages: [],
        onPageSelected: { _ in }
    )
}
