import SwiftUI

/// Pyramid, families, character and cost.
struct AnalysisPanel: View {
    let formula: Formula
    let mix: MixResult
    @Environment(ProStore.self) private var store
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Pyramid").font(Theme.display(20, italic: true, relativeTo: .title3))
                    PyramidView(mix: mix)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Families").font(Theme.display(20, italic: true, relativeTo: .title3))
                    if mix.activeGrams > 0 { FamilyRing(mix: mix) } else { Text("Add materials to see the balance.").foregroundStyle(Theme.inkSoft) }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Character").font(Theme.display(20, italic: true, relativeTo: .title3)).padding(.bottom, 6)
                    InfoRow(label: "Materials (bases unpacked)", value: "\(mix.components.count)")
                    InfoRow(label: "Naturals", value: Fmt.percent(naturalShare * 100, decimals: 0))
                    InfoRow(label: "Estimated longevity", value: Fmt.hours(EvaporationCurve(mix).longevityHours))
                    if let heaviest = mix.components.first {
                        InfoRow(label: "Backbone", value: "\(heaviest.name) · \(Fmt.percent(mix.share(heaviest) * 100, decimals: 1))")
                    }
                }
            }
            costCard
            if formula.usesBases {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Bases unpacked").font(Theme.display(20, italic: true, relativeTo: .title3))
                        ForEach(mix.components) { c in
                            HStack {
                                Dot(color: Theme.color(c.tier))
                                Text(verbatim: c.name).font(.subheadline)
                                Spacer()
                                Text(verbatim: Fmt.percent(mix.share(c) * 100, decimals: 2)).font(Theme.figure(.subheadline, weight: .regular))
                            }
                        }
                    }
                }
            }
        }
    }

    private var naturalShare: Double {
        let total = mix.activeGrams
        guard total > 0 else { return 0 }
        let naturalKeys = Set(formula.lines.compactMap { $0.material }.filter(\.isNatural).map { $0.id.uuidString })
        var nested = Set<String>()
        for line in formula.lines {
            if let b = line.base { nested.formUnion(b.lines.compactMap { $0.material }.filter(\.isNatural).map { $0.id.uuidString }) }
        }
        let keys = naturalKeys.union(nested)
        return mix.components.filter { keys.contains($0.key) }.reduce(0) { $0 + $1.pureGrams } / total
    }

    @ViewBuilder private var costCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Cost").font(Theme.display(20, italic: true, relativeTo: .title3))
                    Spacer()
                    if !store.isPro { Tag(text: "Pro", tint: Theme.amberInk) }
                }
                .padding(.bottom, 6)
                if store.isPro {
                    let cost = mix.cost
                    InfoRow(label: "This batch", value: Fmt.money(cost.value))
                    InfoRow(label: "Per 100 g concentrate", value: mix.totalGrams > 0 ? Fmt.money(cost.value / mix.totalGrams * 100) : "–")
                    if formula.product != .concentrate {
                        InfoRow(label: "Per 50 ml bottle", value: Fmt.money(bottleCost(cost.value, ml: 50)))
                    }
                    if cost.missing > 0 {
                        Text("\(cost.missing) materials have no price yet. Add it in Materials.")
                            .font(.footnote).foregroundStyle(Theme.warn).padding(.top, 4)
                    }
                } else {
                    Text("See what each batch and bottle costs from your own material prices.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    Button("Unlock cost") { state.proReason = .inventory }
                        .buttonStyle(QuietButtonStyle(wide: false)).padding(.top, Theme.Space.s)
                }
            }
        }
    }

    private func bottleCost(_ batchCost: Double, ml: Double) -> Double {
        let plan = ScalePlan.make(FormulaActions.scaleInput(formula),
                                  mode: .bottle(ml: ml, concentration: formula.concentration, waterShare: 0))
        let alcoholPerKg = UserDefaults.standard.double(forKey: "accord.alcoholPerKg")
        return batchCost * plan.factor + plan.ethanolGrams / 1000 * alcoholPerKg
    }
}

/// Finished product: concentration, per-material levels and the user's own limits.
struct ProductPanel: View {
    @Bindable var formula: Formula
    let mix: MixResult
    let plan: () -> Void

    var body: some View {
        let rows = Compliance.check(mix, concentration: formula.concentration)
        let safe = Compliance.maxSafeConcentration(mix)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Finished product").font(Theme.display(20, italic: true, relativeTo: .title3))
                    Picker(selection: Binding(get: { formula.product }, set: { p in
                        formula.product = p
                        formula.concentration = p.defaultConcentration
                        formula.touch()
                    })) {
                        ForEach(ProductType.allCases) { p in Text(verbatim: p.name).tag(p) }
                    } label: { Text("Type") }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("product-type")

                    if formula.product != .concentrate {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Fragrance load")
                                Spacer()
                                Text(verbatim: Fmt.percent(formula.concentration * 100, decimals: 1)).font(Theme.figure(.title3))
                            }
                            Slider(value: $formula.concentration, in: 0.005...0.4, step: 0.005)
                                .accessibilityLabel(Text("Fragrance load"))
                        }
                        if let safe, safe < formula.concentration {
                            Label {
                                Text("Your limits allow up to \(Fmt.percent(safe * 100, decimals: 1)) in this product.")
                            } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                            .font(.footnote).foregroundStyle(Theme.danger)
                        } else if let safe {
                            Text("Your limits allow up to \(Fmt.percent(safe * 100, decimals: 1)) in this product.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Button(action: plan) { Label("Plan a batch", systemImage: "scalemass") }
                        .buttonStyle(QuietButtonStyle())
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Your limits").font(Theme.display(20, italic: true, relativeTo: .title3))
                    if rows.isEmpty {
                        Text("Add a maximum % to any material in Materials (from your supplier’s documents) and Accord checks every formula against it.")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    } else {
                        ForEach(rows) { row in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: row.status == .over ? "xmark.octagon.fill" : (row.status == .near ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                                    .foregroundStyle(row.status == .over ? Theme.danger : (row.status == .near ? Theme.warn : Theme.ok))
                                    .accessibilityHidden(true)
                                Text(verbatim: row.component.name).font(.subheadline)
                                Spacer()
                                Text(verbatim: "\(Fmt.percent(row.inProduct, decimals: 3)) / \(Fmt.percent(row.limit, decimals: 3))")
                                    .font(Theme.figure(.subheadline, weight: .regular))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text("Accord compares against the limits you enter. It is not a regulatory assessment.")
                        .font(.caption).foregroundStyle(Theme.inkSoft).padding(.top, 4)
                }
            }

            if formula.product != .concentrate {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("In the bottle").font(Theme.display(20, italic: true, relativeTo: .title3))
                        ForEach(mix.components.prefix(12)) { c in
                            HStack {
                                Dot(color: Theme.color(c.tier))
                                Text(verbatim: c.name).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(verbatim: Fmt.percent(mix.share(c) * formula.concentration * 100, decimals: 3))
                                    .font(Theme.figure(.subheadline, weight: .regular))
                            }
                        }
                        if mix.components.count > 12 {
                            Text("and \(mix.components.count - 12) more").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
    }
}
