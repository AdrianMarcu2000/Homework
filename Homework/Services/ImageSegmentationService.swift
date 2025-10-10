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
    /// - Returns: Array of image segments
    func segmentImage(
        image: UIImage,
        ocrBlocks: [OCRService.OCRBlock],
        gapThreshold: Double = 0.05
    ) -> [ImageSegment] {
        guard !ocrBlocks.isEmpty else { return [] }

        // Sort blocks by Y coordinate (top to bottom in Vision coordinates)
        let sortedBlocks = ocrBlocks.sorted { $0.y < $1.y }

        var segments: [ImageSegment] = []
        var currentSegmentStart = sortedBlocks[0].y
        var currentSegmentBlocks: [OCRService.OCRBlock] = [sortedBlocks[0]]
        var previousY = sortedBlocks[0].y

        for i in 1..<sortedBlocks.count {
            let block = sortedBlocks[i]
            let gap = block.y - previousY

            // If we detect a large gap, end current segment and start new one
            if gap > gapThreshold {
                // Create segment from accumulated blocks
                if !currentSegmentBlocks.isEmpty {
                    let segmentEndY = previousY
                    if let croppedImage = image.crop(
                        startY: currentSegmentStart,
                        endY: segmentEndY,
                        padding: 0.02
                    ) {
                        segments.append(ImageSegment(
                            startY: currentSegmentStart,
                            endY: segmentEndY,
                            croppedImage: croppedImage,
                            ocrBlocks: currentSegmentBlocks
                        ))
                    }
                }

                // Start new segment
                currentSegmentStart = block.y
                currentSegmentBlocks = [block]
            } else {
                // Continue current segment
                currentSegmentBlocks.append(block)
            }

            previousY = block.y
        }

        // Add final segment
        if !currentSegmentBlocks.isEmpty {
            let segmentEndY = sortedBlocks.last!.y
            if let croppedImage = image.crop(
                startY: currentSegmentStart,
                endY: segmentEndY,
                padding: 0.02
            ) {
                segments.append(ImageSegment(
                    startY: currentSegmentStart,
                    endY: segmentEndY,
                    croppedImage: croppedImage,
                    ocrBlocks: currentSegmentBlocks
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
