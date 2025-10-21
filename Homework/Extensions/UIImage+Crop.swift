//
//  UIImage+Crop.swift
//  Homework
//
//  Created by Adrian Marcu on 09.10.2025.
//

import UIKit

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
}
