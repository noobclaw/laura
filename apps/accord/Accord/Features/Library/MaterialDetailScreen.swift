import SwiftUI
import SwiftData

struct MaterialDetailScreen: View {
    @Bindable var material: Material
    var isNew = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Environment(ProStore.self) private var store
    @State private var confirmDelete = false
    @State private var pendingDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField(text: $material.name) { Text("Name") }
                    .font(Theme.display(24, relativeTo: .title2))
                    .focused($nameFocused)
                    .accessibilityIdentifier("material-name")
                Picker(selection: Binding(get: { material.family }, set: { material.family = $0 })) {
                    ForEach(Family.allCases) { f in
                        Label { Text(verbatim: f.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(Theme.color(f)) }.tag(f)
                    }
                } label: { Text("Family") }
                Picker(selection: Binding(get: { material.tier }, set: { material.tier = $0 })) {
                    ForEach(Tier.allCases) { t in Text(verbatim: t.name).tag(t) }
                } label: { Text("Evaporation") }
                Toggle(isOn: $material.isNatural) { Text("Natural") }
                TextField(text: $material.odor, axis: .vertical) { Text("What it smells like") }.lineLimit(1...4)
            } header: { Text("Identity") }
            .listRowBackground(Theme.card)

            Section {
                HStack {
                    Text("Kept at")
                    Spacer()
                    Picker(selection: $material.defaultDilution) {
                        Text("Neat").tag(1.0)
                        Text(verbatim: Fmt.percent(50, decimals: 0)).tag(0.5)
                        Text(verbatim: Fmt.percent(10, decimals: 0)).tag(0.1)
                        Text(verbatim: Fmt.percent(1, decimals: 0)).tag(0.01)
                        Text(verbatim: Fmt.percent(0.1, decimals: 1)).tag(0.001)
                        if ![1, 0.5, 0.1, 0.01, 0.001].contains(material.defaultDilution) {
                            Text(verbatim: Fmt.dilution(material.defaultDilution)).tag(material.defaultDilution)
                        }
                    } label: { EmptyView() }
                }
                if material.defaultDilution < 0.9999 {
                    Picker(selection: Binding(get: { material.defaultSolvent }, set: { material.defaultSolvent = $0 })) {
                        ForEach(Solvent.allCases.filter { $0 != .none }) { s in Text(verbatim: s.name).tag(s) }
                    } label: { Text("Diluted in") }
                }
                numberRow("Drops per gram", value: Binding(get: { material.dropsPerGram }, set: { material.dropsPerGram = max($0 ?? 25, 1) }), suffix: "")
                numberRow("Your maximum in the product", value: $material.limitPercent, suffix: "%")
            } header: { Text("At the bench") } footer: {
                Text("Count drops from your own pipette once and enter it here; viscous materials give fewer, larger drops. Take the maximum from your supplier’s IFRA certificate or SDS.")
            }
            .listRowBackground(Theme.card)

            Section {
                if store.isPro {
                    numberRow("Cost per gram", value: $material.costPerGram, suffix: Fmt.currencyCode)
                    numberRow("In stock", value: $material.stockGrams, suffix: AmountUnit.grams.short)
                    numberRow("Warn below", value: $material.lowStockGrams, suffix: AmountUnit.grams.short)
                    Toggle(isOn: Binding(get: { material.purchaseDate != nil }, set: { material.purchaseDate = $0 ? (material.purchaseDate ?? Date()) : nil })) {
                        Text("Track shelf life")
                    }
                    if material.purchaseDate != nil {
                        DatePicker(selection: Binding(get: { material.purchaseDate ?? Date() }, set: { material.purchaseDate = $0 }), displayedComponents: .date) {
                            Text("Bought or opened")
                        }
                        Stepper(value: Binding(get: { material.shelfLifeMonths ?? 24 }, set: { material.shelfLifeMonths = $0 }), in: 1...120) {
                            Text("Shelf life: \(material.shelfLifeMonths ?? 24) months")
                        }
                        if let exp = material.expiryDate {
                            Text(material.isExpired ? "Past shelf life since \(Fmt.date(exp))" as LocalizedStringKey : "Good until \(Fmt.date(exp))")
                                .font(.footnote).foregroundStyle(material.isExpired ? Theme.danger : Theme.inkSoft)
                        }
                    }
                    TextField(text: $material.supplier) { Text("Supplier") }
                    TextField(text: $material.cas) { Text("CAS number") }.keyboardType(.numbersAndPunctuation)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Track grams left, cost per gram, shelf life and supplier for every material.")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        Button("Unlock stock and cost") { state.proReason = .inventory }
                            .buttonStyle(QuietButtonStyle(wide: false))
                    }
                    .padding(.vertical, 4)
                }
            } header: { HStack { Text("Stock and cost"); if !store.isPro { Tag(text: "Pro", tint: Theme.amberInk) } } }
            .listRowBackground(Theme.card)

            Section {
                TextField(text: $material.notes, axis: .vertical) { Text("Notes") }.lineLimit(2...8)
            } header: { Text("Notes") }
            .listRowBackground(Theme.card)

            if !material.formulas.isEmpty {
                Section {
                    ForEach(material.formulas) { f in
                        let line = material.lines.first { $0.formula?.id == f.id }
                        Button { state.open(f) } label: {
                            HStack {
                                Text(verbatim: f.name).foregroundStyle(Theme.ink)
                                Spacer()
                                if let line, f.totalGrams > 0 {
                                    Text(verbatim: Fmt.percent(line.grams / f.totalGrams * 100)).font(Theme.figure(.subheadline, weight: .regular)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                        }
                    }
                } header: { Text("Used in") }
                .listRowBackground(Theme.card)
            }

            Section {
                Button(role: .destructive) { confirmDelete = true } label: { Text("Delete material") }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
            .textCase(nil)
        .keyboardDoneButton()
        .background(PaperBackground())
        .navigationTitle(Text(verbatim: material.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { if isNew { nameFocused = true } }
        .onDisappear {
            // Delete only after the screen is gone, so nothing renders a deleted model.
            if pendingDelete {
                context.delete(material)
                try? context.save()
                return
            }
            if material.name.trimmingCharacters(in: .whitespaces).isEmpty { material.name = String(localized: "Unnamed material", bundle: .l10n) }
            try? context.save()
        }
        .confirmationDialog(Text("Delete “\(material.name)”?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete material", role: .destructive) {
                pendingDelete = true
                dismiss()
            }
        } message: {
            Text(material.lines.isEmpty ? "It isn’t used in any formula." as LocalizedStringKey : "\(material.formulas.count) formulas use it; those lines will show “Missing material”.")
        }
    }

    private func numberRow(_ title: LocalizedStringKey, value: Binding<Double?>, suffix: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            DecimalField(title: "–", value: value)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
            if !suffix.isEmpty { Text(verbatim: suffix).foregroundStyle(Theme.inkSoft) }
        }
    }
}
