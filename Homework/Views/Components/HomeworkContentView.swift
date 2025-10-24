//
//  HomeworkContentView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

/// Shared homework content display (image or text)
struct HomeworkContentView<Homework: AnalyzableHomework>: View {
    var homework: Homework

    var body: some View {
        let _ = {
            let hasImageData = homework.imageData != nil
            let imageDataSize = homework.imageData?.count ?? 0
            let hasExtractedText = homework.extractedText != nil
            let extractedTextLength = homework.extractedText?.count ?? 0
            let hasDescription = (homework as? ClassroomAssignment)?.coursework.description != nil
            let descriptionLength = (homework as? ClassroomAssignment)?.coursework.description?.count ?? 0
            let materialsCount = (homework as? ClassroomAssignment)?.coursework.materials?.count ?? 0

            AppLogger.ui.info("📄 HomeworkContentView rendering - imageData: \(hasImageData) (\(imageDataSize) bytes), extractedText: \(hasExtractedText) (\(extractedTextLength) chars), description: \(hasDescription) (\(descriptionLength) chars), materials: \(materialsCount)")
        }()

        VStack(spacing: 20) {
            // Show assignment description first if it's a ClassroomAssignment
            if let assignment = homework as? ClassroomAssignment,
               let description = assignment.coursework.description,
               !description.isEmpty {
                let _ = AppLogger.ui.info("✅ Displaying assignment description (\(description.count) chars)")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Assignment")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Text(description)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
            }

            // Show attachments section for ClassroomAssignments
            if let assignment = homework as? ClassroomAssignment,
               let materials = assignment.coursework.materials, !materials.isEmpty {
                let _ = AppLogger.ui.info("📎 Displaying \(materials.count) attachment preview cards")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Attachments")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    // Show preview cards for all materials
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(Array(materials.enumerated()), id: \.offset) { index, material in
                                let materialID = generateMaterialID(assignment: assignment, material: material, index: index)
                                let filename = material.driveFile?.driveFile.title ?? material.link?.title ?? material.youtubeVideo?.title ?? material.form?.title ?? "unknown"
                                NavigationLink(destination: AttachmentViewerView(material: material)) {
                                    AttachmentPreviewCard(
                                        material: material,
                                        assignment: assignment
                                    )
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    AppLogger.ui.info("User tapped attachment preview: \(filename)")
                                })
                                .id(materialID)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)
            }

            // Show downloaded image content if available (only for non-ClassroomAssignment items)
            if !(homework is ClassroomAssignment),
               let imageData = homework.imageData,
               let uiImage = UIImage(data: imageData) {
                let _ = AppLogger.ui.info("✅ Displaying downloaded image (\(imageData.count) bytes)")

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .padding(.horizontal)
            } else if let extractedText = homework.extractedText, !extractedText.isEmpty, !(homework is ClassroomAssignment) {
                // For non-ClassroomAssignment items, show extracted text
                let _ = AppLogger.ui.info("✅ Displaying extracted text content (\(extractedText.count) chars)")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Extracted Text")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Text(extractedText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
            } else if !(homework is ClassroomAssignment) || (homework as? ClassroomAssignment)?.coursework.description?.isEmpty ?? true {
                // Only show "No Content" if there's truly no content
                let _ = AppLogger.ui.info("⚠️ Showing 'No Content' - no description, imageData, or extractedText available")
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Content")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
    }

    /// Generate unique ID for material to prevent SwiftUI view reuse across assignments
    private func generateMaterialID(assignment: ClassroomAssignment, material: Material, index: Int) -> String {
        let assignmentID = assignment.id
        if let driveFile = material.driveFile?.driveFile {
            return "\(assignmentID)_\(driveFile.id)_\(index)"
        } else if let link = material.link {
            return "\(assignmentID)_\(link.url.hashValue)_\(index)"
        } else if let video = material.youtubeVideo {
            return "\(assignmentID)_\(video.id)_\(index)"
        } else if let form = material.form {
            return "\(assignmentID)_\(form.formUrl.hashValue)_\(index)"
        }
        return "\(assignmentID)_\(index)"
    }
}
