import SwiftUI
import UIKit

/// Design tokens. Colours, radii, spacing, durations and fonts come only from here.
enum Theme {
    // MARK: Look

    /// Two art directions. Atelier: warm paper perfumer's lab (follows light/dark). Noir: black and gold boutique (always dark).
    enum Look: String, CaseIterable, Identifiable {
        case atelier, noir
        var id: String { rawValue }
        var name: String {
            switch self {
            case .atelier: return String(localized: "Atelier", bundle: .l10n)
            case .noir: return String(localized: "Noir", bundle: .l10n)
            }
        }
        var detail: String {
            switch self {
            case .atelier: return String(localized: "Warm paper, amber and kraft labels", bundle: .l10n)
            case .noir: return String(localized: "Black glass and gold, like a perfume counter", bundle: .l10n)
            }
        }
    }

    static let lookKey = "accord.look"
    /// Read live by every colour provider, so switching only needs a view rebuild.
    static var look: Look { Look(rawValue: UserDefaults.standard.string(forKey: lookKey) ?? "") ?? .atelier }

    // MARK: Colour (atelier light / atelier dark / noir)

    static let paper = tone(0xF6F1E7, 0x1C1916, 0x0D0B09)
    static let card = tone(0xFCF9F2, 0x26221E, 0x17140F)
    static let sunken = tone(0xEDE5D6, 0x14120F, 0x060504)
    static let ink = tone(0x2A2420, 0xEDE6D8, 0xF3EADB)
    static let inkSoft = tone(0x6B6158, 0xA89E90, 0xA99B84)
    static let hair = tone(0x2A2420, 0xEDE6D8, 0xD4AF63, alpha: 0.12, noirAlpha: 0.22)
    static let amber = tone(0xC8941E, 0xE0AE3C, 0xD4AF63)
    /// Amber dark enough to read as text on paper (gold on noir).
    static let amberInk = tone(0x8A6210, 0xE8BC55, 0xE6C47E)
    static let onAmber = tone(0x2A2420, 0x1C1916, 0x120F0B)
    static let kraft = tone(0xEADBC0, 0x3A3127, 0x2A2116)

    static let topNote = tone(0x8FAE8B, 0xA9C6A4, 0x8CC7AE)
    static let heartNote = tone(0xC47F8F, 0xD8A0AD, 0xE08EA5)
    static let baseNote = tone(0x7A5A44, 0xB08A6C, 0xC08A55)

    static let ok = tone(0x4F7A52, 0x8FBF8F, 0x8FC79A)
    static let warn = tone(0xA8770F, 0xE0AE3C, 0xE6C47E)
    static let danger = tone(0xB3412E, 0xE07A63, 0xEB8770)

    static var isNoir: Bool { look == .noir }

    static func color(_ layer: Tier.Layer) -> Color {
        switch layer {
        case .top: return topNote
        case .heart: return heartNote
        case .base: return baseNote
        }
    }

    static func color(_ tier: Tier) -> Color {
        switch tier {
        case .top: return topNote
        case .topHeart: return blend(0x8FAE8B, 0xC47F8F, 0xA9C6A4, 0xD8A0AD, 0x8CC7AE, 0xE08EA5)
        case .heart: return heartNote
        case .heartBase: return blend(0xC47F8F, 0x7A5A44, 0xD8A0AD, 0xB08A6C, 0xE08EA5, 0xC08A55)
        case .base: return baseNote
        }
    }

    /// One hue per olfactive family, muted to sit on paper.
    static func color(_ family: Family) -> Color {
        switch family {
        case .citrus: return dynamic(0xD9B23A, 0xE6C65E)
        case .green: return dynamic(0x6F9A5B, 0x93BF7E)
        case .aromatic: return dynamic(0x7C8FB0, 0x9FB1CF)
        case .floral: return dynamic(0xC47F8F, 0xD8A0AD)
        case .fruity: return dynamic(0xE08E62, 0xEDA984)
        case .spicy: return dynamic(0xB4553A, 0xD27A5F)
        case .woody: return dynamic(0x8A6A4C, 0xB89573)
        case .amber: return dynamic(0xC8941E, 0xE0AE3C)
        case .musk: return dynamic(0xB9AFA6, 0xCFC6BE)
        case .gourmand: return dynamic(0x9B6B3D, 0xC4935F)
        case .aquatic: return dynamic(0x5E9BA6, 0x86BEC8)
        case .leather: return dynamic(0x5B4636, 0x9A8170)
        case .animalic: return dynamic(0x7E5A6C, 0xA98299)
        case .powdery: return dynamic(0xB89BC4, 0xCDB6D7)
        }
    }

    // MARK: Shape, spacing, motion

    enum Radius {
        static let small: CGFloat = 4
        static let row: CGFloat = 12
        static let pill: CGFloat = 28
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let settle = Animation.spring(response: 0.42, dampingFraction: 0.86)
        static let pour = Animation.easeInOut(duration: 0.6)
    }

    // MARK: Type

    /// Bodoni Moda has no CJK glyphs: in Chinese, Japanese and Korean the display face falls back to the system serif.
    static var usesLatinDisplay: Bool {
        !["zh-Hant", "zh-Hans", "ja", "ko"].contains(AppLanguage.currentCode)
    }

    static func display(_ size: CGFloat, italic: Bool = false, relativeTo style: Font.TextStyle = .title) -> Font {
        if usesLatinDisplay {
            return .custom(italic ? "BodoniModa-MediumItalic" : "BodoniModa-Medium", size: size, relativeTo: style)
        }
        return .system(style, design: .serif).weight(.semibold)
    }

    static func displayBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        usesLatinDisplay ? .custom("BodoniModa-SemiBold", size: size, relativeTo: style)
                         : .system(style, design: .serif).weight(.bold)
    }

    /// Figures on the scale: tabular digits so columns don't jitter.
    static func figure(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .default).weight(weight).monospacedDigit()
    }

    // MARK: Helpers

    static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
        })
    }

    /// Atelier light / atelier dark / noir.
    static func tone(_ light: UInt32, _ dark: UInt32, _ noir: UInt32, alpha: CGFloat = 1, noirAlpha: CGFloat? = nil) -> Color {
        Color(UIColor { traits in
            if look == .noir { return UIColor(hex: noir, alpha: noirAlpha ?? alpha) }
            return UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
        })
    }

    private static func blend(_ a: UInt32, _ b: UInt32, _ da: UInt32, _ db: UInt32, _ na: UInt32, _ nb: UInt32) -> Color {
        Color(UIColor { traits in
            if look == .noir { return UIColor(hex: na).mixed(with: UIColor(hex: nb), 0.5) }
            let dark = traits.userInterfaceStyle == .dark
            return UIColor(hex: dark ? da : a).mixed(with: UIColor(hex: dark ? db : b), 0.5)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
