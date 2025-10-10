//
//  ImageSegmentationService.swift
//  Homework
//
//  Created by Adrian Marcu on 10.10.2025.
//

import UIKit

/// Service for segmenting homework images into logical sections based on OCR block gaps
class ImageSegmentationService {
    static let shared = ImageSegmentationService()

    private init() {}

    /// Represents a segment of the homework page
    struct ImageSegment {
        let startY: Double
        let endY: Double
        let croppedImage: UIImage
        let ocrBlocks: [OCRService.OCRBlock]
    }

    /// Segments an image based on gaps in OCR blocks
    ///
    /// - Parameters:
    ///   - image: The full homework page image
    ///   - ocrBlocks: OCR blocks with Y coordinates
    ///   - gapThreshold: Minimum gap (normalized) to consider a segment boundary (default: 0.05 = 5%)
    /// - Returns: Array of image segments covering the entire image
    func segmentImage(
        image: UIImage,
        ocrBlocks: [OCRService.OCRBlock],
        gapThreshold: Double = 0.05
    ) -> [ImageSegment] {
        guard !ocrBlocks.isEmpty else { return [] }

        // Sort blocks by Y coordinate (bottom to top in Vision coordinates: 0=bottom, 1=top)
        let sortedBlocks = ocrBlocks.sorted { $0.y < $1.y }

        // Track gap positions (midpoints between segments)
        var gapMidpoints: [Double] = []
        var currentSegmentBlocks: [[OCRService.OCRBlock]] = [[sortedBlocks[0]]]
        var previousY = sortedBlocks[0].y

        // Group blocks into segments based on gaps
        for i in 1..<sortedBlocks.count {
            let block = sortedBlocks[i]
            let gap = block.y - previousY

            if gap > gapThreshold {
                // Found a gap - record the midpoint
                let midpoint = previousY + gap / 2.0
                gapMidpoints.append(midpoint)

                // Start new segment group
                currentSegmentBlocks.append([block])
            } else {
                // Continue current segment
                currentSegmentBlocks[currentSegmentBlocks.count - 1].append(block)
            }

            previousY = block.y
        }

        // Create segments with boundaries that cover the entire image
        var segments: [ImageSegment] = []

        for (index, blocks) in currentSegmentBlocks.enumerated() {
            guard !blocks.isEmpty else { continue }

            // Determine segment boundaries
            let firstBlockY = blocks.first!.y
            let lastBlockY = blocks.last!.y

            // Start: Use previous gap midpoint, or extend to top with padding
            let startY: Double
            if index == 0 {
                // First segment: start above first text
                startY = max(0.0, firstBlockY - 0.05)
            } else {
                // Use midpoint from previous gap
                startY = gapMidpoints[index - 1]
            }

            // End: Use next gap midpoint, or extend to bottom with padding
            let endY: Double
            if index == currentSegmentBlocks.count - 1 {
                // Last segment: extend below last text
                endY = min(1.0, lastBlockY + 0.05)
            } else {
                // Use midpoint to next gap
                endY = gapMidpoints[index]
            }

            // Create cropped image for this segment
            if let croppedImage = image.crop(
                startY: startY,
                endY: endY,
                padding: 0.0 // No additional padding since we already extended
            ) {
                segments.append(ImageSegment(
                    startY: startY,
                    endY: endY,
                    croppedImage: croppedImage,
                    ocrBlocks: blocks
                ))
            }
        }

        return segments
    }

    /// Merges small segments with adjacent ones to avoid over-segmentation
    ///
    /// - Parameters:
    ///   - segments: Array of image segments
    ///   - minSegmentHeight: Minimum normalized height (default: 0.03 = 3%)
    ///   - fullImage: The original full image for re-cropping
    /// - Returns: Merged segments
    func mergeSmallSegments(
        _ segments: [ImageSegment],
        minSegmentHeight: Double = 0.03,
        fullImage: UIImage
    ) -> [ImageSegment] {
        guard segments.count > 1 else { return segments }

        var merged: [ImageSegment] = []
        var i = 0

        while i < segments.count {
            let segment = segments[i]
            let height = segment.endY - segment.startY

            // If segment is too small and not the last one, merge with next
            if height < minSegmentHeight && i < segments.count - 1 {
                let nextSegment = segments[i + 1]
                var mergedBlocks = segment.ocrBlocks
                mergedBlocks.append(contentsOf: nextSegment.ocrBlocks)

                if let croppedImage = fullImage.crop(
                    startY: segment.startY,
                    endY: nextSegment.endY,
                    padding: 0.02
                ) {
                    merged.append(ImageSegment(
                        startY: segment.startY,
                        endY: nextSegment.endY,
                        croppedImage: croppedImage,
                        ocrBlocks: mergedBlocks
                    ))
                }

                i += 2 // Skip next segment since we merged it
            } else {
                merged.append(segment)
                i += 1
            }
        }

        return merged
    }
}
