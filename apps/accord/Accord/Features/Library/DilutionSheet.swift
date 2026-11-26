import SwiftUI
import SwiftData

/// "Make 10 g of a 10 % dilution": grams of material and solvent, drops, and an optional update of the material.
struct DilutionSheet: View {
    var material: Material?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @Query(sort: \Material.name) private var materials: [Material]

    enum Mode: String, CaseIterable, Identifiable {
        case make, have
        var id: String { rawValue }
        var title: String {
            switch self {
            case .make: return String(localized: "I want to make", bundle: .l10n)
            case .have: return String(localized: "I have", bundle: .l10n)
            }
        }
    }

    @State private var picked: Material?
    @State private var mode: Mode = .make
    @State private var amount: Double? = 10
    @State private var targetPercent: Double? = 10
    @State private var sourcePercent: Double? = 100
    @State private var solvent: Solvent = .ethanol
    @State private var subtract = false
    @State private var saved = false

    private var m: Material? { picked ?? material }

    private var plan: DilutionPlan? {
        guard let a = amount, let t = targetPercent, let s = sourcePercent else { return nil }
        switch mode {
        case .make: return DilutionPlan.make(total: a, target: t / 100, source: s / 100)
        case .have: return DilutionPlan.fromMaterial(a, target: t / 100, source: s / 100)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    materialHeader
                    inputs
                    result
                }
                .screenPadding()
                .padding(.bottom, Theme.Space.xl)
            }
            .background(PaperBackground())
            .navigationTitle(Text("Dilution calculator"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .keyboardDoneButton()
            .onAppear {
                if let m = m {
                    solvent = m.defaultSolvent == .none ? .ethanol : m.defaultSolvent
                    if m.defaultDilution < 0.9999 { targetPercent = m.defaultDilution * 100 }
                }
            }
        }
    }

    private var materialHeader: some View {
        Menu {
            ForEach(materials) { mat in
                Button(mat.name) { picked = mat; saved = false }
            }
        } label: {
            HStack(spacing: Theme.Space.m) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.color(m?.tier ?? .heart)).frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: m?.name ?? String(localized: "Choose a material", bundle: .l10n))
                        .font(Theme.display(24, relativeTo: .title2)).foregroundStyle(Theme.ink)
                    if let m {
                        Text(verbatim: "\(m.family.name) · \(String(localized: "kept at", bundle: .l10n)) \(Fmt.dilution(m.defaultDilution))")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.inkSoft)
            }
            .padding(Theme.Space.m)
            .background(Theme.kraft.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .accessibilityIdentifier("dilution-material")
    }

    private var inputs: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Picker(selection: $mode) {
                    ForEach(Mode.allCases) { Text(verbatim: $0.title).tag($0) }
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                field(mode == .make ? "Total to make" as LocalizedStringKey : "Material you have", value: $amount, suffix: AmountUnit.grams.short)
                field("Target strength", value: $targetPercent, suffix: "%")
                field("Starting from", value: $sourcePercent, suffix: "%")
                HStack(spacing: 6) {
                    ForEach([100.0, 50, 10], id: \.self) { v in
                        Button { sourcePercent = v } label: {
                            Text(verbatim: v == 100 ? String(localized: "Neat", bundle: .l10n) : Fmt.percent(v, decimals: 0))
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(sourcePercent == v ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Theme.sunken),
                                            in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                                .foregroundStyle(sourcePercent == v ? Theme.onAmber : Theme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                Picker(selection: $solvent) {
                    ForEach(Solvent.allCases.filter { $0 != .none }) { Text(verbatim: $0.name).tag($0) }
                } label: { Text("Solvent") }
            }
        }
    }

    private func field(_ title: LocalizedStringKey, value: Binding<Double?>, suffix: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.ink)
            Spacer()
            DecimalField(title: "–", value: value)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text(verbatim: suffix).foregroundStyle(Theme.inkSoft).frame(width: 18, alignment: .leading)
        }
    }

    @ViewBuilder private var result: some View {
        if let plan {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                // Proportion bar: material vs solvent.
                GeometryReader { g in
                    let share = plan.total > 0 ? plan.material / plan.total : 0
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.color(m?.tier ?? .heart))
                            .frame(width: max(4, g.size.width * share))
                        RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.sunken)
                    }
                }
                .frame(height: 14)
                .accessibilityHidden(true)

                step(number: 1, title: sourcePercent ?? 100 >= 99.999 ? String(localized: "Weigh the material", bundle: .l10n)
                                                                       : String(localized: "Weigh your \(Fmt.percent(sourcePercent ?? 100, decimals: 2)) dilution", bundle: .l10n),
                     grams: plan.material,
                     note: m.map { Fmt.drops(FormulaMath.drops(fromGrams: plan.material, dropsPerGram: $0.dropsPerGram)) })
                step(number: 2, title: String(localized: "Add \(solvent.name)", bundle: .l10n), grams: plan.solvent, note: nil)
                HStack {
                    Text("You get")
                    Spacer()
                    Text(verbatim: "\(Fmt.grams(plan.total)) · \(Fmt.percent(targetPercent ?? 0, decimals: 2))")
                        .font(Theme.figure(.headline))
                }
                .foregroundStyle(Theme.amberInk)

                if let m {
                    if store.isPro, m.stockGrams != nil {
                        Toggle(isOn: $subtract) { Text("Subtract from stock") }
                    }
                    Button {
                        m.defaultDilution = (targetPercent ?? 100) / 100
                        m.defaultSolvent = solvent
                        if subtract, let stock = m.stockGrams {
                            m.stockGrams = max(0, stock - plan.material * (sourcePercent ?? 100) / 100)
                        }
                        try? context.save()
                        Haptics.success()
                        saved = true
                    } label: {
                        Label(saved ? "Saved" as LocalizedStringKey : "Keep this material at this strength",
                              systemImage: saved ? "checkmark" : "tray.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saved)
                    .accessibilityIdentifier("save-dilution")
                }
            }
            .padding(Theme.Space.m)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hair))
        } else {
            Text("The target must be weaker than what you start from, and every number above zero.")
                .font(.footnote).foregroundStyle(Theme.danger)
        }
    }

    private func step(number: Int, title: String, grams: Double, note: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(verbatim: "\(number)")
                .font(Theme.displayBold(20))
                .foregroundStyle(Theme.amberInk)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).foregroundStyle(Theme.ink)
                if let note { Text(verbatim: "≈ \(note)").font(.caption).foregroundStyle(Theme.inkSoft) }
            }
            Spacer()
            Text(verbatim: Fmt.grams(grams)).font(Theme.figure(.title2)).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}
