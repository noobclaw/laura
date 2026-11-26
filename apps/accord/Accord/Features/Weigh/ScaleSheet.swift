import SwiftUI
import SwiftData

enum ScaleModeKind: String, CaseIterable, Identifiable {
    case bottle, concentrate, factor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bottle: return String(localized: "Bottle", bundle: .l10n)
        case .concentrate: return String(localized: "Concentrate", bundle: .l10n)
        case .factor: return String(localized: "Multiply", bundle: .l10n)
        }
    }
}

/// Turns the formula into a weighing sheet for a target size.
struct ScaleSheet: View {
    @Bindable var formula: Formula
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accord.scale.mode") private var modeRaw = ScaleModeKind.bottle.rawValue
    @AppStorage("accord.scale.ml") private var ml: Double = 50
    @AppStorage("accord.scale.grams") private var grams: Double = 10
    @AppStorage("accord.scale.factor") private var factor: Double = 1
    @AppStorage("accord.scale.water") private var waterPercent: Double = 0
    @State private var weighing = false

    private var mode: ScaleModeKind { ScaleModeKind(rawValue: modeRaw) ?? .bottle }

    private var plan: ScalePlan {
        let input = FormulaActions.scaleInput(formula)
        switch mode {
        case .bottle:
            let conc = formula.product == .concentrate ? 1 : formula.concentration
            return ScalePlan.make(input, mode: .bottle(ml: ml, concentration: conc, waterShare: formula.product.isAlcoholic ? waterPercent / 100 : 0))
        case .concentrate: return ScalePlan.make(input, mode: .concentrate(grams: grams))
        case .factor: return ScalePlan.make(input, mode: .factor(factor))
        }
    }

    var body: some View {
        let plan = plan
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $modeRaw) {
                        ForEach(ScaleModeKind.allCases) { m in Text(verbatim: m.title).tag(m.rawValue) }
                    } label: { EmptyView() }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("scale-mode")

                    switch mode {
                    case .bottle:
                        stepperRow(title: formula.product.isAlcoholic || formula.product == .concentrate ? "Bottle size" : "Container size",
                                   value: $ml, step: 5, range: 1...1000, unit: String(localized: "ml", bundle: .l10n))
                        if formula.product != .concentrate {
                            HStack {
                                Text("Fragrance load")
                                Spacer()
                                Text(verbatim: "\(formula.product.name) · \(Fmt.percent(formula.concentration * 100, decimals: 1))")
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            if formula.product.isAlcoholic {
                                stepperRow(title: "Water in the diluent", value: $waterPercent, step: 1, range: 0...30, unit: "%")
                            }
                        }
                    case .concentrate:
                        stepperRow(title: "Concentrate", value: $grams, step: 1, range: 0.1...5000, unit: AmountUnit.grams.short)
                    case .factor:
                        stepperRow(title: "Multiply by", value: $factor, step: 0.5, range: 0.05...200, unit: "×")
                    }
                } footer: {
                    if mode == .bottle {
                        Text("Volumes use typical densities (ethanol 0.79 g/ml, concentrate 0.95 g/ml). Weigh everything by mass.")
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    ForEach(plan.rows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: row.name)
                                if row.dilution < 0.9999 {
                                    Text(verbatim: Fmt.dilution(row.dilution)).font(.caption).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            Spacer()
                            Text(verbatim: Fmt.grams(row.grams)).font(Theme.figure(.body))
                        }
                    }
                    if plan.ethanolGrams > 0 {
                        HStack {
                            Text(verbatim: formula.product.diluentName).foregroundStyle(Theme.amberInk)
                            Spacer()
                            Text(verbatim: Fmt.grams(plan.ethanolGrams)).font(Theme.figure(.body))
                        }
                    }
                    if plan.waterGrams > 0 {
                        HStack {
                            Text("Distilled water").foregroundStyle(Theme.amberInk)
                            Spacer()
                            Text(verbatim: Fmt.grams(plan.waterGrams)).font(Theme.figure(.body))
                        }
                    }
                } header: {
                    HStack {
                        Text("Weighing sheet")
                        Spacer()
                        Text(verbatim: Fmt.grams(plan.totalGrams)).font(Theme.figure(.footnote))
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .textCase(nil)
            .keyboardDoneButton()
            .background(PaperBackground())
            .navigationTitle(Text("Plan a batch"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { weighing = true } label: { Label("Start weighing", systemImage: "scalemass.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(Theme.Space.m)
                    .background(Theme.paper.opacity(0.96))
                    .disabled(plan.totalGrams <= 0)
                    .accessibilityIdentifier("start-weighing")
            }
            .fullScreenCover(isPresented: $weighing) {
                WeighScreen(formula: formula, plan: plan, bottleML: mode == .bottle ? ml : 0) { dismiss() }
            }
        }
    }

    private func stepperRow(title: LocalizedStringKey, value: Binding<Double>, step: Double, range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(text: Binding(get: { Fmt.number(value.wrappedValue, maxDecimals: 2) },
                                    set: { if let v = Fmt.parse($0), v > 0 { value.wrappedValue = min(v, range.upperBound) } })) {
                Text(title)
            }
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(Theme.figure(.body))
            .frame(width: 80)
            Text(verbatim: unit).foregroundStyle(Theme.inkSoft)
            Stepper(value: value, in: range, step: step) { EmptyView() }.labelsHidden()
        }
    }
}

/// One ingredient at a time, big type, phone propped next to the scale.
struct WeighScreen: View {
    let formula: Formula
    let plan: ScalePlan
    let bottleML: Double
    let finished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @AppStorage("accord.weigh.cumulative") private var cumulative = false
    @AppStorage("accord.weigh.deduct") private var deductStock = true

    struct Step: Identifiable {
        let id: Int
        let name: String
        let target: Double
        let dilution: Double
        let materialID: UUID?
    }

    @State private var index = 0
    @State private var actual: [Int: Double] = [:]
    @State private var inputText = ""
    @State private var done = false
    @State private var saved = false
    @State private var proReason: ProReason?
    @FocusState private var inputFocused: Bool

    private var steps: [Step] {
        let lines = formula.sortedLines.filter(\.isResolved)
        var s = plan.rows.map { row in
            Step(id: row.id, name: row.name, target: row.grams, dilution: row.dilution,
                 materialID: lines[safe: row.id]?.material?.id)
        }
        if plan.ethanolGrams > 0 { s.append(Step(id: 10_000, name: formula.product.diluentName, target: plan.ethanolGrams, dilution: 1, materialID: nil)) }
        if plan.waterGrams > 0 { s.append(Step(id: 10_001, name: String(localized: "Distilled water", bundle: .l10n), target: plan.waterGrams, dilution: 1, materialID: nil)) }
        return s
    }

    var body: some View {
        let steps = steps
        ZStack {
            PaperBackground()
            if done { summary(steps) } else if let step = steps[safe: index] { stepView(step, steps: steps) }
        }
        .sheet(item: $proReason) { ProSheet(reason: $0) }
        .keyboardDoneButton()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; prepareInput(steps) }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func stepView(_ step: Step, steps: [Step]) -> some View {
        let before = steps.prefix(index).reduce(0) { $0 + (actual[$1.id] ?? $1.target) }
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44) }
                    .accessibilityLabel(Text("Stop weighing"))
                Spacer()
                Text(verbatim: "\(index + 1) / \(steps.count)").font(Theme.figure(.subheadline)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Toggle(isOn: $cumulative) { Text("Running total") }.toggleStyle(.button).font(.caption)
            }
            ProgressView(value: Double(index), total: Double(max(steps.count, 1))).tint(Theme.amber)

            Spacer()
            Text(verbatim: step.name)
                .font(Theme.display(34, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            if step.dilution < 0.9999 {
                Tag(text: String(localized: "Use your \(Fmt.dilution(step.dilution)) dilution", bundle: .l10n), tint: Theme.amberInk)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Add").font(.subheadline).foregroundStyle(Theme.inkSoft)
                Text(verbatim: Fmt.grams(step.target))
                    .font(.system(size: 64, weight: .semibold, design: .default).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("weigh-target")
                if cumulative {
                    Text("Scale should read \(Fmt.grams(before + step.target))")
                        .font(Theme.figure(.title3, weight: .medium)).foregroundStyle(Theme.amberInk)
                }
            }
            HStack {
                Text("Weighed")
                TextField(text: $inputText) { Text(verbatim: Fmt.number(step.target, maxDecimals: 3)) }
                    .keyboardType(.decimalPad)
                    .font(Theme.figure(.title2))
                    .focused($inputFocused)
                    .multilineTextAlignment(.trailing)
                Text(verbatim: AmountUnit.grams.short).foregroundStyle(Theme.inkSoft)
            }
            .padding(Theme.Space.m)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            if let v = Fmt.parse(inputText), step.target > 0, abs(v - step.target) / step.target > 0.05 {
                Text("\(Fmt.percent(abs(v - step.target) / step.target * 100, decimals: 0)) off target. It will be recorded as weighed.")
                    .font(.footnote).foregroundStyle(Theme.warn)
            }
            Spacer()
            HStack(spacing: Theme.Space.s) {
                Button { back(steps) } label: { Image(systemName: "chevron.left").frame(width: 24) }
                    .buttonStyle(QuietButtonStyle(wide: false))
                    .disabled(index == 0)
                    .accessibilityLabel(Text("Previous"))
                Button { next(steps) } label: {
                    Text(index == steps.count - 1 ? "Finish" as LocalizedStringKey : "Weighed, next")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("weigh-next")
            }
        }
        .padding(Theme.Space.m)
    }

    private func summary(_ steps: [Step]) -> some View {
        let worst = steps.map { s in s.target > 0 ? abs((actual[s.id] ?? s.target) - s.target) / s.target : 0 }.max() ?? 0
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Spacer()
            FlaconView(layers: layerShares)
                .frame(width: 120, height: 160)
                .frame(maxWidth: .infinity)
            Text(saved ? "Batch saved" as LocalizedStringKey : "All weighed")
                .font(Theme.display(34, relativeTo: .largeTitle))
                .frame(maxWidth: .infinity)
            Text(verbatim: String(localized: "\(Fmt.grams(steps.reduce(0) { $0 + (actual[$1.id] ?? $1.target) })) of \(formula.name)", bundle: .l10n))
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
            if worst > 0.05 {
                Text("Largest deviation \(Fmt.percent(worst * 100, decimals: 0)). Keep it in mind when you smell it.")
                    .font(.footnote).foregroundStyle(Theme.warn).frame(maxWidth: .infinity)
            }
            Spacer()
            if !saved {
                Toggle(isOn: $deductStock) { Text("Subtract from stock") }
                    .padding(.horizontal, Theme.Space.s)
                Button { saveBatch(steps) } label: { Label("Save batch and start maturation", systemImage: "hourglass") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("save-batch")
            }
            Button(saved ? "Done" as LocalizedStringKey : "Close without saving") { dismiss(); finished() }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("weigh-close")
        }
        .multilineTextAlignment(.center)
        .padding(Theme.Space.m)
    }

    private var layerShares: [Double] {
        let mix = formula.mix()
        return Tier.Layer.allCases.map { layer in Tier.allCases.filter { $0.layer == layer }.reduce(0) { $0 + mix.grams(in: $1) } }
    }

    private func prepareInput(_ steps: [Step]) {
        inputText = ""
        _ = steps
    }

    private func commit(_ steps: [Step]) {
        guard let step = steps[safe: index] else { return }
        actual[step.id] = Fmt.parse(inputText) ?? step.target
    }

    private func next(_ steps: [Step]) {
        commit(steps)
        Haptics.tap()
        if index >= steps.count - 1 {
            withAnimation(Theme.Motion.settle) { done = true }
            Haptics.success()
        } else {
            index += 1
            inputText = steps[safe: index].flatMap { actual[$0.id] }.map { Fmt.number($0, maxDecimals: 3) } ?? ""
        }
    }

    private func back(_ steps: [Step]) {
        commit(steps)
        index = max(0, index - 1)
        inputText = steps[safe: index].flatMap { actual[$0.id] }.map { Fmt.number($0, maxDecimals: 3) } ?? ""
    }

    private func saveBatch(_ steps: [Step]) {
        guard store.isPro else { proReason = .batches; return }
        let entries = steps.filter { $0.id < 10_000 }.map {
            BatchEntry(name: $0.name, target: $0.target, actual: actual[$0.id] ?? $0.target, dilution: $0.dilution, materialID: $0.materialID)
        }
        let batch = Batch(formula: formula, entries: entries, bottleML: bottleML, concentrateGrams: plan.concentrateGrams,
                          ethanolGrams: actual[10_000] ?? plan.ethanolGrams, waterGrams: actual[10_001] ?? plan.waterGrams)
        batch.reminderDays = [7, 14, 28]
        context.insert(batch)
        if deductStock { Inventory.deduct(entries, in: context) }
        try? context.save()
        Reminders.schedule(batch)
        Haptics.success()
        withAnimation { saved = true }
    }
}

enum Inventory {
    /// Subtracts neat grams from each material that tracks stock.
    @MainActor static func deduct(_ entries: [BatchEntry], in context: ModelContext) {
        let ids = Set(entries.compactMap(\.materialID))
        guard !ids.isEmpty, let materials = try? context.fetch(FetchDescriptor<Material>()) else { return }
        for m in materials where ids.contains(m.id) {
            guard let stock = m.stockGrams else { continue }
            let used = entries.filter { $0.materialID == m.id }.reduce(0) { $0 + $1.actual * $1.dilution }
            m.stockGrams = max(0, stock - used)
        }
    }
}
