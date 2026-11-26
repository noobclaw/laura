import SwiftUI
import SwiftData

struct BenchScreen: View {
    @Environment(AppState.self) private var state
    @Environment(ProStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \Formula.updatedAt, order: .reverse) private var formulas: [Formula]
    @State private var showNew = false

    private var formula: Formula? {
        formulas.first { $0.id == state.currentFormulaID } ?? formulas.first
    }

    var body: some View {
        Group {
            if let f = formula {
                BenchContent(formula: f).id(f.id)
            } else {
                ScrollView {
                    ActionEmpty(title: "Your bench is clear",
                                message: "Start a formula and add materials by gram, drop or percent. Accord does the arithmetic.",
                                action: "Start a formula") {
                        if FormulaActions.ensureRoom(context, store: store, state: state) { showNew = true }
                    }
                    .padding(.top, 80)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewFormulaSheet() }
    }
}

private enum BenchSection: String, CaseIterable, Identifiable {
    case formula, analysis, product
    var id: String { rawValue }
    var title: String {
        switch self {
        case .formula: return String(localized: "Formula", bundle: .l10n)
        case .analysis: return String(localized: "Analysis", bundle: .l10n)
        case .product: return String(localized: "Product", bundle: .l10n)
        }
    }
}

struct BenchContent: View {
    @Bindable var formula: Formula
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var state
    @Environment(ProStore.self) private var store

    @State private var section: BenchSection = .formula
    @State private var hour: Double = 2
    @State private var editing: FormulaLine?
    @State private var adding = false
    @State private var scaling = false
    @State private var renaming = false
    @State private var editingNotes = false
    @State private var comparing = false
    @State private var exporting = false
    @State private var confirmDelete = false
    @State private var newName = ""

    var body: some View {
        let mix = formula.mix()
        let lines = formula.sortedLines
        let total = formula.totalGrams
        List {
            header(mix: mix, lines: lines)
                .plainRow(top: Theme.Space.m)

            timelineCard(mix: mix)
                .plainRow()

            SectionPicker(selection: $section)
                .plainRow(top: Theme.Space.m, bottom: Theme.Space.s)

            switch section {
            case .formula:
                if lines.isEmpty {
                    ActionEmpty(title: "No materials yet",
                                message: "Add your first material. Type grams, drops or a percentage, whichever you weigh in.",
                                action: "Add material") { adding = true }
                        .plainRow()
                } else {
                    ForEach(lines) { line in
                        LineRow(line: line, total: total) {
                            Haptics.select()
                            line.unit = line.unit.next
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = line }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(line) } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button { cycleFlag(line) } label: { Label("Flag", systemImage: "flag") }.tint(Theme.amber)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Space.m, bottom: 0, trailing: Theme.Space.m))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.hair)
                        .accessibilityIdentifier("line-\(line.displayName)")
                    }
                    .onMove { from, to in FormulaActions.move(formula, from: from, to: to) }

                    totals(mix: mix).plainRow(top: Theme.Space.s)
                }
            case .analysis:
                AnalysisPanel(formula: formula, mix: mix).plainRow()
            case .product:
                ProductPanel(formula: formula, mix: mix) { scaling = true }.plainRow()
            }

            Color.clear.frame(height: 80).plainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(lines: lines) }
        .sheet(item: $editing) { line in LineEditorSheet(formula: formula, line: line) }
        .sheet(isPresented: $adding) { LineEditorSheet(formula: formula, line: nil) }
        .sheet(isPresented: $scaling) { ScaleSheet(formula: formula) }
        .sheet(isPresented: $editingNotes) { NotesSheet(formula: formula) }
        .sheet(isPresented: $comparing) { ComparePickerSheet(base: formula) }
        .sheet(isPresented: $exporting) { ExportSheet(formula: formula) }
        .alert(Text("Rename formula"), isPresented: $renaming) {
            TextField(text: $newName) { Text("Name") }
            Button("Save") {
                let t = newName.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { formula.name = t; formula.touch() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(Text("Delete “\(formula.name)”?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete formula and its lines", role: .destructive) { deleteFormula() }
        } message: {
            if formula.usedAsBaseIn.isEmpty {
                Text("Batches you already made keep their records.")
            } else {
                Text("\(Set(formula.usedAsBaseIn.compactMap { $0.formula?.id }).count) formulas use it as a base; those lines will show “Missing material”.")
            }
        }
    }

    // MARK: Header

    private func header(mix: MixResult, lines: [FormulaLine]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Tag(text: formula.product.name, tint: Theme.amberInk)
                if formula.version > 1 { Tag(text: String(localized: "v\(formula.version)", bundle: .l10n)) }
                if !formula.category.isEmpty { Tag(text: formula.category) }
                Spacer()
                formulaMenu
            }
            Text(verbatim: formula.name)
                .font(Theme.display(36, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .onTapGesture { newName = formula.name; renaming = true }
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("bench-title")
            Text(verbatim: String(localized: "\(Fmt.grams(formula.totalGrams)) · \(lines.count) ingredients", bundle: .l10n))
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var formulaMenu: some View {
        Menu {
            Button { newName = formula.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
            Button { editingNotes = true } label: { Label("Notes", systemImage: "note.text") }
            Button { duplicateAsVersion() } label: { Label("Save as new version", systemImage: "plus.square.on.square") }
            Button {
                if store.isPro { comparing = true } else { state.proReason = .compare }
            } label: { Label("Compare with…", systemImage: "arrow.left.arrow.right") }
            Button {
                if store.isPro { exporting = true } else { state.proReason = .export }
            } label: { Label("Export…", systemImage: "square.and.arrow.up") }
            Menu {
                Button("Heaviest first") { FormulaActions.sort(formula, by: .heaviest) }
                Button("Top to base") { FormulaActions.sort(formula, by: .pyramid) }
                Button("By name") { FormulaActions.sort(formula, by: .name) }
            } label: { Label("Sort lines", systemImage: "arrow.up.arrow.down") }
            Menu {
                ForEach(AmountUnit.allCases) { u in
                    Button(u.short) { for l in formula.lines { l.unit = u } }
                }
            } label: { Label("Show amounts as", systemImage: "scalemass") }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete formula", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Formula actions"))
        .accessibilityIdentifier("formula-menu")
    }

    // MARK: Timeline

    private func timelineCard(mix: MixResult) -> some View {
        let dominant = EvaporationCurve.dominant(mix, at: hour)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: hour < 0.05 ? String(localized: "On the first spray", bundle: .l10n)
                                           : String(localized: "After \(Fmt.hours(hour))", bundle: .l10n))
                    .font(Theme.display(20, italic: true, relativeTo: .title3))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if mix.activeGrams > 0 {
                    Text(verbatim: String(localized: "lasts ≈ \(Fmt.hours(EvaporationCurve(mix).longevityHours))", bundle: .l10n))
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            EvaporationChart(mix: mix, hour: $hour)
                .frame(height: 132)
            if dominant.isEmpty {
                Text("Add materials to see how the scent unfolds.").font(.footnote).foregroundStyle(Theme.inkSoft)
            } else {
                HStack(spacing: 6) {
                    ForEach(dominant, id: \.0.key) { comp, share in
                        HStack(spacing: 4) {
                            Dot(color: Theme.color(comp.tier))
                            Text(verbatim: comp.name).lineLimit(1)
                            Text(verbatim: Fmt.percent(share * 100, decimals: 0)).foregroundStyle(Theme.inkSoft)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Theme.Space.m) {
                ForEach(Tier.Layer.allCases, id: \.rawValue) { layer in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.color(layer)).frame(width: 10, height: 10)
                        Text(verbatim: layerName(layer)).font(.caption2).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer()
                Text("Sketch, not a measurement").font(.caption2).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(Theme.Space.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hair))
    }

    private func layerName(_ l: Tier.Layer) -> String {
        switch l {
        case .top: return Tier.top.name
        case .heart: return Tier.heart.name
        case .base: return Tier.base.name
        }
    }

    // MARK: Totals & actions

    private func totals(mix: MixResult) -> some View {
        VStack(spacing: 2) {
            InfoRow(label: "Total on the scale", value: Fmt.grams(mix.totalGrams))
            InfoRow(label: "Neat materials", value: mix.totalGrams > 0 ? Fmt.percent(mix.activeGrams / mix.totalGrams * 100, decimals: 1) : "–")
            if mix.solventGrams > 0 {
                InfoRow(label: "Solvent from dilutions",
                        value: mix.solvents.sorted { $0.value > $1.value }.map { "\($0.key.name) \(Fmt.grams($0.value))" }.joined(separator: ", "))
            }
        }
        .font(.subheadline)
    }

    private func actionBar(lines: [FormulaLine]) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button { adding = true } label: { Label("Add material", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("add-material")
            Button { scaling = true } label: { Label("Weigh", systemImage: "scalemass") }
                .buttonStyle(QuietButtonStyle(wide: false))
                .disabled(lines.isEmpty)
                .accessibilityIdentifier("weigh")
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.paper.opacity(0.96))
    }

    // MARK: Mutations

    private func delete(_ line: FormulaLine) {
        context.delete(line)
        formula.touch()
        try? context.save()
    }

    private func cycleFlag(_ line: FormulaLine) {
        let all = LineFlag.allCases
        let i = all.firstIndex(of: line.flag) ?? 0
        line.flag = all[(i + 1) % all.count]
        Haptics.tap()
    }

    private func duplicateAsVersion() {
        guard FormulaActions.ensureRoom(context, store: store, state: state) else { return }
        let copy = FormulaActions.duplicate(formula, asVersion: true, in: context)
        Haptics.success()
        state.open(copy)
    }

    private func deleteFormula() {
        // Move the bench to another formula first so this view stops rendering the one being deleted.
        let doomed = formula
        let next = (try? context.fetch(FetchDescriptor<Formula>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])))?
            .first { $0.id != doomed.id }
        state.currentFormulaID = next?.id
        let ctx = context
        DispatchQueue.main.async {
            ctx.delete(doomed)
            try? ctx.save()
        }
    }
}

// MARK: - Row

struct LineRow: View {
    let line: FormulaLine
    let total: Double
    let cycleUnit: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.color(line.tier))
                .frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: line.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if line.base != nil {
                        Tag(text: String(localized: "tag.base", defaultValue: "Base", bundle: .l10n), tint: Theme.amberInk)
                    } else if let m = line.material {
                        Dot(color: Theme.color(m.family))
                        Text(verbatim: m.family.name).font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    if line.dilution < 0.9999 {
                        Tag(text: String(localized: "\(Fmt.percent(line.dilution * 100, decimals: 2)) in \(line.solvent.name)", bundle: .l10n))
                    }
                    if line.flag != .none {
                        Image(systemName: line.flag.symbol)
                            .font(.caption)
                            .foregroundStyle(line.flag == .keep ? Theme.ok : Theme.warn)
                            .accessibilityLabel(Text(verbatim: line.flag.name))
                    }
                }
            }
            Spacer(minLength: Theme.Space.s)
            Button(action: cycleUnit) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: amountText)
                        .font(Theme.figure(.title3))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: secondaryText)
                        .font(Theme.figure(.caption, weight: .regular))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(minWidth: 72, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: amountText))
            .accessibilityHint(Text("Switches between grams, drops and percent"))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var share: Double { total > 0 ? line.grams / total * 100 : 0 }

    private var amountText: String {
        switch line.unit {
        case .grams: return Fmt.grams(line.grams)
        case .drops: return Fmt.drops(FormulaMath.drops(fromGrams: line.grams, dropsPerGram: line.dropsPerGram))
        case .percent: return Fmt.percent(share)
        }
    }

    private var secondaryText: String {
        switch line.unit {
        case .grams, .drops: return Fmt.percent(share)
        case .percent: return Fmt.grams(line.grams)
        }
    }
}

// MARK: - Section picker

private struct SectionPicker: View {
    @Binding var selection: BenchSection
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BenchSection.allCases) { s in
                Button {
                    Haptics.select()
                    withAnimation(Theme.Motion.settle) { selection = s }
                } label: {
                    Text(verbatim: s.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == s ? Theme.ink : Theme.inkSoft)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selection == s {
                                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                    .fill(Theme.card)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hair))
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == s ? .isSelected : [])
                .accessibilityIdentifier("section-\(s.rawValue)")
            }
        }
        .padding(3)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.row + 3, style: .continuous))
    }
}

extension View {
    /// A List row with no chrome, used for headers and cards inside the bench list.
    func plainRow(top: CGFloat = Theme.Space.s, bottom: CGFloat = Theme.Space.s) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: Theme.Space.m, bottom: bottom, trailing: Theme.Space.m))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Notes

struct NotesSheet: View {
    @Bindable var formula: Formula
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $formula.notes)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.m)
                .background(PaperBackground())
                .navigationTitle(Text("Notes"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { formula.touch(); dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
