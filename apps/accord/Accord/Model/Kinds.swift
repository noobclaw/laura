import Foundation

/// Substantivity tier: how long a material lasts on a blotter. Five levels, like a perfumer's pyramid
/// with the two transition bands spelled out.
enum Tier: Int, CaseIterable, Codable, Identifiable, Sendable {
    case top = 1, topHeart, heart, heartBase, base
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .top: return String(localized: "Top", bundle: .l10n)
        case .topHeart: return String(localized: "Top–heart", bundle: .l10n)
        case .heart: return String(localized: "Heart", bundle: .l10n)
        case .heartBase: return String(localized: "Heart–base", bundle: .l10n)
        case .base: return String(localized: "Base", bundle: .l10n)
        }
    }

    /// Illustrative half-life on skin, in hours. Used only by the evaporation sketch.
    var halfLifeHours: Double {
        switch self {
        case .top: return 0.4
        case .topHeart: return 1.2
        case .heart: return 3.5
        case .heartBase: return 9
        case .base: return 30
        }
    }

    /// The three broad layers used for colour.
    var layer: Layer {
        switch self {
        case .top, .topHeart: return .top
        case .heart: return .heart
        case .heartBase, .base: return .base
        }
    }

    enum Layer: Int, CaseIterable, Sendable { case top, heart, base }
}

/// Olfactive family of a material.
enum Family: String, CaseIterable, Codable, Identifiable, Sendable {
    case citrus, green, aromatic, floral, fruity, spicy, woody, amber, musk, gourmand, aquatic, leather, animalic, powdery
    var id: String { rawValue }

    var name: String {
        switch self {
        case .citrus: return String(localized: "Citrus", bundle: .l10n)
        case .green: return String(localized: "Green", bundle: .l10n)
        case .aromatic: return String(localized: "Aromatic", bundle: .l10n)
        case .floral: return String(localized: "Floral", bundle: .l10n)
        case .fruity: return String(localized: "Fruity", bundle: .l10n)
        case .spicy: return String(localized: "Spicy", bundle: .l10n)
        case .woody: return String(localized: "Woody", bundle: .l10n)
        case .amber: return String(localized: "Amber", bundle: .l10n)
        case .musk: return String(localized: "Musk", bundle: .l10n)
        case .gourmand: return String(localized: "Gourmand", bundle: .l10n)
        case .aquatic: return String(localized: "Aquatic", bundle: .l10n)
        case .leather: return String(localized: "Leather", bundle: .l10n)
        case .animalic: return String(localized: "Animalic", bundle: .l10n)
        case .powdery: return String(localized: "Powdery", bundle: .l10n)
        }
    }
}

/// What the concentrate is going into. Concentration = share of concentrate in the finished product.
enum ProductType: String, CaseIterable, Codable, Identifiable, Sendable {
    case concentrate, extrait, edp, edt, edc, bodyMist, candle, diffuser, soap, custom
    var id: String { rawValue }

    var name: String {
        switch self {
        case .concentrate: return String(localized: "Concentrate only", bundle: .l10n)
        case .extrait: return String(localized: "Extrait", bundle: .l10n)
        case .edp: return String(localized: "Eau de Parfum", bundle: .l10n)
        case .edt: return String(localized: "Eau de Toilette", bundle: .l10n)
        case .edc: return String(localized: "Eau de Cologne", bundle: .l10n)
        case .bodyMist: return String(localized: "Body mist", bundle: .l10n)
        case .candle: return String(localized: "Candle", bundle: .l10n)
        case .diffuser: return String(localized: "Reed diffuser", bundle: .l10n)
        case .soap: return String(localized: "Soap", bundle: .l10n)
        case .custom: return String(localized: "Custom", bundle: .l10n)
        }
    }

    /// Default fragrance load (fraction of finished product).
    var defaultConcentration: Double {
        switch self {
        case .concentrate: return 1
        case .extrait: return 0.25
        case .edp: return 0.18
        case .edt: return 0.10
        case .edc: return 0.05
        case .bodyMist: return 0.03
        case .candle: return 0.08
        case .diffuser: return 0.25
        case .soap: return 0.03
        case .custom: return 0.15
        }
    }

    /// Whether the balance of the product is perfumer's alcohol (so the weighing sheet adds ethanol).
    var isAlcoholic: Bool {
        switch self {
        case .extrait, .edp, .edt, .edc, .bodyMist, .custom: return true
        default: return false
        }
    }
}

/// Solvent a material is diluted in.
enum Solvent: String, CaseIterable, Codable, Identifiable, Sendable {
    case ethanol, dpg, ipm, tec, bb, none
    var id: String { rawValue }

    var name: String {
        switch self {
        case .ethanol: return String(localized: "Ethanol", bundle: .l10n)
        case .dpg: return "DPG"
        case .ipm: return "IPM"
        case .tec: return "TEC"
        case .bb: return String(localized: "Benzyl benzoate", bundle: .l10n)
        case .none: return String(localized: "Neat", bundle: .l10n)
        }
    }
}

/// A note the perfumer leaves on a line after smelling a trial.
enum LineFlag: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, tooStrong, tooWeak, keep, check
    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: return String(localized: "No flag", bundle: .l10n)
        case .tooStrong: return String(localized: "Too strong", bundle: .l10n)
        case .tooWeak: return String(localized: "Too weak", bundle: .l10n)
        case .keep: return String(localized: "Just right", bundle: .l10n)
        case .check: return String(localized: "Check again", bundle: .l10n)
        }
    }

    var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .tooStrong: return "arrow.down.circle.fill"
        case .tooWeak: return "arrow.up.circle.fill"
        case .keep: return "checkmark.circle.fill"
        case .check: return "questionmark.circle.fill"
        }
    }
}

/// How an amount is shown and typed. Storage is always grams.
enum AmountUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case grams, drops, percent
    var id: String { rawValue }

    var short: String {
        switch self {
        case .grams: return String(localized: "g", bundle: .l10n)
        case .drops: return String(localized: "drops", bundle: .l10n)
        case .percent: return "%"
        }
    }

    var next: AmountUnit {
        switch self {
        case .grams: return .drops
        case .drops: return .percent
        case .percent: return .grams
        }
    }
}
