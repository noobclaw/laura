import SwiftUI
import UIKit

/// Design tokens. Colours, radii, spacing, durations and fonts come only from here.
enum Theme {
    // MARK: Colour (light / dark)

    static let paper = dynamic(0xF6F1E7, 0x1C1916)
    static let card = dynamic(0xFCF9F2, 0x26221E)
    static let sunken = dynamic(0xEDE5D6, 0x14120F)
    static let ink = dynamic(0x2A2420, 0xEDE6D8)
    static let inkSoft = dynamic(0x6B6158, 0xA89E90)
    static let hair = dynamic(0x2A2420, 0xEDE6D8, alpha: 0.12)
    static let amber = dynamic(0xC8941E, 0xE0AE3C)
    /// Amber dark enough to read as text on paper.
    static let amberInk = dynamic(0x8A6210, 0xE8BC55)
    static let onAmber = dynamic(0x2A2420, 0x1C1916)
    static let kraft = dynamic(0xEADBC0, 0x3A3127)

    static let topNote = dynamic(0x8FAE8B, 0xA9C6A4)
    static let heartNote = dynamic(0xC47F8F, 0xD8A0AD)
    static let baseNote = dynamic(0x7A5A44, 0xB08A6C)

    static let ok = dynamic(0x4F7A52, 0x8FBF8F)
    static let warn = dynamic(0xA8770F, 0xE0AE3C)
    static let danger = dynamic(0xB3412E, 0xE07A63)

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
        case .topHeart: return blend(0x8FAE8B, 0xC47F8F, 0xA9C6A4, 0xD8A0AD)
        case .heart: return heartNote
        case .heartBase: return blend(0xC47F8F, 0x7A5A44, 0xD8A0AD, 0xB08A6C)
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

    private static func blend(_ a: UInt32, _ b: UInt32, _ da: UInt32, _ db: UInt32) -> Color {
        Color(UIColor { traits in
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
