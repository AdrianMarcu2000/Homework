//
//  ContentView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData

/// Main view of the Homework app that displays a list of homework items
/// and provides functionality to capture and process homework images using OCR.
///
/// This view integrates camera/photo library access with OCR text extraction,
/// allowing users to take photos of homework assignments and automatically
/// extract text from them.
struct ContentView: View {
    // MARK: - Properties

    /// Core Data managed object context for database operations
    @Environment(\.managedObjectContext) private var viewContext

    /// Fetched results containing all homework items sorted by timestamp
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>

    // MARK: - State Properties

    /// The image selected from camera or photo library
    @State private var selectedImage: UIImage?

    /// Controls the visibility of the image picker sheet
    @State private var showImagePicker = false

    /// Determines whether to use camera or photo library
    @State private var imageSourceType: UIImagePickerController.SourceType = .camera

    /// Controls the visibility of the action sheet for choosing image source
    @State private var showActionSheet = false

    /// Stores the text extracted from the homework image via OCR
    @State private var extractedText: String = ""

    /// Indicates whether OCR processing is in progress
    @State private var isProcessingOCR = false

    /// Controls the visibility of the text extraction result sheet
    @State private var showTextSheet = false

    var body: some View {
        NavigationView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp!, formatter: itemFormatter)")
                    } label: {
                        Text(item.timestamp!, formatter: itemFormatter)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: { showActionSheet = true }) {
                        Label("Add Homework", systemImage: "camera")
                    }
                }
            }
            Text("Select an item")
        }
        .confirmationDialog("Add Homework", isPresented: $showActionSheet) {
            Button("Take Photo") {
                imageSourceType = .camera
                showImagePicker = true
            }
            Button("Choose from Library") {
                imageSourceType = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage, sourceType: imageSourceType)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            if let image = newValue {
                performOCR(on: image)
            }
        }
        .sheet(isPresented: $showTextSheet) {
            NavigationView {
                VStack {
                    if isProcessingOCR {
                        ProgressView("Extracting text...")
                            .padding()
                    } else {
                        ScrollView {
                            Text(extractedText)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .navigationTitle("Extracted Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showTextSheet = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            addItem()
                            showTextSheet = false
                        }
                        .disabled(extractedText.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Creates a new homework item in Core Data with the current timestamp.
    ///
    /// This method saves the new item to the persistent store and handles any errors
    /// that occur during the save operation.
    private func addItem() {
        withAnimation {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()

            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    /// Deletes homework items at the specified offsets from Core Data.
    ///
    /// - Parameter offsets: The index set of items to delete from the list
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    /// Performs OCR (Optical Character Recognition) on the provided image
    /// and displays the results in a sheet.
    ///
    /// This method:
    /// 1. Shows the text sheet with a progress indicator
    /// 2. Calls OCRService to extract text from the image
    /// 3. Updates the UI with extracted text or error message on completion
    ///
    /// - Parameter image: The UIImage to perform text recognition on
    private func performOCR(on image: UIImage) {
        isProcessingOCR = true
        showTextSheet = true
        extractedText = ""

        OCRService.shared.recognizeText(from: image) { result in
            DispatchQueue.main.async {
                isProcessingOCR = false
                switch result {
                case .success(let text):
                    extractedText = text
                case .failure(let error):
                    extractedText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Helper Formatters

/// Date formatter used to display homework item timestamps in the list
private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
