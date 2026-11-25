import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Palette {
    static let ground = Color(hex: 0x07041A)
    static let groundTop = Color(hex: 0x120A2E)
    static let surface = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.12)
    static let text = Color(hex: 0xF1EEFF)
    static let textDim = Color(hex: 0xB7AEDC)
    static let textFaint = Color(hex: 0x8C83B5)

    /// Brand magenta (hue 315°) and its partner violet.
    static let brand = Color(hex: 0xFF3DCF)
    static let violet = Color(hex: 0x7B5CFF)
    static let gold = Color(hex: 0xFFD23F)
    static let cyan = Color(hex: 0x4CC9F0)
    static let mint = Color(hex: 0x3DDC97)
    static let ember = Color(hex: 0xFFB13B)
    static let danger = Color(hex: 0xFF5A6E)

    /// Lane colors, ordered like DrumPiece.allCases. Lightness differs so lanes read apart without hue.
    static let lanes: [Color] = [
        Color(hex: 0xFF6B3D), // kick – orange
        Color(hex: 0xFFD23F), // snare – yellow (lightest)
        Color(hex: 0x4CC9F0), // hi-hat – cyan
        Color(hex: 0x9B8CFF), // tom – violet
        Color(hex: 0x3DDC97), // ride – green
        Color(hex: 0xFF4D8D)  // crash – pink
    ]

    static func color(_ piece: DrumPiece) -> Color { lanes[piece.lane] }

    static func grade(_ g: Grade) -> Color {
        switch g {
        case .s: return gold
        case .a: return cyan
        case .b: return mint
        case .c: return Color(hex: 0x9B8CFF)
        case .d: return textFaint
        }
    }
}

/// Typography: Unbounded for display, Chakra Petch for HUD numerals, system for body text.
/// Scripts the custom faces don't cover (CJK) fall back to the rounded system face.
enum Typo {
    static var usesLatinDisplay: Bool {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return !["ja", "ko", "zh"].contains(code)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        guard usesLatinDisplay else { return .system(size: size * 0.96, weight: .heavy, design: .rounded) }
        let name: String
        switch weight {
        case .heavy, .black: name = "Unbounded-ExtraBold"
        case .semibold, .medium, .regular: name = "Unbounded-SemiBold"
        default: name = "Unbounded-Bold"
        }
        return .custom(name, size: size, relativeTo: .title)
    }

    /// Numbers and HUD labels (Latin digits exist in every locale, so always the custom face).
    static func hud(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "ChakraPetch-Bold"
        case .medium, .regular, .light: name = "ChakraPetch-Medium"
        default: name = "ChakraPetch-SemiBold"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    /// Small uppercase labels: HUD face for Latin, system for CJK.
    static func label(_ size: CGFloat = 11) -> Font {
        usesLatinDisplay ? hud(size, weight: .bold) : .system(size: size, weight: .bold)
    }

    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func hit(_ intensity: CGFloat = 0.8) { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: intensity) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

extension View {
    /// Tracking for uppercase HUD labels.
    func hudLabel(_ color: Color = Palette.textDim, size: CGFloat = 11) -> some View {
        self.font(Typo.label(size)).tracking(Typo.usesLatinDisplay ? 1.6 : 0.4).foregroundStyle(color)
    }

    func glassCard(cornerRadius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.55))
                    .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Palette.stroke, lineWidth: 1))
            }
            .environment(\.colorScheme, .dark)
    }

    func neonGlow(_ color: Color, radius: CGFloat = 12, active: Bool = true) -> some View {
        self.shadow(color: active ? color.opacity(0.75) : .clear, radius: radius)
    }
}

/// Press-down scale + haptic for every tappable surface.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

/// Primary call to action: magenta→violet capsule with glow.
struct NeonButton: View {
    let title: String
    var symbol: String?
    var fill: [Color] = [Palette.brand, Palette.violet]
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().tint(.white)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                }
                Text(title).font(Typo.display(16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(LinearGradient(colors: fill, startPoint: .leading, endPoint: .trailing)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: (fill.first ?? Palette.brand).opacity(0.55), radius: 18, y: 6)
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }
}

/// Animated neon ground with drifting light blobs.
struct NeonBackground: View {
    var colors: [Color] = [Palette.ground, Palette.groundTop]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                g.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .linearGradient(Gradient(colors: [colors.last ?? Palette.groundTop, colors.first ?? Palette.ground]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                let blobs: [(Color, CGFloat, CGFloat, CGFloat, Double)] = [
                    (Palette.brand, 0.05, 0.08, 0.95, 0.07),
                    (Palette.cyan, 0.95, 0.38, 1.05, 0.05),
                    (Palette.violet, 0.2, 0.92, 0.9, 0.06)
                ]
                for (i, b) in blobs.enumerated() {
                    let phase = reduceMotion ? 0 : t * b.4 + Double(i) * 2.1
                    let cx = size.width * (b.1 + 0.06 * CGFloat(sin(phase)))
                    let cy = size.height * (b.2 + 0.04 * CGFloat(cos(phase * 1.3)))
                    let r = size.width * b.3 * 0.5
                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    g.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [b.0.opacity(0.34), b.0.opacity(0)]),
                                                                       center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
                }
            }
        }
        .ignoresSafeArea()
    }
}
