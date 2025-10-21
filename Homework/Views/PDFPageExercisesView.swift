//
//  PDFPageExercisesView.swift
//  Homework
//
//  View for displaying and answering exercises for a specific PDF page
//

import SwiftUI
import CoreData
import OSLog

struct PDFPageExercisesView: View {
    @ObservedObject var item: Item
    let pageNumber: Int

    @Environment(\.managedObjectContext) private var viewContext

    var pageAnalysis: PDFPageAnalysis? {
        item.pdfPageAnalyses?.analysis(for: pageNumber)
    }

    var body: some View {
        ScrollView {
            if let analysis = pageAnalysis {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Page \(pageNumber) Exercises")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.horizontal)

                    ForEach(analysis.analysisResult.exercises, id: \.exerciseNumber) { exercise in
                        PDFExerciseCard(
                            exercise: exercise,
                            item: item,
                            pageNumber: pageNumber
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Page not analyzed")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Page \(pageNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Exercise card for PDF pages - exercises don't have images since the whole page is the PDF
struct PDFExerciseCard: View {
    let exercise: AIAnalysisService.Exercise
    @ObservedObject var item: Item
    let pageNumber: Int

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        // Use ExerciseCardContent without images (PDF pages don't crop to exercises)
        ExerciseCardContent(
            exercise: exercise,
            imageData: nil, // No cropped image for PDF exercises
            exerciseAnswers: Binding(
                get: { item.exerciseAnswers },
                set: { newValue in
                    item.exerciseAnswers = newValue
                    if let context = item.managedObjectContext {
                        try? context.save()
                    }
                }
            )
        )
    }
}
