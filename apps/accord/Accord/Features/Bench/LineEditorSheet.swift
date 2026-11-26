import SwiftUI
import SwiftData

/// Adds a new line (pick → amount) or edits an existing one.
struct LineEditorSheet: View {
    let formula: Formula
    let line: FormulaLine?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store

    @State private var material: Material?
    @State private var base: Formula?
    @State private var unit: AmountUnit = .grams
    @State private var amountText = ""
    @State private var dilution: Double = 1
    @State private var solvent: Solvent = .ethanol
    @State private var flag: LineFlag = .none
    @State private var note = ""
    @State private var customDilution = false
    @State private var loaded = false
    @State private var loadedText = ""
    @State private var loadedUnit: AmountUnit = .grams
    @State private var proReason: ProReason?
    @FocusState private var amountFocused: Bool

    private var picked: Bool { material != nil || base != nil }

    var body: some View {
        NavigationStack {
            Group {
                if picked { form } else { MaterialPicker(formula: formula) { m, b in pick(m, b) } }
            }
            .background(PaperBackground())
            .navigationTitle(Text(line == nil ? "Add material" as LocalizedStringKey : "Edit line"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if picked {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(grams == nil).accessibilityIdentifier("save-line")
                    }
                }
            }
        }
        .sheet(item: $proReason) { ProSheet(reason: $0) }
        .onAppear(perform: load)
    }

    // MARK: Form

    private var others: Double {
        formula.lines.filter { $0.id != line?.id }.reduce(0) { $0 + max($1.grams, 0) }
    }

    private var dropsPerGram: Double { material?.dropsPerGram ?? 25 }

    /// Parsed input converted to grams.
    private var grams: Double? {
        guard let v = Fmt.parse(amountText), v >= 0 else { return nil }
        switch unit {
        case .grams: return v
        case .drops: return FormulaMath.grams(fromDrops: v, dropsPerGram: dropsPerGram)
        case .percent: return FormulaMath.grams(forPercent: v, othersTotal: others)
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack(spacing: Theme.Space.m) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.color(material?.tier ?? .heart)).frame(width: 4, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: material?.name ?? base?.name ?? "").font(Theme.display(22, relativeTo: .title3))
                        if let m = material {
                            Text(verbatim: "\(m.family.name) · \(m.tier.name)").font(.caption).foregroundStyle(Theme.inkSoft)
                        } else {
                            Text("Base: its own formula is unpacked into this one").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer()
                    if line == nil {
                        Button("Change") { material = nil; base = nil }.font(.subheadline)
                    }
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Picker(selection: Binding(get: { unit }, set: { convert(to: $0) })) {
                    ForEach(AmountUnit.allCases) { u in Text(verbatim: u.short).tag(u) }
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("unit-picker")

                HStack(alignment: .firstTextBaseline) {
                    TextField(text: $amountText) { Text("Amount") }
                        .keyboardType(.decimalPad)
                        .font(Theme.figure(.largeTitle))
                        .focused($amountFocused)
                        .accessibilityIdentifier("amount-field")
                    Text(verbatim: unit.short).font(.title3).foregroundStyle(Theme.inkSoft)
                }
                if let g = grams {
                    Text(verbatim: equivalents(g)).font(Theme.figure(.footnote, weight: .regular)).foregroundStyle(Theme.inkSoft)
                } else if !amountText.isEmpty {
                    Text(unit == .percent ? "A single line can’t be 100 % while others are in the formula." as LocalizedStringKey : "Enter a number.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                }
            } header: { Text("Amount") }
            .listRowBackground(Theme.card)

            Section {
                Picker(selection: Binding(get: { customDilution ? -1 : dilution }, set: { v in
                    if v < 0 { customDilution = true } else { customDilution = false; dilution = v }
                })) {
                    Text("Neat").tag(1.0)
                    Text(verbatim: Fmt.percent(50, decimals: 0)).tag(0.5)
                    Text(verbatim: Fmt.percent(10, decimals: 0)).tag(0.1)
                    Text(verbatim: Fmt.percent(1, decimals: 0)).tag(0.01)
                    Text(verbatim: Fmt.percent(0.1, decimals: 1)).tag(0.001)
                    Text("Other").tag(-1.0)
                } label: { Text("Strength") }
                if customDilution {
                    HStack {
                        Text("Strength %")
                        Spacer()
                        TextField(text: Binding(get: { Fmt.number(dilution * 100, maxDecimals: 3) },
                                                set: { if let v = Fmt.parse($0), v > 0, v <= 100 { dilution = v / 100 } })) { Text(verbatim: "10") }
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                }
                if dilution < 0.9999 {
                    Picker(selection: $solvent) {
                        ForEach(Solvent.allCases.filter { $0 != .none }) { s in Text(verbatim: s.name).tag(s) }
                    } label: { Text("Diluted in") }
                }
            } header: { Text("Dilution") } footer: {
                Text("Weigh the solution; Accord counts only the active material in the analysis.")
            }
            .listRowBackground(Theme.card)

            Section {
                Picker(selection: $flag) {
                    ForEach(LineFlag.allCases) { f in Label(f.name, systemImage: f.symbol).tag(f) }
                } label: { Text("After smelling") }
                TextField(text: $note, axis: .vertical) { Text("Note") }
                    .lineLimit(1...4)
            } header: { Text("Trial notes") }
            .listRowBackground(Theme.card)

            if let line {
                Section {
                    Button(role: .destructive) {
                        dismiss()
                        let ctx = context, f = formula
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            ctx.delete(line)
                            f.touch()
                            try? ctx.save()
                        }
                    } label: { Text("Remove from formula") }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .keyboardDoneButton()
    }

    private func equivalents(_ g: Double) -> String {
        let total = others + g
        let pct = total > 0 ? g / total * 100 : 0
        var parts = [Fmt.grams(g), Fmt.drops(FormulaMath.drops(fromGrams: g, dropsPerGram: dropsPerGram)), Fmt.percent(pct)]
        if dilution < 0.9999 {
            parts.append(String(localized: "\(Fmt.grams(g * dilution)) active", bundle: .l10n))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let line {
            material = line.material
            base = line.base
            unit = line.unit
            dilution = line.dilution
            solvent = line.solvent
            flag = line.flag
            note = line.note
            amountText = display(line.grams, in: unit)
            loadedText = amountText
            loadedUnit = unit
            customDilution = ![1, 0.5, 0.1, 0.01, 0.001].contains { abs($0 - line.dilution) < 1e-9 }
        } else {
            unit = formula.lines.max { $0.order < $1.order }?.unit ?? .grams
        }
    }

    private func display(_ g: Double, in unit: AmountUnit) -> String {
        switch unit {
        case .grams: return Fmt.number(g, maxDecimals: 4)
        case .drops: return Fmt.number(FormulaMath.drops(fromGrams: g, dropsPerGram: dropsPerGram).rounded(), maxDecimals: 0)
        case .percent:
            let total = others + g
            return Fmt.number(total > 0 ? g / total * 100 : 0, maxDecimals: 3)
        }
    }

    private func convert(to new: AmountUnit) {
        if let line, amountText == loadedText, unit == loadedUnit {
            amountText = display(line.grams, in: new)
            loadedText = amountText
            loadedUnit = new
        } else if let g = grams {
            amountText = display(g, in: new)
        }
        unit = new
    }

    private func pick(_ m: Material?, _ b: Formula?) {
        if b != nil && !store.isPro {
            proReason = .bases
            return
        }
        material = m
        base = b
        if let m {
            dilution = m.defaultDilution
            solvent = m.defaultSolvent
            customDilution = ![1, 0.5, 0.1, 0.01, 0.001].contains { abs($0 - m.defaultDilution) < 1e-9 }
        } else {
            dilution = 1
        }
        Haptics.select()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { amountFocused = true }
    }

    private func save() {
        guard var g = grams else { return }
        if let line {
            // Re-deriving grams from a rounded display would drift; keep the stored value if the amount wasn't touched.
            if amountText == loadedText && unit == loadedUnit { g = line.grams }
            line.grams = g
            line.unit = unit
            line.dilution = dilution
            line.solvent = solvent
            line.flag = flag
            line.note = note
            formula.touch()
            try? context.save()
        } else {
            let l = FormulaActions.addLine(to: formula, material: material, base: base, grams: g,
                                           dilution: dilution, solvent: solvent, unit: unit, in: context)
            l.flag = flag
            l.note = note
        }
        Haptics.success()
        dismiss()
    }
}

/// Search the library (and, with Pro, other formulas as bases); create a material on the fly.
struct MaterialPicker: View {
    let formula: Formula
    let onPick: (Material?, Formula?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @Query(sort: \Material.name) private var materials: [Material]
    @Query(sort: \Formula.updatedAt, order: .reverse) private var formulas: [Formula]
    @State private var query = ""
    @State private var family: Family?

    private var filtered: [Material] {
        materials.filter { m in
            (family == nil || m.family == family) &&
            (query.isEmpty || m.name.localizedCaseInsensitiveContains(query) || m.odor.localizedCaseInsensitiveContains(query) || m.cas.contains(query))
        }
    }

    private var bases: [Formula] {
        formulas.filter { f in
            f.id != formula.id && !f.contains(base: formula) && !f.lines.isEmpty &&
            (query.isEmpty || f.name.localizedCaseInsensitiveContains(query))
        }
    }

    private var recent: [Material] {
        var seen = Set<UUID>()
        return formulas.prefix(6).flatMap { $0.sortedLines.compactMap(\.material) }
            .filter { m in seen.insert(m.id).inserted && !formula.lines.contains { $0.material?.id == m.id } }
            .prefix(8).map { $0 }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FamilyChip(title: String(localized: "All", bundle: .l10n), color: Theme.ink, selected: family == nil) { family = nil }
                        ForEach(Family.allCases) { f in
                            FamilyChip(title: f.name, color: Theme.color(f), selected: family == f) { family = family == f ? nil : f }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: Theme.Space.m, bottom: 4, trailing: Theme.Space.m))

            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !materials.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                Section {
                    Button {
                        let m = Material(name: trimmed, family: family ?? .floral, tier: .heart)
                        context.insert(m)
                        try? context.save()
                        onPick(m, nil)
                    } label: {
                        Label(String(localized: "Add “\(trimmed)” to materials", bundle: .l10n), systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("create-material")
                }
                .listRowBackground(Theme.card)
            }

            if query.isEmpty && family == nil && !recent.isEmpty {
                Section { ForEach(recent) { m in row(m) } } header: { Text("Recently used") }
                    .listRowBackground(Theme.card)
            }

            if !bases.isEmpty && family == nil {
                Section {
                    ForEach(bases) { b in
                        Button { onPick(nil, b) } label: {
                            HStack {
                                Image(systemName: "flask").foregroundStyle(Theme.amberInk)
                                Text(verbatim: b.name).foregroundStyle(Theme.ink)
                                Spacer()
                                if !store.isPro { Tag(text: "Pro", tint: Theme.amberInk) }
                            }
                        }
                    }
                } header: { Text("Your formulas as bases") }
                .listRowBackground(Theme.card)
            }

            Section {
                ForEach(filtered) { m in row(m) }
            } header: { Text("Library") }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search or type a new name"))
    }

    private func row(_ m: Material) -> some View {
        Button { onPick(m, nil) } label: {
            HStack(spacing: Theme.Space.s) {
                Dot(color: Theme.color(m.family), size: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: m.name).foregroundStyle(Theme.ink)
                    if !m.odor.isEmpty { Text(verbatim: m.odor).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                }
                Spacer()
                Text(verbatim: m.tier.name).font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityIdentifier("pick-\(m.name)")
    }
}

struct FamilyChip: View {
    let title: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.select(); action() }) {
            HStack(spacing: 5) {
                Dot(color: color)
                Text(verbatim: title).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(selected ? Theme.onAmber : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(selected ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Theme.card),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hair))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
