import SwiftUI

/// The neon paywall. Every Pro gate opens this first; the price always comes from StoreKit.
struct ProSheet: View {
    let reason: ProReason
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Perk: Identifiable {
        let id = UUID()
        let symbol: String
        let color: Color
        let title: String
        let detail: String
    }

    private var perks: [Perk] {
        [
            Perk(symbol: "infinity", color: Palette.brand, title: String(localized: "Unlimited songs"),
                 detail: String(localized: "Chart your whole setlist, not just three tracks.")),
            Perk(symbol: "mic.fill", color: Palette.cyan, title: String(localized: "Kit mode"),
                 detail: String(localized: "Play your real drums — the mic scores every hit.")),
            Perk(symbol: "speedometer", color: Palette.gold, title: String(localized: "Speed trainer"),
                 detail: String(localized: "Start slow, climb 5% after every clean loop.")),
            Perk(symbol: "flame.fill", color: Palette.ember, title: String(localized: "Fill library"),
                 detail: String(localized: "Every fill from every song, ready to drill.")),
            Perk(symbol: "square.and.arrow.up.fill", color: Palette.mint, title: String(localized: "MIDI, MusicXML & PDF"),
                 detail: String(localized: "Open your charts in your DAW or notation app.")),
            Perk(symbol: "sparkles", color: Palette.violet, title: String(localized: "Every stage skin"),
                 detail: String(localized: "Vintage, Studio and Arcade — no grinding."))
        ]
    }

    var body: some View {
        ZStack {
            NeonBackground(colors: [Color(hex: 0x0B0524), Color(hex: 0x2A0B3D)])
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.textDim)
                                .frame(width: 36, height: 36).background(Circle().fill(Palette.surface))
                        }
                        .accessibilityLabel(Text("Close"))
                        .accessibilityIdentifier("close-pro")
                    }
                    emblem
                    VStack(spacing: 8) {
                        Text(reason.headline).font(Typo.display(24)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
                        Text(String(localized: "One purchase. Yours forever. No subscription."))
                            .font(Typo.body(15)).foregroundStyle(Palette.textDim).multilineTextAlignment(.center)
                    }
                    VStack(spacing: 10) {
                        ForEach(Array(perks.enumerated()), id: \.element.id) { i, p in
                            HStack(spacing: 14) {
                                Image(systemName: p.symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(p.color)
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(p.color.opacity(0.14)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.title).font(Typo.body(15, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text(p.detail).font(Typo.body(13)).foregroundStyle(Palette.textDim).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(x: appeared ? 0 : 24)
                            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8).delay(0.05 * Double(i)), value: appeared)
                        }
                    }
                    .glassCard()

                    VStack(spacing: 12) {
                        if store.isPro {
                            Label(String(localized: "Pro is unlocked. Thank you!"), systemImage: "checkmark.seal.fill")
                                .font(Typo.body(16, weight: .semibold)).foregroundStyle(Palette.mint)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        } else {
                            if store.loadFailed && store.product == nil {
                                VStack(spacing: 10) {
                                    Text(String(localized: "The App Store isn’t reachable right now. Check your connection and try again."))
                                        .font(Typo.body(14)).foregroundStyle(Palette.textDim).multilineTextAlignment(.center)
                                    NeonButton(title: String(localized: "Try again"), symbol: "arrow.clockwise", busy: store.isLoadingProduct) {
                                        Task { await store.load() }
                                    }
                                }
                            } else {
                                NeonButton(title: buyTitle, symbol: "lock.open.fill", busy: store.isPurchasing || store.isLoadingProduct) {
                                    Task { await store.purchase() }
                                }
                                .disabled(store.product == nil)
                            }
                        }
                        Button {
                            Task { await store.restore() }
                        } label: {
                            HStack(spacing: 6) {
                                if store.isRestoring { ProgressView().controlSize(.small).tint(Palette.textDim) }
                                Text(String(localized: "Restore purchases"))
                            }
                            .font(Typo.body(14, weight: .semibold)).foregroundStyle(Palette.textDim)
                        }
                        .disabled(store.isRestoring)
                        if let m = store.message {
                            Text(m).font(Typo.body(13)).foregroundStyle(Palette.textDim).multilineTextAlignment(.center)
                        }
                        Text(String(localized: "Payment is charged to your Apple Account. Family Sharing supported."))
                            .font(Typo.body(11)).foregroundStyle(Palette.textFaint).multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30).padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { appeared = true }
        .task { if store.product == nil { await store.load() } }
        .onChange(of: store.isPro) { _, pro in
            if pro {
                Haptics.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { dismiss() }
            }
        }
    }

    private var buyTitle: String {
        if let price = store.displayPrice { return String(localized: "Unlock Pro — \(price)") }
        return String(localized: "Unlock Pro")
    }

    private var emblem: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    Capsule()
                        .fill(Palette.lanes[i])
                        .frame(width: 8, height: 46 + 30 * CGFloat(abs(sin(t * 2.2 + Double(i) * 0.9))))
                        .shadow(color: Palette.lanes[i].opacity(0.9), radius: 8)
                        .offset(x: CGFloat(i - 3) * 16 + 8)
                }
                Circle().strokeBorder(
                    AngularGradient(colors: [Palette.brand, Palette.violet, Palette.cyan, Palette.brand], center: .center,
                                    angle: .degrees(t * 40)), lineWidth: 3)
                    .frame(width: 140, height: 140)
                    .shadow(color: Palette.brand.opacity(0.6), radius: 20)
            }
            .frame(height: 150)
        }
        .accessibilityHidden(true)
    }
}
