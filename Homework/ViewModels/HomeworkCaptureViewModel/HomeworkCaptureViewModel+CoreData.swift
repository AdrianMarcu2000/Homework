
//
//  HomeworkCaptureViewModel+CoreData.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import OSLog

extension HomeworkCaptureViewModel {
    /// Creates a new homework item with a processing status.
    ///
    /// - Parameters:
    ///   - image: The homework image.
    ///   - context: The Core Data context.
    /// - Returns: The newly created homework item.
    func createHomeworkItem(from image: UIImage, context: NSManagedObjectContext) -> Item {
        let newItem = Item(context: context)
        newItem.timestamp = Date()
        newItem.imageData = image.jpegData(compressionQuality: 0.8)
        newItem.analysisJSON = "inProgress" // Set status to inProgress

        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return newItem
    }

    /// Saves the current homework item with extracted text to Core Data.
    ///
    /// This method either creates a new Item entity or updates an existing one if in re-analysis mode.
    ///
    /// - Parameter context: The NSManagedObjectContext to use for saving
    func saveHomework(context: NSManagedObjectContext) {
        withAnimation {
            let item: Item

            // Check if we're re-analyzing an existing item
            if let existingItem = reanalyzingItem {
                item = existingItem
                AppLogger.persistence.info("Overwriting existing item analysis")
            } else {
                item = Item(context: context)
                item.timestamp = Date()

                // Convert UIImage to JPEG data for storage (only for new items)
                if let image = selectedImage,
                   let imageData = image.jpegData(compressionQuality: 0.8) {
                    item.imageData = imageData
                }
                AppLogger.persistence.info("Creating new homework item")
            }

            // Update extracted text (summary)
            item.extractedText = extractedText

            // Save AI analysis result as JSON
            if let analysis = analysisResult {
                AppLogger.persistence.info("Saving analysis with \(analysis.exercises.count) exercises")
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let jsonData = try encoder.encode(analysis)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        // Explicitly overwrite analysisJSON field
                        item.analysisJSON = jsonString
                        // Set analysis method based on whether cloud was used
                        item.analysisMethod = isCloudAnalysisInProgress ? AnalysisMethod.cloudAI.rawValue : AnalysisMethod.appleAI.rawValue
                        AppLogger.persistence.info("Analysis JSON saved successfully")
                    }
                } catch {
                    AppLogger.persistence.error("Failed to encode analysis result", error: error)
                }
            }

            do {
                try context.save()
                AppLogger.persistence.info("Core Data save successful")
                showTextSheet = false
            } catch {
                AppLogger.persistence.error("Failed to save homework", error: error)
            }
        }
    }
}
