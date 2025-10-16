//
//  SubscriptionService.swift
//  Homework
//
//  Created by Claude on 16.10.2025.
//

import Foundation
import StoreKit
import Combine
import UIKit

/// Manages in-app subscriptions using StoreKit 2
@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    // Product identifier for monthly subscription
    private let cloudAIMonthlyID = "com.BlueFern.Homework.cloudai.monthly"

    @Published private(set) var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published private(set) var products: [Product] = []
    @Published var purchaseError: String?
    @Published private(set) var isLoading = false

    private var updateListenerTask: Task<Void, Error>?

    enum SubscriptionStatus {
        case notSubscribed
        case subscribed(expirationDate: Date?)
        case expired
        case inGracePeriod
        case revoked

        var isActive: Bool {
            switch self {
            case .subscribed, .inGracePeriod:
                return true
            default:
                return false
            }
        }
    }

    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        print("🔄 Loading products for ID: \(cloudAIMonthlyID)")

        do {
            let products = try await Product.products(for: [cloudAIMonthlyID])
            print("📦 Received \(products.count) products from StoreKit")

            if products.isEmpty {
                print("⚠️ No products found. Make sure Configuration.storekit is selected in Xcode scheme.")
                purchaseError = "No subscription products available. Please check StoreKit configuration."
            } else {
                for product in products {
                    print("  - Product: \(product.id), Price: \(product.displayPrice), Name: \(product.displayName)")
                }
            }

            self.products = products.sorted { $0.price < $1.price }
            print("✅ Loaded \(products.count) subscription product(s)")
        } catch {
            print("❌ Failed to load products: \(error)")
            print("   Error details: \(error.localizedDescription)")
            purchaseError = "Failed to load subscription options: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase Subscription

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Verify the transaction
                let transaction = try checkVerified(verification)

                // Update subscription status
                await updateSubscriptionStatus()

                // Finish the transaction
                await transaction.finish()

                // Enable cloud AI by default after successful subscription
                AppSettings.shared.useCloudAnalysis = true

                print("✅ Purchase successful: \(product.id)")
                print("✅ Cloud AI enabled by default")
                return true

            case .userCancelled:
                print("⚠️ User cancelled purchase")
                return false

            case .pending:
                print("⏳ Purchase pending approval")
                purchaseError = "Purchase is pending approval"
                return false

            @unknown default:
                print("❌ Unknown purchase result")
                return false
            }
        } catch {
            print("❌ Purchase failed: \(error)")
            purchaseError = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            print("✅ Purchases restored")
        } catch {
            print("❌ Failed to restore purchases: \(error)")
            purchaseError = "Failed to restore purchases: \(error.localizedDescription)"
        }
    }

    // MARK: - Update Subscription Status

    func updateSubscriptionStatus() async {
        var activeSubscription: Transaction?

        // Check for active subscription
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // Check if this is our cloud AI subscription
                if transaction.productID == cloudAIMonthlyID {
                    activeSubscription = transaction
                    break
                }
            } catch {
                print("❌ Failed to verify transaction: \(error)")
            }
        }

        if let transaction = activeSubscription {
            if let expirationDate = transaction.expirationDate {
                if expirationDate > Date() {
                    subscriptionStatus = .subscribed(expirationDate: expirationDate)
                    print("✅ Active subscription until \(expirationDate)")
                } else {
                    subscriptionStatus = .expired
                    print("⚠️ Subscription expired on \(expirationDate)")
                }
            } else {
                // No expiration date means lifetime or non-expiring
                subscriptionStatus = .subscribed(expirationDate: nil)
                print("✅ Active subscription (no expiration)")
            }

            // Check for revocation
            if transaction.revocationDate != nil {
                subscriptionStatus = .revoked
                print("⚠️ Subscription was revoked")
            }
        } else {
            subscriptionStatus = .notSubscribed
            print("ℹ️ No active subscription")
        }

        // Sync with AppSettings
        let wasSubscribed = AppSettings.shared.hasCloudSubscription
        let isNowSubscribed = subscriptionStatus.isActive

        AppSettings.shared.hasCloudSubscription = isNowSubscribed

        // Enable cloud AI automatically when subscription becomes active
        if !wasSubscribed && isNowSubscribed {
            AppSettings.shared.useCloudAnalysis = true
            print("✅ Cloud AI enabled automatically with new subscription")
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Listen for transaction updates
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    // Update subscription status on main actor
                    await self.updateSubscriptionStatus()

                    // Finish the transaction
                    await transaction.finish()
                } catch {
                    print("❌ Transaction verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Verification Helper
    nonisolated private func checkVerified(_ result: StoreKit.VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Manage Subscriptions
    func openManageSubscriptions() async {
        // Get the window scene on the main actor
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene

        if let windowScene = windowScene {
            do {
                try await AppStore.showManageSubscriptions(in: windowScene)
            } catch {
                print("❌ Failed to open manage subscriptions: \(error)")
                purchaseError = "Failed to open subscription management"
            }
        }
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction verification failed"
        }
    }
}
