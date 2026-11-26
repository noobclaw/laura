import Foundation
import Observation
import StoreKit

/// Why the Pro sheet was opened — drives its headline.
enum ProReason: String, Identifiable {
    case songLimit, kitMode, speedTrainer, fills, export, skins, settings
    var id: String { rawValue }

    var headline: String {
        switch self {
        case .songLimit: return String(localized: "You’ve charted your 3 free songs", bundle: .l10n)
        case .kitMode: return String(localized: "Score your real kit", bundle: .l10n)
        case .speedTrainer: return String(localized: "Climb to full tempo", bundle: .l10n)
        case .fills: return String(localized: "Every fill, one tap away", bundle: .l10n)
        case .export: return String(localized: "Take your charts anywhere", bundle: .l10n)
        case .skins: return String(localized: "Unlock every stage", bundle: .l10n)
        case .settings: return String(localized: "Groovelens Pro", bundle: .l10n)
        }
    }
}

@MainActor
@Observable
final class ProStore {
    static let productID = "com.noobclaw.groovelens.pro_unlock"
    static let freeSongLimit = 3

    private(set) var product: Product?
    private(set) var isPro: Bool
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let cacheKey = "groovelens.pro.cached"

    init() {
        isPro = UserDefaults.standard.bool(forKey: cacheKey)
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await self.load() }
    }

    /// Localized price from the store; nil until loaded (UI shows a spinner, never a hard-coded price).
    var displayPrice: String? { product?.displayPrice }

    /// True while products are being fetched; `loadFailed` when the store returned nothing.
    var isLoadingProduct = false
    var loadFailed = false

    func load() async {
        isLoadingProduct = true
        loadFailed = false
        do {
            let products = try await Product.products(for: [ProStore.productID])
            product = products.first
        } catch {
            product = nil
        }
        loadFailed = product == nil
        isLoadingProduct = false
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == ProStore.productID, t.revocationDate == nil {
                owned = true
            }
        }
        // currentEntitlements is served from the on-device cache, so this also works offline.
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
            let result = try await product.purchase()
            switch result {
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
            message = isPro ? String(localized: "Pro restored. Welcome back!", bundle: .l10n) : String(localized: "No previous Pro purchase was found for this Apple ID.", bundle: .l10n)
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
            if t.revocationDate == nil { Haptics.success() }
        }
        await t.finish()
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: cacheKey)
    }

    func canAnalyzeAnotherSong(started: Int) -> Bool {
        isPro || started < ProStore.freeSongLimit
    }
}
