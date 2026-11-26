import Foundation
import ObjectiveC
import SwiftUI

/// In-app language switching (no trip to iOS Settings, no restart).
///
/// Bundle.main is re-classed so every localized lookup (SwiftUI `Text`, `String(localized:)`,
/// `LocalizedStringKey`) reads from the chosen `.lproj`. The choice is stored in our own key and
/// re-applied at launch before any UI is built; `AppleLanguages` is left to the system.
@MainActor
@Observable
final class AppLanguage {
    nonisolated static let supported = ["en", "zh-Hant", "zh-Hans", "ja", "ko", "de", "fr", "es", "pt-BR", "it"]
    private static let storeKey = "groovelens.language"

    /// Code of the language in effect, readable from anywhere (fonts, formatters).
    nonisolated(unsafe) static var currentCode = "en"

    /// `nil` = follow the system.
    private(set) var override: String?
    /// The language the system would pick for this app.
    let systemCode: String

    init(defaults: UserDefaults = .standard) {
        // Builds before 116 pinned AppleLanguages in the app domain, which hid the real system language.
        defaults.removeObject(forKey: "AppleLanguages")
        let stored = defaults.string(forKey: AppLanguage.storeKey)
        // AppleLanguages may have been pinned by an earlier override; resolve the system choice without it.
        let systemPreferred = Bundle.preferredLocalizations(from: Bundle.main.localizations.filter { $0 != "Base" },
                                                            forPreferences: Locale.preferredLanguages)
        systemCode = AppLanguage.normalize(systemPreferred.first ?? "en")
        override = stored.flatMap { AppLanguage.supported.contains($0) ? $0 : nil }
        apply()
    }

    var code: String { override ?? systemCode }
    var locale: Locale { Locale(identifier: code) }

    func select(_ newCode: String?) {
        override = newCode
        let d = UserDefaults.standard
        if let newCode {
            d.set(newCode, forKey: AppLanguage.storeKey)
        } else {
            d.removeObject(forKey: AppLanguage.storeKey)
        }
        apply()
    }

    private func apply() {
        AppLanguage.currentCode = code
        LocalizedBundle.use(code)
    }

    /// Native name, e.g. "繁體中文", "Deutsch".
    nonisolated static func nativeName(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    nonisolated static func normalize(_ code: String) -> String {
        if supported.contains(code) { return code }
        let lower = code.lowercased()
        if lower.hasPrefix("zh") { return lower.contains("hans") || lower.hasSuffix("cn") || lower.hasSuffix("sg") ? "zh-Hans" : "zh-Hant" }
        if lower.hasPrefix("pt") { return "pt-BR" }
        let base = String(lower.prefix(2))
        return supported.first { $0 == base } ?? "en"
    }
}

private var overrideBundleKey: UInt8 = 0

/// Bundle subclass installed on Bundle.main; forwards string lookups to the selected `.lproj`.
final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let target = objc_getAssociatedObject(self, &overrideBundleKey) as? Bundle {
            return target.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }

    static func use(_ code: String) {
        if object_getClass(Bundle.main) != LocalizedBundle.self {
            object_setClass(Bundle.main, LocalizedBundle.self)
        }
        let target = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        objc_setAssociatedObject(Bundle.main, &overrideBundleKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
