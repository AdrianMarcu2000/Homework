//
//  ODTProcessingService.swift
//  Homework
//
//  Created by Claude on 22.10.2025.
//

import Foundation
import UIKit
import OSLog
import ZIPFoundation

/// Service for processing ODT (OpenDocument Text) files
/// ODT files are ZIP archives containing XML content and embedded images
class ODTProcessingService {
    static let shared = ODTProcessingService()

    private init() {}

    /// Represents extracted content from an ODT file
    struct ODTContent {
        let text: String
        let images: [UIImage]
    }

    /// Extracts text and images from an ODT file
    ///
    /// - Parameter odtData: The ODT file data
    /// - Returns: Extracted text and images, or nil if extraction fails
    func extractContent(from odtData: Data) -> ODTContent? {
        AppLogger.image.info("Starting ODT extraction with ZIPFoundation")

        // Create a temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Write ODT data to a temporary file
            let tempODTFile = tempDir.appendingPathComponent("document.odt")
            try odtData.write(to: tempODTFile)

            // Unzip the ODT file
            let extractionDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.unzipItem(at: tempODTFile, to: extractionDir)

            AppLogger.image.info("ODT file unzipped successfully")

            // Extract text from content.xml
            let contentXML = extractionDir.appendingPathComponent("content.xml")
            var extractedText = ""
            if FileManager.default.fileExists(atPath: contentXML.path) {
                extractedText = extractText(from: contentXML) ?? ""
                AppLogger.image.info("Extracted \(extractedText.count) characters of text")
            } else {
                AppLogger.image.warning("content.xml not found in ODT file")
            }

            // Extract images from Pictures directory
            let picturesDir = extractionDir.appendingPathComponent("Pictures")
            var images: [UIImage] = []
            if FileManager.default.fileExists(atPath: picturesDir.path) {
                images = extractImages(from: picturesDir)
                AppLogger.image.info("Extracted \(images.count) images from ODT")
            } else {
                AppLogger.image.info("No Pictures directory found in ODT")
            }

            // Clean up temporary directory
            cleanup(tempDir)

            return ODTContent(text: extractedText, images: images)

        } catch {
            AppLogger.image.error("Failed to extract ODT content", error: error)
            cleanup(tempDir)
            return nil
        }
    }

    /// Extracts text from content.xml
    private func extractText(from contentXML: URL) -> String? {
        guard let data = try? Data(contentsOf: contentXML) else {
            return nil
        }

        let parser = ODTXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser

        guard xmlParser.parse() else {
            AppLogger.image.error("XML parsing failed")
            return nil
        }

        return parser.extractedText
    }

    /// Extracts images from the Pictures directory
    private func extractImages(from picturesDir: URL) -> [UIImage] {
        var images: [UIImage] = []

        guard let files = try? FileManager.default.contentsOfDirectory(at: picturesDir, includingPropertiesForKeys: nil) else {
            return images
        }

        for file in files {
            if let imageData = try? Data(contentsOf: file),
               let image = UIImage(data: imageData) {
                images.append(image)
            }
        }

        return images
    }

    /// Cleans up temporary directory
    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Checks if a file is an ODT based on its extension
    func isODT(fileName: String?) -> Bool {
        guard let fileName = fileName?.lowercased() else { return false }
        return fileName.hasSuffix(".odt")
    }
}

// MARK: - XML Parser Delegate

/// XMLParser delegate for extracting text from ODT content.xml
private class ODTXMLParser: NSObject, XMLParserDelegate {
    var extractedText = ""
    private var currentElement = ""
    private var isInTextElement = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName

        // Text elements in ODT: text:p (paragraph), text:h (heading), text:span
        if elementName.hasPrefix("text:") {
            isInTextElement = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInTextElement {
            extractedText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        // Add newline after paragraphs and headings
        if elementName == "text:p" || elementName == "text:h" {
            extractedText += "\n"
            isInTextElement = false
        }
    }
}
