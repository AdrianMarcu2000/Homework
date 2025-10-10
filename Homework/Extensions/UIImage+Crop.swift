//
//  UIImage+Crop.swift
//  Homework
//
//  Created by Adrian Marcu on 09.10.2025.
//

import UIKit

extension UIImage {
    /// Crops the image based on normalized Y coordinates (0.0 to 1.0)
    /// where 0.0 is the top and 1.0 is the bottom of the image.
    ///
    /// - Parameters:
    ///   - startY: Normalized Y coordinate where the crop should start (0.0 = top)
    ///   - endY: Normalized Y coordinate where the crop should end (1.0 = bottom)
    ///   - padding: Additional padding to add around the crop area (default: 0.02 = 2%)
    /// - Returns: Cropped UIImage, or nil if cropping fails
    func crop(startY: Double, endY: Double, padding: Double = 0.02) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let imageHeight = CGFloat(cgImage.height)
        let imageWidth = CGFloat(cgImage.width)

        // Convert normalized coordinates to pixel coordinates
        // Note: Vision framework uses bottom-left origin, so we need to flip Y
        let cropStartY = CGFloat(1.0 - endY) * imageHeight
        let cropEndY = CGFloat(1.0 - startY) * imageHeight

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
}
