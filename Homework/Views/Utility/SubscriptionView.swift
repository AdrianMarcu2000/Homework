//
//  SubscriptionView.swift
//  Homework
//
//  Created by Claude on 16.10.2025.
//

import SwiftUI
import StoreKit

/// View for purchasing and managing Cloud AI subscription
struct SubscriptionView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingError = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 40) {
                        // Header
                        VStack(spacing: 20) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 100))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .padding(.top, 40)

                            Text("Cloud AI")
                                .font(.system(size: 52, weight: .bold))

                            Text("Unlock powerful homework analysis")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        // Features
                        VStack(alignment: .leading, spacing: 24) {
                            FeatureRow(
                                icon: "eyes",
                                color: .blue,
                                title: "Multimodal Analysis",
                                description: "Google Gemini analyzes both text and images for superior understanding"
                            )

                            FeatureRow(
                                icon: "lightbulb.fill",
                                color: .yellow,
                                title: "Better Exercise Detection",
                                description: "More accurate identification and splitting of homework problems"
                            )

                            FeatureRow(
                                icon: "chart.line.uptrend.xyaxis",
                                color: .green,
                                title: "Enhanced Clarity",
                                description: "Superior OCR correction and content interpretation"
                            )

                            FeatureRow(
                                icon: "lock.shield.fill",
                                color: .purple,
                                title: "Privacy Focused",
                                description: "Your data is processed securely and never stored permanently"
                            )
                        }
                        .padding(.horizontal, 32)

                        // Subscription Status
                        if case .subscribed(let expirationDate) = subscriptionService.subscriptionStatus {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title2)

                                    VStack(alignment: .leading) {
                                        Text("Active Subscription")
                                            .font(.headline)

                                        if let date = expirationDate {
                                            Text("Renews on \(date.formatted(date: .long, time: .omitted))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Active")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)

                                Button(action: {
                                    Task {
                                        await subscriptionService.openManageSubscriptions()
                                    }
                                }) {
                                    Text("Manage Subscription")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal, 24)
                        } else {
                            // Subscription products
                            VStack(spacing: 20) {
                                if subscriptionService.isLoading {
                                    ProgressView()
                                        .scaleEffect(2)
                                        .padding()
                                } else if subscriptionService.products.isEmpty {
                                    Text("Loading subscription options...")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                        .padding()
                                } else {
                                    ForEach(subscriptionService.products, id: \.id) { product in
                                        SubscriptionProductCard(product: product) {
                                            Task {
                                                let success = await subscriptionService.purchase(product)
                                                if success {
                                                    dismiss()
                                                } else if subscriptionService.purchaseError != nil {
                                                    showingError = true
                                                }
                                            }
                                        }
                                    }
                                }

                                // Restore purchases button
                                Button(action: {
                                    Task {
                                        await subscriptionService.restorePurchases()
                                    }
                                }) {
                                    Text("Restore Purchases")
                                        .font(.body)
                                        .foregroundColor(.blue)
                                        .padding(.top, 12)
                                }
                            }
                            .padding(.horizontal, 32)
                        }

                        // Terms and privacy
                        VStack(spacing: 10) {
                            Text("By subscribing, you agree to our Terms of Service and Privacy Policy.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Purchase Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {
                    subscriptionService.purchaseError = nil
                }
            } message: {
                Text(subscriptionService.purchaseError ?? "An unknown error occurred")
            }
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Subscription Product Card

struct SubscriptionProductCard: View {
    let product: Product
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(product.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(product.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(product.displayPrice)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("per month")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Button(action: onPurchase) {
                Text("Subscribe Now")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
        }
        .padding(28)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Preview

#Preview {
    SubscriptionView()
}
