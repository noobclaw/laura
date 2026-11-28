import SwiftUI
import UIKit

/// Design tokens (PLAN §6.1). Every colour, radius, spacing and duration comes from here.
enum Theme {
    // Colours: light / dark pairs.
    static let bg = dyn(0xF1EFE8, 0x121315)
    static let surface = dyn(0xFFFFFF, 0x1C1E21)
    static let raised = dyn(0xE7E4DA, 0x26282C)
    static let ink = dyn(0x1B1C1E, 0xECEAE3)
    static let sub = dyn(0x6B6A64, 0x9A9890)
    static let hairline = dyn(0xD8D5CB, 0x2E3034)
    static let accent = dyn(0x8A8122, 0xD9CF4A)
    static let signal = dyn(0xC2502F, 0xE86A4A)
    static let vinyl = Color(hex: 0x0E0E0F)
    /// Edge of a record: invisible on light paper, a soft rim on the dark background.
    static let vinylRim = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.05) })
    static let onAccent = dyn(0xFFFFFF, 0x121315)

    // Shape: the only three radii.
    static let rSmall: CGFloat = 2
    static let rCard: CGFloat = 10
    static let rPill: CGFloat = 999

    // Spacing (8 pt base).
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 16
    static let s4: CGFloat = 24
    static let s5: CGFloat = 32

    // Motion.
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    static let medium = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)
    static let sheet = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.4)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// Anton for Latin display text; CJK languages fall back to the heavy system face (Anton has no CJK glyphs).
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        if usesCJKFallback { return .system(size: size * 0.86, weight: .heavy).leading(.tight) }
        return .custom("Anton-Regular", size: size, relativeTo: style)
    }

    /// The SPINDLE wordmark is always Anton.
    static func wordmark(_ size: CGFloat) -> Font { .custom("Anton-Regular", size: size, relativeTo: .title) }

    static var usesCJKFallback: Bool {
        let c = AppLanguage.currentCode
        return c.hasPrefix("zh") || c == "ja" || c == "ko"
    }

    static let mono = Font.system(.footnote, design: .default).monospacedDigit()
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// One event, one tap of feedback; no heavy impacts.
enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

/// Pressed buttons shrink to 0.97 on touch-down.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Filled pill for the main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, Theme.s4)
            .frame(minHeight: 48)
            .background(Theme.accent, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Outlined pill for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.s3)
            .frame(minHeight: 48)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

extension View {
    /// Section label: small, sentence case, secondary ink.
    func sectionLabel() -> some View {
        font(.subheadline.weight(.semibold)).foregroundStyle(Theme.sub)
    }
}

enum Format {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    static func number(_ n: Int) -> String { n.formatted(.number.locale(Locale(identifier: AppLanguage.currentCode))) }
}
