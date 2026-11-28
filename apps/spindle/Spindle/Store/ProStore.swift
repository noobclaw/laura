import Foundation
import Observation
import StoreKit
import UIKit

/// Why the Pro sheet was opened: drives its headline.
enum ProReason: String, Identifiable {
    case sources, playlists, offline, sleepTimer, settings
    var id: String { rawValue }

    var headline: String {
        switch self {
        case .sources: return String(localized: "Add as many servers as you like", bundle: .l10n)
        case .playlists: return String(localized: "Make all the playlists you want", bundle: .l10n)
        case .offline: return String(localized: "Your 20 free offline songs are used", bundle: .l10n)
        case .sleepTimer: return String(localized: "Fall asleep to your music", bundle: .l10n)
        case .settings: return String(localized: "Spindle Pro", bundle: .l10n)
        }
    }
}

@MainActor
@Observable
final class ProStore {
    static let productID = "com.noobclaw.spindle.pro_unlock"

    private(set) var product: Product?
    private(set) var isPro: Bool
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    var isLoadingProduct = false
    var loadFailed = false
    var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let cacheKey = "spindle.pro.cached"

    init() {
        isPro = UserDefaults.standard.bool(forKey: cacheKey)
        if ProcessInfo.processInfo.arguments.contains("-UITourPro") { isPro = true }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await self.load() }
    }

    /// Localized price from the store; nil until loaded (the UI shows a spinner, never a hard-coded price).
    var displayPrice: String? { product?.displayPrice }

    func load() async {
        isLoadingProduct = true
        loadFailed = false
        do {
            product = try await Product.products(for: [ProStore.productID]).first
        } catch {
            product = nil
        }
        loadFailed = product == nil
        isLoadingProduct = false
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        if ProcessInfo.processInfo.arguments.contains("-UITourPro") { return }
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == ProStore.productID, t.revocationDate == nil {
                owned = true
            }
        }
        setPro(owned)
    }

    func purchase() async {
        if product == nil { await load() }
        guard let product else {
            message = String(localized: "The App Store isn’t reachable right now. Check your connection and try again.", bundle: .l10n)
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .pending:
                message = String(localized: "Your purchase is waiting for approval. Pro unlocks as soon as it’s approved.", bundle: .l10n)
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = String(localized: "The purchase didn’t go through: \(error.localizedDescription)", bundle: .l10n)
        }
    }

    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPro ? String(localized: "Pro restored. Welcome back!", bundle: .l10n)
                            : String(localized: "No previous Pro purchase was found for this Apple ID.", bundle: .l10n)
        } catch {
            message = String(localized: "Restore failed: \(error.localizedDescription)", bundle: .l10n)
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let t) = result else {
            message = String(localized: "The App Store couldn’t verify this purchase.", bundle: .l10n)
            return
        }
        if t.productID == ProStore.productID {
            setPro(t.revocationDate == nil)
            if t.revocationDate == nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        await t.finish()
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: cacheKey)
    }

    var limits: ProLimits { ProLimits(isPro: isPro) }
}
