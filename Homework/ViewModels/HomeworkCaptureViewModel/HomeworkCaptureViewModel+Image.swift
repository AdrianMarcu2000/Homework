
//
//  HomeworkCaptureViewModel+Image.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

extension HomeworkCaptureViewModel {
    /// Selects the camera as the image source and presents the image picker.
    func selectCamera() {
        AppLogger.ui.info("User selected camera for homework capture")
        imageSourceType = .camera
        showImagePicker = true
    }

    /// Selects the photo library as the image source and presents the image picker.
    func selectPhotoLibrary() {
        AppLogger.ui.info("User selected photo library for homework capture")
        imageSourceType = .photoLibrary
        showImagePicker = true
    }

    /// Presents the document picker to allow users to select image files from the Files app.
    func selectDocumentPicker() {
        AppLogger.ui.info("User opened document picker for homework selection")
        showDocumentPicker = true
    }
}
