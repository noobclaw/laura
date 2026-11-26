import SwiftUI
import UIKit

// MARK: - Formatting

enum Fmt {
    static var locale: Locale { Locale(identifier: AppLanguage.currentCode) }

    /// "12.5", "0.125", "120": up to 3 decimals, no trailing zeros.
    static func number(_ v: Double, maxDecimals: Int = 3) -> String {
        v.formatted(.number.precision(.fractionLength(0...maxDecimals)).grouping(.never).locale(locale))
    }

    static func grams(_ v: Double) -> String {
        let decimals = v >= 100 ? 1 : (v >= 10 ? 2 : 3)
        return number(v, maxDecimals: decimals) + " " + AmountUnit.grams.short
    }

    static func drops(_ v: Double) -> String { number(v.rounded(), maxDecimals: 0) + " " + AmountUnit.drops.short }

    /// `v` is 0…100.
    static func percent(_ v: Double, decimals: Int = 2) -> String {
        (v / 100).formatted(.percent.precision(.fractionLength(0...decimals)).locale(locale))
    }

    static var currencyCode: String {
        UserDefaults.standard.string(forKey: "accord.currency") ?? Locale.current.currency?.identifier ?? "USD"
    }

    static func money(_ v: Double) -> String {
        v.formatted(.currency(code: currencyCode).precision(.fractionLength(2)).locale(locale))
    }

    static func dilution(_ d: Double) -> String {
        d >= 0.9999 ? String(localized: "Neat", bundle: .l10n) : percent(d * 100, decimals: 2)
    }

    static func date(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)) }

    static func hours(_ h: Double) -> String {
        h < 1 ? String(localized: "\(number(h * 60, maxDecimals: 0)) min", bundle: .l10n)
              : String(localized: "\(number(h, maxDecimals: 1)) h", bundle: .l10n)
    }

    /// Parses user input with either decimal separator.
    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }
}

// MARK: - Paper

/// Warm paper with a faint grain, drawn once and tiled.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Theme.paper
            .overlay(Image(uiImage: PaperGrain.tile(dark: scheme == .dark)).resizable(resizingMode: .tile).opacity(1))
            .ignoresSafeArea()
    }
}

enum PaperGrain {
    private static var cache: [Bool: UIImage] = [:]

    static func tile(dark: Bool) -> UIImage {
        if let img = cache[dark] { return img }
        let size = CGSize(width: 128, height: 128)
        var rng = SeededRandom(seed: 7)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            for _ in 0..<900 {
                let x = CGFloat(rng.next() % 128), y = CGFloat(rng.next() % 128)
                let a = CGFloat(rng.next() % 100) / 100 * 0.05
                (dark ? UIColor.white : UIColor.black).withAlphaComponent(a).setFill()
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        cache[dark] = img
        return img
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var wide = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAmber)
            .padding(.horizontal, Theme.Space.l)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 52)
            .background(Theme.amber, in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var wide = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.l)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.85), lineWidth: 1.2)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Pieces

/// Section heading in the display face, sentence case.
struct SectionTitle: View {
    let text: LocalizedStringKey
    var trailing: AnyView? = nil

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(Theme.display(22, italic: true, relativeTo: .title3)).foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small rounded tag (product type, dilution, version).
struct Tag: View {
    let text: String
    var tint: Color = Theme.inkSoft
    var filled = false

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? Theme.onAmber : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(filled ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(tint.opacity(0.12)))
            )
    }
}

/// Paper card that groups content.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hair))
    }
}

/// A key–value line in detail screens.
struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.inkSoft)
            Spacer(minLength: Theme.Space.m)
            Text(verbatim: value).font(Theme.figure(.body, weight: .medium)).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }
}

/// Empty state that offers a real action instead of a lone line of grey text.
struct ActionEmpty: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let action: LocalizedStringKey
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(Theme.display(24, relativeTo: .title2)).foregroundStyle(Theme.ink)
            Text(message).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            Button(action: perform) { Text(action) }
                .buttonStyle(PrimaryButtonStyle(wide: false))
                .padding(.top, Theme.Space.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
    }
}

/// Colour swatch dot for a family or tier.
struct Dot: View {
    let color: Color
    var size: CGFloat = 8
    var body: some View { Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true) }
}

extension View {
    /// Standard screen padding.
    func screenPadding() -> some View { padding(.horizontal, Theme.Space.m) }

    func hairDivider() -> some View {
        overlay(alignment: .bottom) { Rectangle().fill(Theme.hair).frame(height: 0.5) }
    }
}

/// A text field for decimal numbers that accepts "," or ".".
struct DecimalField: View {
    let title: LocalizedStringKey
    @Binding var value: Double?
    var suffix: String = ""
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .font(Theme.figure(.body, weight: .medium))
                .focused($focused)
                .onChange(of: text) { _, new in value = Fmt.parse(new) }
            if !suffix.isEmpty { Text(verbatim: suffix).foregroundStyle(Theme.inkSoft) }
        }
        .onAppear { text = value.map { Fmt.number($0, maxDecimals: 4) } ?? "" }
        .onChange(of: value) { _, new in
            if !focused { text = new.map { Fmt.number($0, maxDecimals: 4) } ?? "" }
        }
    }
}
