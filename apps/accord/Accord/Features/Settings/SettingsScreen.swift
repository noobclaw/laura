import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppLanguage.self) private var language
    @Environment(ProStore.self) private var store
    @Environment(AppLock.self) private var lock
    @AppStorage("accord.currency") private var currency = Locale.current.currency?.identifier ?? "USD"
    @AppStorage("accord.alcoholPerKg") private var alcoholPerKg: Double = 0

    @State private var showLanguage = false
    @State private var proReason: ProReason?
    @State private var share: ShareItem?
    @State private var restoring = false
    @State private var message: String?

    static let currencies = ["USD", "EUR", "GBP", "JPY", "CNY", "TWD", "HKD", "KRW", "CAD", "AUD", "CHF", "BRL", "SGD"]

    var body: some View {
        NavigationStack {
            Form {
                Section { proCard }
                    .listRowBackground(Theme.card)

                Section {
                    Button { showLanguage = true } label: {
                        HStack {
                            Label { Text("App language").foregroundStyle(Theme.ink) } icon: { Image(systemName: "globe").foregroundStyle(Theme.amberInk) }
                            Spacer()
                            Text(verbatim: language.override.map(AppLanguage.nativeName) ?? String(localized: "System", bundle: .l10n))
                                .foregroundStyle(Theme.inkSoft)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .accessibilityIdentifier("language-row")
                    Picker(selection: $currency) {
                        ForEach(Self.currencies.contains(currency) ? Self.currencies : [currency] + Self.currencies, id: \.self) { c in
                            Text(verbatim: c).tag(c)
                        }
                    } label: { Label { Text("Currency") } icon: { Image(systemName: "banknote").foregroundStyle(Theme.amberInk) } }
                    HStack {
                        Label { Text("Alcohol price per kg") } icon: { Image(systemName: "drop.triangle").foregroundStyle(Theme.amberInk) }
                        Spacer()
                        DecimalField(title: "0", value: Binding(get: { alcoholPerKg > 0 ? alcoholPerKg : nil }, set: { alcoholPerKg = $0 ?? 0 }))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                } header: { Text("Preferences") }
                .listRowBackground(Theme.card)

                Section {
                    Toggle(isOn: Binding(get: { lock.isEnabled }, set: { on in
                        if !store.isPro { proReason = .appLock; return }
                        if on {
                            if !lock.enable() { message = String(localized: "Set a passcode on this iPhone first; App Lock needs it.", bundle: .l10n) }
                        } else {
                            lock.isEnabled = false
                        }
                    })) {
                        Label { Text("App Lock") } icon: { Image(systemName: "faceid").foregroundStyle(Theme.amberInk) }
                    }
                } header: { Text("Privacy") } footer: {
                    Text("Accord has no account and no server. Your formulas never leave this iPhone unless you export them.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button { proGate(.export) { makeBackup() } } label: {
                        Label { Text("Back up everything").foregroundStyle(Theme.ink) } icon: { Image(systemName: "externaldrive").foregroundStyle(Theme.amberInk) }
                    }
                    Button { proGate(.importData) { restoring = true } } label: {
                        Label { Text("Restore from a backup").foregroundStyle(Theme.ink) } icon: { Image(systemName: "arrow.counterclockwise").foregroundStyle(Theme.amberInk) }
                    }
                } header: { Text("Your data") } footer: {
                    Text("A backup is one file with every material, formula and batch. Restoring adds what’s missing and never overwrites what’s on this iPhone.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Link(destination: URL(string: "https://256btc.com/support/")!) {
                        Label { Text("Help and contact").foregroundStyle(Theme.ink) } icon: { Image(systemName: "questionmark.circle").foregroundStyle(Theme.amberInk) }
                    }
                    Link(destination: URL(string: "https://256btc.com/privacy/accord/")!) {
                        Label { Text("Privacy policy").foregroundStyle(Theme.ink) } icon: { Image(systemName: "hand.raised").foregroundStyle(Theme.amberInk) }
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(verbatim: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                            .foregroundStyle(Theme.inkSoft)
                    }
                } header: { Text("About") } footer: {
                    Text("Starter materials carry general descriptions only. Safety limits differ by supplier and product type: always check the documents that came with your materials.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .keyboardDoneButton()
            .background(PaperBackground())
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showLanguage) { LanguagePickerSheet() }
            .sheet(item: $proReason) { ProSheet(reason: $0) }
            .sheet(item: $share) { item in ActivityView(items: [item.url]).ignoresSafeArea() }
            .fileImporter(isPresented: $restoring, allowedContentTypes: [.json]) { result in restore(result) }
            .onChange(of: store.message) { _, new in
                if let new, proReason == nil { message = new; store.message = nil }
            }
            .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private var proCard: some View {
        HStack(spacing: Theme.Space.m) {
            FlaconView(layers: [0.3, 0.35, 0.35]).frame(width: 40, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.isPro ? "Accord Pro" as LocalizedStringKey : "Accord Free").font(Theme.display(20, relativeTo: .headline))
                Text(store.isPro ? "Everything is unlocked. Thank you." as LocalizedStringKey : "5 formulas, full calculator and analysis.")
                    .font(.footnote).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if !store.isPro {
                Button("Unlock") { proReason = .settings }
                    .buttonStyle(PrimaryButtonStyle(wide: false))
                    .accessibilityIdentifier("settings-unlock")
            }
        }
        if !store.isPro {
            Button {
                Task { await store.restore() }
            } label: { Text("Restore purchase") }
            .font(.subheadline)
        }
    }

    private func proGate(_ reason: ProReason, _ action: () -> Void) {
        if store.isPro { action() } else { proReason = reason }
    }

    private func makeBackup() {
        do { share = ShareItem(url: try Backup.make(context)) } catch { message = error.localizedDescription }
    }

    private func restore(_ result: Swift.Result<URL, Error>) {
        do {
            let url = try result.get()
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let s = try Backup.restore(try Data(contentsOf: url), into: context)
            message = String(localized: "Restored \(s.formulas) formulas, \(s.materials) materials and \(s.batches) batches.", bundle: .l10n)
        } catch {
            message = String(localized: "This file isn’t an Accord backup.", bundle: .l10n)
        }
    }
}

struct LanguagePickerSheet: View {
    @Environment(AppLanguage.self) private var language
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(nil, title: String(localized: "Use system language", bundle: .l10n), detail: AppLanguage.nativeName(language.systemCode))
                }
                .listRowBackground(Theme.card)
                Section {
                    ForEach(AppLanguage.supported, id: \.self) { code in
                        choice(code, title: AppLanguage.nativeName(code), detail: nil)
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle(Text("App language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func choice(_ code: String?, title: String, detail: String?) -> some View {
        let selected = language.override == code
        return Button {
            Haptics.select()
            dismiss()
            // Switch after the sheet starts closing so the rebuild doesn't fight the dismissal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeInOut(duration: 0.3)) { language.select(code) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).foregroundStyle(Theme.ink)
                    if let detail { Text(verbatim: detail).font(.caption).foregroundStyle(Theme.inkSoft) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.amberInk) }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("lang-\(code ?? "system")")
    }
}
