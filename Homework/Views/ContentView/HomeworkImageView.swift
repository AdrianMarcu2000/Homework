
//
//  HomeworkImageView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// A simple view to display the homework image
struct HomeworkImageView: View {
    let item: Item

    var body: some View {
        ScrollView {
            if let imageData = item.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Image")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Image")
        .navigationBarTitleDisplayMode(.inline)
    }
}
