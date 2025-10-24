//
//  VerificationResultView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// A view that displays the result of answer verification
struct VerificationResultView: View {
    let result: VerificationResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Result header with icon
                    VStack(spacing: 16) {
                        // Large icon
                        ZStack {
                            Circle()
                                .fill(resultColor.opacity(0.15))
                                .frame(width: 100, height: 100)

                            Image(systemName: resultIcon)
                                .font(.system(size: 50))
                                .foregroundColor(resultColor)
                        }

                        // Result title
                        Text(resultTitle)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(resultColor)
                            .multilineTextAlignment(.center)

                        // Confidence badge
                        HStack(spacing: 4) {
                            Image(systemName: confidenceIcon)
                                .font(.caption)
                            Text("\(result.confidence.capitalized) confidence")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(resultColor.opacity(0.2))
                        .foregroundColor(resultColor)
                        .cornerRadius(12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                    // Feedback section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "message.fill")
                                .foregroundColor(.blue)
                            Text("Feedback")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }

                        Text(result.feedback)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Suggestions section (if available)
                    if let suggestions = result.suggestions, !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.orange)
                                Text("Suggestions")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }

                            Text(suggestions)
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            .navigationTitle("Answer Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Helper Properties

    private var resultColor: Color {
        result.isCorrect ? .green : .red
    }

    private var resultIcon: String {
        result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var resultTitle: String {
        if result.isCorrect {
            return "Correct! 🎉"
        } else {
            return "Not quite right"
        }
    }

    private var confidenceIcon: String {
        switch result.confidence {
        case "high": return "star.fill"
        case "medium": return "star.leadinghalf.filled"
        default: return "star"
        }
    }
}

#Preview("Correct Answer") {
    VerificationResultView(result: VerificationResult(
        isCorrect: true,
        confidence: "high",
        feedback: "Great job! Your answer is correct. You showed clear understanding of the problem and your work demonstrates the right approach.",
        suggestions: nil
    ))
}

#Preview("Incorrect Answer") {
    VerificationResultView(result: VerificationResult(
        isCorrect: false,
        confidence: "high",
        feedback: "Your approach is on the right track, but there's a small calculation error in step 3. Review how you handled the negative numbers.",
        suggestions: "Try checking your arithmetic when working with negative numbers. Remember: when multiplying two negative numbers, the result is positive!"
    ))
}

#Preview("Medium Confidence") {
    VerificationResultView(result: VerificationResult(
        isCorrect: true,
        confidence: "medium",
        feedback: "Your answer appears to be correct! The work shown is a bit unclear in some parts, which makes it harder to verify completely.",
        suggestions: "Try to write more clearly and show each step of your work. This will help both you and others understand your solution better."
    ))
}
