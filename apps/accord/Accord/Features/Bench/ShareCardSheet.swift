import SwiftUI
import UIKit

/// A portrait card (1080 × 1350) to post a creation: bottle, notes by layer, the evaporation curve.
/// Amounts stay hidden unless the user turns them on: a formula is a perfumer's secret.
struct ShareCard: View {
    let formula: Formula
    let mix: MixResult
    var showAmounts = false
    var showMaterials = true

    static let size = CGSize(width: 360, height: 450)

    private var layers: [Double] {
        Tier.Layer.allCases.map { layer in Tier.allCases.filter { $0.layer == layer }.reduce(0) { $0 + mix.grams(in: $1) } }
    }

    private func notes(_ layer: Tier.Layer) -> [MixComponent] {
        Array(mix.components.filter { $0.tier.layer == layer }.prefix(3))
    }

    var body: some View {
        ZStack {
            Theme.paper
            Image(uiImage: PaperGrain.tile(dark: false)).resizable(resizingMode: .tile)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(verbatim: formula.product.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.amberInk)
                    if formula.product != .concentrate {
                        Text(verbatim: "· " + Fmt.percent(formula.concentration * 100, decimals: 0))
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.amberInk)
                    }
                    Spacer()
                    if formula.version > 1 {
                        Text(verbatim: String(localized: "v\(formula.version)", bundle: .l10n)).font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                    }
                }
                HStack(alignment: .center, spacing: 18) {
                    FlaconView(layers: layers.reduce(0, +) > 0 ? layers : [1, 1, 1], live: false)
                        .frame(width: 118, height: 160)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: formula.name)
                            .font(Theme.usesLatinDisplay ? .custom("BodoniModa-MediumItalic", size: 30) : .system(size: 26, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                        if let family = Family.allCases.max(by: { mix.grams(in: $0) < mix.grams(in: $1) }), mix.activeGrams > 0 {
                            HStack(spacing: 5) {
                                Dot(color: Theme.color(family), size: 7)
                                Text(verbatim: family.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        Text(verbatim: String(localized: "lasts ≈ \(Fmt.hours(EvaporationCurve(mix).longevityHours))", bundle: .l10n))
                            .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(.top, 14)

                if showMaterials {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Tier.Layer.allCases, id: \.rawValue) { layer in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.color(layer)).frame(width: 10, height: 3)
                                    Text(verbatim: layerName(layer)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                                }
                                ForEach(notes(layer)) { c in
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(verbatim: c.name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(2)
                                        if showAmounts {
                                            Text(verbatim: Fmt.percent(mix.share(c) * 100, decimals: 1)).font(.system(size: 9).monospacedDigit()).foregroundStyle(Theme.inkSoft)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .padding(.top, 18)
                }

                Spacer(minLength: 10)
                EvaporationChart(mix: mix, hour: .constant(0), live: false)
                    .frame(height: 70)
                    .allowsHitTesting(false)
                HStack {
                    Text(verbatim: "Accord").font(.custom("BodoniModa-MediumItalic", size: 14)).foregroundStyle(Theme.ink)
                    Text("Perfume formula lab").font(.system(size: 9)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text(verbatim: Fmt.date(formula.updatedAt)).font(.system(size: 9)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 8)
            }
            .padding(22)
        }
        .frame(width: ShareCard.size.width, height: ShareCard.size.height)
        .environment(\.colorScheme, .light)
    }

    private func layerName(_ l: Tier.Layer) -> String {
        switch l {
        case .top: return Tier.top.name
        case .heart: return Tier.heart.name
        case .base: return Tier.base.name
        }
    }

    /// 1080 × 1350 PNG-ready image.
    @MainActor static func render(_ card: ShareCard) -> UIImage? {
        let r = ImageRenderer(content: card)
        r.scale = 3
        return r.uiImage
    }
}

struct ShareCardSheet: View {
    let formula: Formula
    @Environment(\.dismiss) private var dismiss
    @State private var showAmounts = false
    @State private var showMaterials = true
    @State private var share: ShareImage?

    struct ShareImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        let mix = formula.mix()
        let card = ShareCard(formula: formula, mix: mix, showAmounts: showAmounts, showMaterials: showMaterials)
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    card
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                        .scaleEffect(0.86)
                        .frame(width: ShareCard.size.width * 0.86, height: ShareCard.size.height * 0.86)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("Share card preview"))
                    VStack(spacing: 0) {
                        Toggle(isOn: $showMaterials) { Text("Show materials") }
                            .padding(.vertical, 10)
                            .hairDivider()
                        Toggle(isOn: $showAmounts) { Text("Show percentages") }
                            .disabled(!showMaterials)
                            .padding(.vertical, 10)
                    }
                    .padding(.horizontal, Theme.Space.m)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                    Text("Percentages are off by default so your formula stays yours.")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                }
                .screenPadding()
                .padding(.vertical, Theme.Space.m)
            }
            .background(PaperBackground())
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let img = ShareCard.render(card) { share = ShareImage(image: img) }
                } label: { Label("Share image", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(Theme.Space.m)
                    .background(Theme.paper.opacity(0.96))
                    .accessibilityIdentifier("share-card")
            }
            .navigationTitle(Text("Share card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $share) { item in ActivityView(items: [item.image]).ignoresSafeArea() }
        }
    }
}
