import SwiftUI

struct ProSheet: View {
    let reason: ProReason
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Perk: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private var perks: [Perk] {
        [
            Perk(symbol: "infinity", title: String(localized: "Unlimited formulas", bundle: .l10n),
                 detail: String(localized: "Every draft, every version.", bundle: .l10n)),
            Perk(symbol: "square.stack.3d.up", title: String(localized: "Bases inside formulas", bundle: .l10n),
                 detail: String(localized: "Use your accords as ingredients; Accord unpacks them.", bundle: .l10n)),
            Perk(symbol: "hourglass", title: String(localized: "Batches and maturation diary", bundle: .l10n),
                 detail: String(localized: "What you weighed, and how it smelled on day 7, 14, 28.", bundle: .l10n)),
            Perk(symbol: "arrow.left.arrow.right", title: String(localized: "Compare versions", bundle: .l10n),
                 detail: String(localized: "See every material that moved between two drafts.", bundle: .l10n)),
            Perk(symbol: "shippingbox", title: String(localized: "Stock and cost", bundle: .l10n),
                 detail: String(localized: "Grams left, low-stock and expiry warnings, cost per bottle.", bundle: .l10n)),
            Perk(symbol: "square.and.arrow.up.on.square", title: String(localized: "Import, export and backup", bundle: .l10n),
                 detail: String(localized: "CSV, PDF, Markdown, and a full backup file.", bundle: .l10n)),
            Perk(symbol: "faceid", title: String(localized: "App Lock", bundle: .l10n),
                 detail: String(localized: "Keep your formulas behind Face ID.", bundle: .l10n)),
        ]
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.headline).foregroundStyle(Theme.inkSoft).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("Close"))
                    }
                    FlaconView(layers: [0.3, 0.35, 0.35])
                        .frame(width: 84, height: 112)
                    Text(verbatim: reason.headline)
                        .font(Theme.display(34, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Accord Pro is one purchase. No subscription, no account, everything stays on your iPhone.")
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        ForEach(perks) { perk in
                            HStack(alignment: .top, spacing: Theme.Space.m) {
                                Image(systemName: perk.symbol)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Theme.amberInk)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: perk.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text(verbatim: perk.detail).font(.subheadline).foregroundStyle(Theme.inkSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, Theme.Space.s)
                }
                .padding(Theme.Space.m)
                .padding(.bottom, 180)
            }
            VStack {
                Spacer()
                VStack(spacing: Theme.Space.s) {
                    if store.isPro {
                        Label("Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline).foregroundStyle(Theme.ok)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else if let price = store.displayPrice {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            if store.isPurchasing { ProgressView().tint(Theme.onAmber) }
                            else { Text("Unlock Pro for \(price)") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(store.isPurchasing)
                        .accessibilityIdentifier("buy-pro")
                    } else if store.loadFailed {
                        Button { Task { await store.load() } } label: { Label("Couldn’t reach the App Store. Try again", systemImage: "arrow.clockwise") }
                            .buttonStyle(QuietButtonStyle())
                    } else {
                        ProgressView().frame(minHeight: 52)
                    }
                    Button {
                        Task { await store.restore() }
                    } label: {
                        if store.isRestoring { ProgressView() } else { Text("Restore purchase") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minHeight: 44)
                    .disabled(store.isRestoring)
                }
                .padding(Theme.Space.m)
                .background(Theme.paper.opacity(0.97).ignoresSafeArea())
            }
        }
        .onChange(of: store.isPro) { _, pro in if pro { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() } } }
        .alert(Text(verbatim: store.message ?? ""), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}
