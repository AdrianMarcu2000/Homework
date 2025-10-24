//
//  UIImage+Crop.swift
//  Homework
//
//  Created by Adrian Marcu on 09.10.2025.
//

import UIKit
import OSLog

extension UIImage {
    /// Crops the image based on normalized Y coordinates (0.0 to 1.0)
    /// where 0.0 is the TOP and 1.0 is the BOTTOM (standard top-to-bottom reading order).
    ///
    /// - Parameters:
    ///   - startY: Normalized Y coordinate where the crop should start (0.0 = top, 1.0 = bottom). This is the top edge.
    ///   - endY: Normalized Y coordinate where the crop should end (0.0 = top, 1.0 = bottom). This is the bottom edge.
    ///   - padding: Additional padding to add around the crop area (default: 0.02 = 2%)
    /// - Returns: Cropped UIImage, or nil if cropping fails
    func crop(startY: Double, endY: Double, padding: Double = 0.02) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let imageHeight = CGFloat(cgImage.height)
        let imageWidth = CGFloat(cgImage.width)

        // Coordinate system: Y=0 is top, Y=1 is bottom (matches UIKit/CGImage top-left origin)
        // startY is the top edge (smaller value), endY is the bottom edge (larger value)

        let topY = min(startY, endY)  // Ensure top is the smaller value
        let bottomY = max(startY, endY)  // Ensure bottom is the larger value

        let cropStartY = CGFloat(topY) * imageHeight  // Top of crop in pixels
        let cropEndY = CGFloat(bottomY) * imageHeight  // Bottom of crop in pixels

        // Calculate height and apply padding
        let paddingPixels = CGFloat(padding) * imageHeight
        let adjustedStartY = max(0, cropStartY - paddingPixels)
        let adjustedEndY = min(imageHeight, cropEndY + paddingPixels)
        let cropHeight = adjustedEndY - adjustedStartY

        // Create crop rectangle (full width, calculated height)
        let cropRect = CGRect(
            x: 0,
            y: adjustedStartY,
            width: imageWidth,
            height: cropHeight
        )

        // Perform the crop
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: self.scale, orientation: self.imageOrientation)
    }

    // MARK: - Image Resizing

    /// Preset sizes for different use cases
    enum ImageSizePreset {
        case preview        // 280×373 for preview cards (aspect ratio constrained)
        case thumbnail      // 120×100 for exercise thumbnails
        case detailView     // 1200px max for main detail view display
        case llmProcessing  // 2048px max for LLM analysis

        var targetSize: CGSize? {
            switch self {
            case .preview: return CGSize(width: 280, height: 373)
            case .thumbnail: return CGSize(width: 120, height: 100)
            case .detailView: return nil  // Use maxDimension instead
            case .llmProcessing: return nil  // Use maxDimension instead
            }
        }

        var maxDimension: CGFloat {
            switch self {
            case .preview: return 373  // Use height as constraint
            case .thumbnail: return 120
            case .detailView: return 1200
            case .llmProcessing: return 2048
            }
        }

        var maxFileSize: Int {
            switch self {
            case .preview: return 500 * 1024      // 500KB for previews
            case .thumbnail: return 100 * 1024     // 100KB for thumbnails
            case .detailView: return 2 * 1024 * 1024  // 2MB for detail view
            case .llmProcessing: return 4 * 1024 * 1024  // 4MB for LLM
            }
        }

        var initialQuality: CGFloat {
            switch self {
            case .preview, .thumbnail: return 0.7
            case .detailView: return 0.85
            case .llmProcessing: return 0.8
            }
        }
    }

    /// Resizes image for specific use case with optimal settings
    ///
    /// - Parameter preset: The use case preset (preview, detailView, llmProcessing, etc.)
    /// - Returns: Resized and optimized image
    func resized(for preset: ImageSizePreset) -> UIImage {
        // If preset has a target size (like preview/thumbnail), use aspect-fit resizing
        if let targetSize = preset.targetSize {
            return resizedToFit(
                targetSize: targetSize,
                maxFileSize: preset.maxFileSize,
                initialQuality: preset.initialQuality
            )
        } else {
            // Otherwise use max dimension resizing
            return resizedForDisplay(
                maxDimension: preset.maxDimension,
                maxFileSize: preset.maxFileSize,
                initialQuality: preset.initialQuality
            )
        }
    }

    /// Resizes image to safe dimensions for LLM processing
    /// Ensures images are not too large in dimensions or file size
    ///
    /// - Parameters:
    ///   - maxDimension: Maximum width or height (default: 2048 pixels)
    ///   - maxFileSize: Maximum JPEG file size in bytes (default: 4MB)
    ///   - initialQuality: Starting compression quality (default: 0.8)
    /// - Returns: Resized image, or original if already within limits
    func resizedForLLM(
        maxDimension: CGFloat = 2048,
        maxFileSize: Int = 4 * 1024 * 1024,  // 4MB
        initialQuality: CGFloat = 0.8
    ) -> UIImage {
        return resizedForDisplay(
            maxDimension: maxDimension,
            maxFileSize: maxFileSize,
            initialQuality: initialQuality
        )
    }

    /// Resizes image to fit within target size while maintaining aspect ratio
    ///
    /// - Parameters:
    ///   - targetSize: Target container size to fit within
    ///   - maxFileSize: Maximum JPEG file size in bytes
    ///   - initialQuality: Starting compression quality
    /// - Returns: Resized image that fits within target size
    private func resizedToFit(
        targetSize: CGSize,
        maxFileSize: Int,
        initialQuality: CGFloat
    ) -> UIImage {
        let originalSize = self.size
        let originalWidth = originalSize.width
        let originalHeight = originalSize.height

        // Calculate aspect fit scale (image should fit entirely within target size)
        let widthScale = targetSize.width / originalWidth
        let heightScale = targetSize.height / originalHeight
        let scale = min(widthScale, heightScale)  // Use smaller scale to fit both dimensions

        // Calculate new size maintaining aspect ratio
        let newWidth = originalWidth * scale
        let newHeight = originalHeight * scale
        let newSize = CGSize(width: newWidth, height: newHeight)

        // Only resize if new size is smaller than original
        let needsResize = scale < 1.0

        var processedImage = self

        if needsResize {
            AppLogger.image.info("Resizing image from \(Int(originalWidth))×\(Int(originalHeight)) to \(Int(newWidth))×\(Int(newHeight)) (aspect-fit to \(Int(targetSize.width))×\(Int(targetSize.height)))")

            let renderer = UIGraphicsImageRenderer(size: newSize)
            processedImage = renderer.image { context in
                self.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        // Compress to meet file size constraint
        var quality = initialQuality
        var imageData = processedImage.jpegData(compressionQuality: quality)

        while let data = imageData, data.count > maxFileSize && quality > 0.1 {
            quality -= 0.1
            imageData = processedImage.jpegData(compressionQuality: quality)
            AppLogger.image.info("Compressing image: quality=\(String(format: "%.1f", quality)), size=\(data.count / 1024)KB")
        }

        if let data = imageData, let compressedImage = UIImage(data: data) {
            let finalSizeKB = data.count / 1024
            if needsResize || quality < initialQuality {
                AppLogger.image.info("Image prepared: \(Int(compressedImage.size.width))×\(Int(compressedImage.size.height)), \(finalSizeKB)KB, quality=\(String(format: "%.1f", quality))")
            }
            return compressedImage
        }

        return processedImage
    }

    /// Internal method that performs the actual resizing by max dimension
    private func resizedForDisplay(
        maxDimension: CGFloat,
        maxFileSize: Int,
        initialQuality: CGFloat
    ) -> UIImage {
        let originalSize = self.size
        let originalWidth = originalSize.width
        let originalHeight = originalSize.height

        // Check if resizing needed based on dimensions
        let needsResize = originalWidth > maxDimension || originalHeight > maxDimension

        var processedImage = self

        // Step 1: Resize dimensions if needed
        if needsResize {
            let scale = min(maxDimension / originalWidth, maxDimension / originalHeight)
            let newWidth = originalWidth * scale
            let newHeight = originalHeight * scale
            let newSize = CGSize(width: newWidth, height: newHeight)

            AppLogger.image.info("Resizing image from \(Int(originalWidth))x\(Int(originalHeight)) to \(Int(newWidth))x\(Int(newHeight)) for LLM")

            let renderer = UIGraphicsImageRenderer(size: newSize)
            processedImage = renderer.image { context in
                self.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        // Step 2: Check file size and compress if needed
        var quality = initialQuality
        var imageData = processedImage.jpegData(compressionQuality: quality)

        while let data = imageData, data.count > maxFileSize && quality > 0.1 {
            quality -= 0.1
            imageData = processedImage.jpegData(compressionQuality: quality)
            AppLogger.image.info("Compressing image: quality=\(String(format: "%.1f", quality)), size=\(data.count / 1024)KB")
        }

        if let data = imageData, let compressedImage = UIImage(data: data) {
            let finalSizeKB = data.count / 1024
            if needsResize || quality < initialQuality {
                AppLogger.image.info("Image prepared for LLM: \(Int(compressedImage.size.width))x\(Int(compressedImage.size.height)), \(finalSizeKB)KB, quality=\(String(format: "%.1f", quality))")
            }
            return compressedImage
        }

        // Fallback to processed image if compression fails
        return processedImage
    }

    /// Validates if image is within safe limits for LLM processing
    /// - Parameters:
    ///   - maxDimension: Maximum width or height
    ///   - maxFileSize: Maximum file size in bytes
    /// - Returns: Tuple of (isValid, reason)
    func validateForLLM(maxDimension: CGFloat = 2048, maxFileSize: Int = 4 * 1024 * 1024) -> (isValid: Bool, reason: String?) {
        let width = self.size.width
        let height = self.size.height

        if width > maxDimension || height > maxDimension {
            return (false, "Image dimensions (\(Int(width))x\(Int(height))) exceed maximum (\(Int(maxDimension))px)")
        }

        if let data = self.jpegData(compressionQuality: 0.8), data.count > maxFileSize {
            let sizeMB = Double(data.count) / (1024.0 * 1024.0)
            let maxMB = Double(maxFileSize) / (1024.0 * 1024.0)
            return (false, String(format: "Image file size (%.1fMB) exceeds maximum (%.1fMB)", sizeMB, maxMB))
        }

        return (true, nil)
    }
}
