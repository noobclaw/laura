import SwiftUI
import UIKit
import SwiftData
import LocalAuthentication

@main
struct AccordApp: App {
    @State private var language = AppLanguage()
    @State private var store = ProStore()
    @State private var state = AppState()
    @State private var lock = AppLock()
    @AppStorage(Theme.lookKey) private var look = Theme.Look.atelier.rawValue
    private let container: ModelContainer
    private let storeFailed: Bool

    init() {
        let schema = Schema([Material.self, Formula.self, FormulaLine.self, Batch.self, AgingNote.self])
        let args = ProcessInfo.processInfo.arguments
        let inMemory = args.contains("-UITour")
        if inMemory { UserDefaults.standard.set(args.contains("-UITourNoir") ? "noir" : "atelier", forKey: Theme.lookKey) }
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
            storeFailed = false
        } catch {
            // Never crash on a damaged store: run from memory and tell the user, so nothing they type is silently lost.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            storeFailed = true
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeFailed: storeFailed)
                .environment(language)
                .environment(store)
                .environment(state)
                .environment(lock)
                .environment(\.locale, language.locale)
                .preferredColorScheme(look == Theme.Look.noir.rawValue ? .dark : nil)
                .id(language.code + look)
                .tint(Theme.amberInk)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .modelContainer(container)
    }
}

/// App-wide navigation state.
@MainActor
@Observable
final class AppState {
    enum Tab: String, CaseIterable, Identifiable {
        case bench, shelf, library, lab
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bench: return String(localized: "Bench", bundle: .l10n)
            case .shelf: return String(localized: "Formulas", bundle: .l10n)
            case .library: return String(localized: "Materials", bundle: .l10n)
            case .lab: return String(localized: "Batches", bundle: .l10n)
            }
        }

        var symbol: String {
            switch self {
            case .bench: return "flask"
            case .shelf: return "books.vertical"
            case .library: return "drop"
            case .lab: return "hourglass"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .bench: return "flask.fill"
            case .shelf: return "books.vertical.fill"
            case .library: return "drop.fill"
            case .lab: return "hourglass.bottomhalf.filled"
            }
        }
    }

    var tab: Tab = .bench
    var proReason: ProReason?
    var currentFormulaID: UUID? {
        didSet { UserDefaults.standard.set(currentFormulaID?.uuidString, forKey: "accord.current") }
    }

    init() {
        currentFormulaID = UserDefaults.standard.string(forKey: "accord.current").flatMap(UUID.init(uuidString:))
    }

    func open(_ formula: Formula) {
        currentFormulaID = formula.id
        tab = .bench
    }
}

/// Optional Face ID / passcode lock over the whole app (Pro).
@MainActor
@Observable
final class AppLock {
    private static let key = "accord.lock"
    var isEnabled: Bool { didSet { UserDefaults.standard.set(isEnabled, forKey: AppLock.key) } }
    var isLocked: Bool
    var failure: String?

    init() {
        let on = UserDefaults.standard.bool(forKey: AppLock.key)
        isEnabled = on
        isLocked = on
    }

    @ObservationIgnored private var window: UIWindow?

    func lockIfNeeded() {
        guard isEnabled else { return }
        isLocked = true
        showWindow()
    }

    /// A separate window above everything, so open sheets are covered too.
    func showWindow() {
        guard isLocked, window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.rootViewController = UIHostingController(rootView: LockScreen().environment(self))
        w.makeKeyAndVisible()
        window = w
    }

    private func hideWindow() {
        window?.isHidden = true
        window = nil
    }

    func unlock() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode on the device: a lock cannot be enforced, so don't trap the user's data.
            isLocked = false
            hideWindow()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock your formula book", bundle: .l10n)) { ok, err in
            Task { @MainActor in
                if ok { self.isLocked = false; self.failure = nil; self.hideWindow() } else { self.failure = err?.localizedDescription }
            }
        }
    }

    /// Checks that the device can authenticate before turning the lock on.
    func enable() -> Bool {
        var error: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        isEnabled = true
        return true
    }
}
