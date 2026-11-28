import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showSources = false

    var body: some View {
        NavigationStack {
            List {
                Section { proCard }.listRowBackground(Theme.surface)
                Section {
                    NavigationLink { LanguagePicker() } label: {
                        HStack {
                            Label("Language", systemImage: "globe")
                            Spacer()
                            Text(verbatim: model.language.override.map(AppLanguage.nativeName) ?? String(localized: "System", bundle: .l10n))
                                .foregroundStyle(Theme.sub)
                        }
                    }
                    .accessibilityIdentifier("settings-language")
                    NavigationLink { SourcesView() } label: { Label("Sources", systemImage: "externaldrive.connected.to.line.below") }
                        .accessibilityIdentifier("settings-sources")
                }
                .listRowBackground(Theme.surface)
                Section {
                    Button { model.rateFromSettings() } label: { Label("Rate Spindle", systemImage: "star") }
                        .accessibilityIdentifier("settings-rate")
                    Link(destination: ReviewGate.feedbackURL(appVersion: AppInfo.version, osVersion: UIDevice.current.systemVersion)) {
                        Label("Send feedback", systemImage: "envelope")
                    }
                    Link(destination: AppInfo.privacyURL) { Label("Privacy policy", systemImage: "hand.raised") }
                } footer: {
                    Text("Spindle collects no data. Your server passwords stay in this iPhone’s Keychain and your music goes straight from your server to you.")
                }
                .listRowBackground(Theme.surface)
                Section {
                    LabeledContent("Version") { Text(verbatim: AppInfo.version).font(Theme.mono) }
                    LabeledContent("Display font") { Text(verbatim: "Anton · SIL OFL 1.1") }
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder private var proCard: some View {
        if model.pro.isPro {
            Label("Spindle Pro is unlocked", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        } else {
            Button { model.paywall = .settings } label: {
                HStack(spacing: Theme.s3) {
                    VinylView(albumKey: "pro", title: "P", size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spindle Pro").font(.headline).foregroundStyle(Theme.ink)
                        Text("Unlimited sources, playlists and offline songs").font(.caption).foregroundStyle(Theme.sub)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.sub)
                }
            }
            .accessibilityIdentifier("settings-pro")
        }
    }
}

struct LanguagePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Button { model.language.select(nil) } label: {
                row(String(localized: "Follow system", bundle: .l10n), selected: model.language.override == nil)
            }
            ForEach(AppLanguage.supported, id: \.self) { code in
                Button { model.language.select(code) } label: { row(AppLanguage.nativeName(code), selected: model.language.override == code) }
                    .accessibilityIdentifier("lang-\(code)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(Text("Language"))
    }

    private func row(_ name: String, selected: Bool) -> some View {
        HStack {
            Text(verbatim: name).foregroundStyle(Theme.ink)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let reason: ProReason

    var body: some View {
        let pro = model.pro
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    SpindleStack(discs: [
                        .init(id: UUID(), name: "a", count: 3, active: false),
                        .init(id: UUID(), name: "b", count: 2, active: false),
                        .init(id: UUID(), name: "c", count: 4, active: true),
                    ])
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    Text(reason.headline)
                        .font(Theme.display(32, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("paywall-title")
                    VStack(alignment: .leading, spacing: Theme.s3) {
                        feature("externaldrive.connected.to.line.below", "Every NAS, WebDAV server and folder you own")
                        feature("music.note.list", "Unlimited playlists")
                        feature("arrow.down.circle", "Unlimited offline songs")
                        feature("moon.zzz", "Sleep timer with a gentle fade")
                    }
                    Text("One payment, yours for good. Not a subscription. Shared with your family.")
                        .font(.subheadline).foregroundStyle(Theme.sub)
                    if pro.isPro {
                        Label("Spindle Pro is unlocked", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.accent)
                    } else {
                        Button { Task { await pro.purchase(); if pro.isPro { dismiss() } } } label: {
                            HStack {
                                if pro.isPurchasing { ProgressView().tint(Theme.onAccent) }
                                if let price = pro.displayPrice {
                                    Text("Unlock Pro · \(price)")
                                } else if pro.loadFailed {
                                    Text("Unlock Pro")
                                } else {
                                    Text("Unlock Pro"); ProgressView().tint(Theme.onAccent)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(pro.isPurchasing)
                        .accessibilityIdentifier("paywall-buy")
                        if pro.loadFailed {
                            HStack {
                                Text("The App Store isn’t reachable right now. Check your connection and try again.")
                                    .font(.caption).foregroundStyle(Theme.signal)
                                Button("Retry") { Task { await pro.load() } }.font(.caption.weight(.semibold))
                            }
                        }
                        Button { Task { await pro.restore() } } label: {
                            HStack { Text("Restore Purchases"); if pro.isRestoring { ProgressView() } }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("paywall-restore")
                    }
                    if let m = pro.message {
                        Text(verbatim: m).font(.footnote).foregroundStyle(Theme.sub)
                    }
                }
                .padding(Theme.s3)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("paywall-close") } }
        }
        .accessibilityIdentifier("paywall")
        .onDisappear { pro.message = nil }
    }

    private func feature(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.s3) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.accent).frame(width: 30)
            Text(text).foregroundStyle(Theme.ink)
        }
    }
}

struct ReviewCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s3) {
                VinylView(albumKey: "review", title: "S", size: 40)
                Text("Enjoying Spindle?").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                Button { model.showReviewCard = false } label: { Image(systemName: "xmark").foregroundStyle(Theme.sub).frame(width: 44, height: 44) }
                    .accessibilityLabel(Text("Close"))
            }
            HStack(spacing: Theme.s2) {
                Button { model.reviewLoved() } label: { Text("Love it").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
                Button { model.reviewNotYet() } label: { Text("Not yet").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.s3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard).stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}
