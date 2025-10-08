//
//  GlassmorphicButtonStyle.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI

/// A button style that creates a glassmorphic (liquid glass) effect with blur,
/// transparency, and subtle borders.
///
/// This style provides a modern, translucent appearance that works well with
/// light and dark mode interfaces.
struct GlassmorphicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Glass background with blur effect
                    RoundedRectangle(cornerRadius: 30)
                        .fill(.ultraThinMaterial)

                    // Subtle gradient overlay
                    RoundedRectangle(cornerRadius: 30)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Border
                    RoundedRectangle(cornerRadius: 30)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview {
    ZStack {
        // Background to show glass effect
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
            Button("Add Homework") {}
                .buttonStyle(GlassmorphicButtonStyle())

            Button(action: {}) {
                Label("Camera", systemImage: "camera")
            }
            .buttonStyle(GlassmorphicButtonStyle())

            Button("Edit") {}
                .buttonStyle(GlassmorphicButtonStyle())
        }
    }
}
