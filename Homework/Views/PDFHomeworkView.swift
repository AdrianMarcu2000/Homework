//
//  PDFHomeworkView.swift
//  Homework
//
//  View for displaying PDF homework with per-page analysis
//

import SwiftUI
import PDFKit
import OSLog
import CoreData

struct PDFHomeworkView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @State private var pdfDocument: PDFDocument?
    @State private var currentPage: Int = 0
    @State private var showAnalyzeSheet = false
    @State private var isAnalyzing = false
    @State private var analysisProgress: (current: Int, total: Int)?
    @State private var jumpToPageText = ""

    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    var totalPages: Int {
        pdfDocument?.pageCount ?? 0
    }

    var currentPageAnalysis: PDFPageAnalysis? {
        item.pdfPageAnalyses?.analysis(for: currentPage + 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let pdfDocument = pdfDocument {
                // Show exercises view if page is analyzed
                if let analysis = currentPageAnalysis {
                    VStack(spacing: 0) {
                        // Action buttons at the top (matching image homework style)
                        HStack(spacing: 12) {
                            // View Original button - shows the PDF page
                            Button(action: {
                                // Scroll to top to show PDF
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "doc.fill")
                                        .font(.title2)
                                    Text("View Page")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            // Analyze with Apple Intelligence button
                            if AIAnalysisService.shared.isModelAvailable {
                                Button(action: {
                                    analyzePageWithMethod(useCloud: false)
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "apple.logo")
                                            .font(.title2)
                                        Text("Apple AI")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.purple.opacity(0.1))
                                    .foregroundColor(.purple)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .disabled(isAnalyzing)
                            }

                            // Analyze with Google Gemini button (if cloud enabled)
                            if useCloudAnalysis {
                                Button(action: {
                                    analyzePageWithMethod(useCloud: true)
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "cloud.fill")
                                            .font(.title2)
                                        Text("Google AI")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundColor(.green)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .disabled(isAnalyzing)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        Divider()

                        // Exercises content
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                // Page navigation header
                                HStack(spacing: 12) {
                                    Button(action: previousPage) {
                                        Image(systemName: "chevron.left.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                    .disabled(currentPage == 0)

                                    Spacer()

                                    HStack(spacing: 8) {
                                        Text("Page")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)

                                        TextField("", text: $jumpToPageText)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 50)
                                            .textFieldStyle(.roundedBorder)
                                            .onSubmit {
                                                jumpToPage()
                                            }
                                            .overlay(
                                                Text(jumpToPageText.isEmpty ? "\(currentPage + 1)" : "")
                                                    .foregroundColor(.secondary)
                                                    .allowsHitTesting(false)
                                            )

                                        Text("of \(totalPages)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button(action: nextPage) {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                    .disabled(currentPage >= totalPages - 1)
                                }
                                .padding(.horizontal)

                                // PDF page preview
                                PDFPageView(
                                    document: pdfDocument,
                                    currentPage: $currentPage,
                                    height: 500
                                )
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .padding(.horizontal)

                                // Exercises
                                ForEach(analysis.analysisResult.exercises, id: \.exerciseNumber) { exercise in
                                    PDFExerciseCard(
                                        exercise: exercise,
                                        item: item,
                                        pageNumber: currentPage + 1
                                    )
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                } else {
                    // Page not analyzed - show full PDF with analyze buttons
                    VStack(spacing: 0) {
                        // Action buttons at the top
                        HStack(spacing: 12) {
                            // Analyze with Apple Intelligence button
                            if AIAnalysisService.shared.isModelAvailable {
                                Button(action: {
                                    analyzePageWithMethod(useCloud: false)
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "apple.logo")
                                            .font(.title2)
                                        Text("Apple AI")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.purple.opacity(0.1))
                                    .foregroundColor(.purple)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .disabled(isAnalyzing)
                            }

                            // Analyze with Google Gemini button (if cloud enabled)
                            if useCloudAnalysis {
                                Button(action: {
                                    analyzePageWithMethod(useCloud: true)
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "cloud.fill")
                                            .font(.title2)
                                        Text("Google AI")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundColor(.green)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .disabled(isAnalyzing)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        Divider()

                        // Full page PDF view
                        ZStack {
                            VStack(spacing: 0) {
                                // Page navigation
                                HStack(spacing: 12) {
                                    Button(action: previousPage) {
                                        Image(systemName: "chevron.left.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                    .disabled(currentPage == 0)

                                    Spacer()

                                    HStack(spacing: 8) {
                                        Text("Page")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)

                                        TextField("", text: $jumpToPageText)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 50)
                                            .textFieldStyle(.roundedBorder)
                                            .onSubmit {
                                                jumpToPage()
                                            }
                                            .overlay(
                                                Text(jumpToPageText.isEmpty ? "\(currentPage + 1)" : "")
                                                    .foregroundColor(.secondary)
                                                    .allowsHitTesting(false)
                                            )

                                        Text("of \(totalPages)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button(action: nextPage) {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                    .disabled(currentPage >= totalPages - 1)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 12)

                                // PDF fills remaining space
                                PDFPageView(
                                    document: pdfDocument,
                                    currentPage: $currentPage
                                )
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .padding(.horizontal)
                                .padding(.bottom, 20)
                            }

                            // Analysis progress overlay
                            if isAnalyzing {
                                Color.black.opacity(0.4)
                                    .edgesIgnoringSafeArea(.all)
                                VStack {
                                    if let progress = analysisProgress {
                                        ProgressView(value: Double(progress.current), total: Double(progress.total))
                                            .progressViewStyle(.linear)
                                            .frame(maxWidth: 300)
                                        Text("Analyzing segment \(progress.current) of \(progress.total)")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                    } else {
                                        ProgressView()
                                            .scaleEffect(1.5)
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Analyzing...")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.top)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading PDF...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("PDF Homework")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPDF()
        }
    }

    // MARK: - PDF Loading

    private func loadPDF() {
        guard let pdfData = try? item.loadPDFData() else {
            AppLogger.image.error("Failed to load PDF data for item")
            return
        }

        guard let document = PDFDocument(data: pdfData) else {
            AppLogger.image.error("Failed to create PDFDocument from data")
            return
        }

        self.pdfDocument = document
        AppLogger.image.info("Loaded PDF with \(document.pageCount) pages")
    }

    // MARK: - Page Navigation

    private func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
            AppLogger.ui.info("Navigated to page \(currentPage + 1)")
        }
    }

    private func nextPage() {
        if currentPage < totalPages - 1 {
            currentPage += 1
            AppLogger.ui.info("Navigated to page \(currentPage + 1)")
        }
    }

    private func jumpToPage() {
        guard let pageNumber = Int(jumpToPageText),
              pageNumber >= 1,
              pageNumber <= totalPages else {
            AppLogger.ui.warning("Invalid page number: \(jumpToPageText)")
            jumpToPageText = ""
            return
        }

        currentPage = pageNumber - 1
        AppLogger.ui.info("Jumped to page \(pageNumber)")
        jumpToPageText = ""
    }

    // MARK: - Page Analysis

    private func analyzePageWithMethod(useCloud: Bool) {
        guard let pdfDocument = pdfDocument,
              let page = pdfDocument.page(at: currentPage) else {
            AppLogger.image.error("No PDF page available for analysis")
            return
        }

        isAnalyzing = true
        AppLogger.ui.info("Starting analysis for PDF page \(currentPage + 1) with \(useCloud ? "cloud" : "local") AI")

        let shouldUseCloud = useCloud
        let pageNum = currentPage

        Task.detached(priority: .background) {
            // Render page as image
            let pageImage = await renderPageAsImage(page: page)

            // Extract text from PDF page
            let pageText = page.string ?? ""
            let hasNativeText = !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Perform OCR or use native text
            let ocrBlocks: [OCRService.OCRBlock]
            if hasNativeText {
                // Use native PDF text
                ocrBlocks = [OCRService.OCRBlock(text: pageText, y: 0.5)]
                await AppLogger.image.info("Using native PDF text (\(pageText.count) characters)")
            } else {
                // Perform OCR
                do {
                    let ocrResult = try await OCRService.shared.recognizeTextWithBlocks(from: pageImage)
                    ocrBlocks = ocrResult.blocks
                    await AppLogger.ocr.info("OCR completed with \(ocrBlocks.count) blocks")
                } catch {
                    await MainActor.run {
                        isAnalyzing = false
                    }
                    await AppLogger.ocr.error("OCR failed for PDF page", error: error)
                    return
                }
            }

            // Perform AI analysis
            let aiBlocks = ocrBlocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

            let analysisResult: Result<AIAnalysisService.AnalysisResult, Error>
            if shouldUseCloud {
                analysisResult = await CloudAnalysisService.shared.analyzeHomework(image: pageImage, ocrBlocks: aiBlocks)
            } else {
                analysisResult = await AIAnalysisService.shared.analyzeHomeworkWithSegments(
                    image: pageImage,
                    ocrBlocks: aiBlocks,
                    progressHandler: { current, total in
                        Task { @MainActor in
                            self.analysisProgress = (current, total)
                        }
                    }
                )
            }

            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = nil

                switch analysisResult {
                case .success(let analysis):
                    // Save analysis for this page
                    let pageAnalysis = PDFPageAnalysis(
                        pageNumber: pageNum + 1,
                        analysisResult: analysis,
                        analysisMethod: shouldUseCloud ? AnalysisMethod.cloudAI.rawValue : AnalysisMethod.appleAI.rawValue
                    )

                    var pdfAnalysis = item.pdfPageAnalyses ?? PDFHomeworkAnalysis()
                    pdfAnalysis.setAnalysis(pageAnalysis, for: pageNum + 1)
                    item.pdfPageAnalyses = pdfAnalysis

                    do {
                        try viewContext.save()
                        AppLogger.persistence.info("Saved analysis for PDF page \(pageNum + 1)")
                    } catch {
                        AppLogger.persistence.error("Failed to save page analysis", error: error)
                    }

                case .failure(let error):
                    AppLogger.ai.error("Analysis failed for PDF page", error: error)
                }
            }
        }
    }

    private func renderPageAsImage(page: PDFPage) async -> UIImage {
        let pageBounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let scaledSize = CGSize(
            width: pageBounds.width * scale,
            height: pageBounds.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: 0, y: pageBounds.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
}

// MARK: - PDF Page View

struct PDFPageView: View {
    let document: PDFDocument
    @Binding var currentPage: Int
    var height: CGFloat? = nil

    var body: some View {
        PDFPageRepresentable(document: document, pageIndex: currentPage)
            .frame(height: height)
            .frame(maxHeight: height == nil ? .infinity : height)
    }
}

struct PDFPageRepresentable: UIViewControllerRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeUIViewController(context: Context) -> PDFViewController {
        PDFViewController(document: document, pageIndex: pageIndex)
    }

    func updateUIViewController(_ uiViewController: PDFViewController, context: Context) {
        uiViewController.updatePage(pageIndex)
    }
}

class PDFViewController: UIViewController {
    private let pdfView = PDFView()
    private let document: PDFDocument
    private var currentPageIndex: Int

    init(document: PDFDocument, pageIndex: Int) {
        self.document = document
        self.currentPageIndex = pageIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.displayDirection = .horizontal
        pdfView.backgroundColor = .clear
        pdfView.usePageViewController(false)

        view.addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        pdfView.document = document
        updatePage(currentPageIndex)
    }

    func updatePage(_ pageIndex: Int) {
        guard currentPageIndex != pageIndex else { return }
        currentPageIndex = pageIndex

        if let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        }
    }
}
