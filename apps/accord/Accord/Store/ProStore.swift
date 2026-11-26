import Foundation
import Observation
import StoreKit

/// Why the Pro sheet was opened: drives its headline.
enum ProReason: String, Identifiable {
    case formulaLimit, bases, batches, compare, inventory, export, importData, appLock, settings
    var id: String { rawValue }

    var headline: String {
        switch self {
        case .formulaLimit: return String(localized: "Your 5 free formulas are full", bundle: .l10n)
        case .bases: return String(localized: "Build with your own bases", bundle: .l10n)
        case .batches: return String(localized: "Keep a record of every batch", bundle: .l10n)
        case .compare: return String(localized: "See exactly what changed", bundle: .l10n)
        case .inventory: return String(localized: "Know your stock and your cost", bundle: .l10n)
        case .export: return String(localized: "Take your formulas anywhere", bundle: .l10n)
        case .importData: return String(localized: "Bring in your spreadsheet", bundle: .l10n)
        case .appLock: return String(localized: "Lock your formula book", bundle: .l10n)
        case .settings: return String(localized: "Accord Pro", bundle: .l10n)
        }
    }
}

@MainActor
@Observable
final class ProStore {
    static let productID = "com.noobclaw.accord.pro_unlock"
    static let freeFormulaLimit = 5

    private(set) var product: Product?
    private(set) var isPro: Bool
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    var isLoadingProduct = false
    var loadFailed = false
    var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let cacheKey = "accord.pro.cached"

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
            if t.revocationDate == nil { Haptics.success() }
        }
        await t.finish()
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: cacheKey)
    }

    /// Samples don't count against the limit.
    func canCreateFormula(userFormulaCount: Int) -> Bool {
        isPro || userFormulaCount < ProStore.freeFormulaLimit
    }
}
