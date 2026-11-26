import Foundation
import SwiftData

@MainActor
enum FormulaActions {
    static func userFormulaCount(_ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<Formula>(predicate: #Predicate { !$0.isSample }))) ?? 0
    }

    /// True if the user may add another formula; otherwise opens the paywall.
    static func ensureRoom(_ context: ModelContext, store: ProStore, state: AppState) -> Bool {
        if store.canCreateFormula(userFormulaCount: userFormulaCount(context)) { return true }
        state.proReason = .formulaLimit
        return false
    }

    @discardableResult
    static func create(name: String, product: ProductType, category: String, in context: ModelContext) -> Formula {
        let f = Formula(name: name, product: product, category: category)
        context.insert(f)
        try? context.save()
        return f
    }

    /// Copies a formula as the next version; the copy keeps the lineage via `parentID`.
    @discardableResult
    static func duplicate(_ source: Formula, asVersion: Bool, in context: ModelContext) -> Formula {
        let copy = Formula(name: asVersion ? source.name : String(localized: "\(source.name) copy", bundle: .l10n),
                           product: source.product, category: source.category)
        copy.concentration = source.concentration
        copy.notes = source.notes
        copy.version = asVersion ? nextVersion(of: source, in: context) : 1
        copy.parentID = asVersion ? source.id : nil
        context.insert(copy)
        for line in source.sortedLines {
            let l = FormulaLine(order: line.order, grams: line.grams, material: line.material, base: line.base,
                                dilution: line.dilution, solvent: line.solvent)
            l.unit = line.unit
            l.flag = line.flag
            l.note = line.note
            context.insert(l)
            l.formula = copy
        }
        try? context.save()
        return copy
    }

    /// Highest version among formulas of the same name, plus one.
    static func nextVersion(of f: Formula, in context: ModelContext) -> Int {
        let name = f.name
        let same = (try? context.fetch(FetchDescriptor<Formula>(predicate: #Predicate { $0.name == name }))) ?? []
        return (same.map(\.version).max() ?? f.version) + 1
    }

    static func addLine(to f: Formula, material: Material? = nil, base: Formula? = nil, grams: Double,
                        dilution: Double, solvent: Solvent, unit: AmountUnit, in context: ModelContext) -> FormulaLine {
        let order = (f.lines.map(\.order).max() ?? -1) + 1
        let line = FormulaLine(order: order, grams: grams, material: material, base: base, dilution: dilution, solvent: solvent)
        line.unit = unit
        context.insert(line)
        line.formula = f
        f.touch()
        try? context.save()
        return line
    }

    enum SortMode { case heaviest, pyramid, name }

    static func sort(_ f: Formula, by mode: SortMode) {
        let lines = f.sortedLines
        let sorted: [FormulaLine]
        switch mode {
        case .heaviest: sorted = lines.sorted { $0.grams > $1.grams }
        case .pyramid: sorted = lines.sorted { ($0.tier.rawValue, -$0.grams) < ($1.tier.rawValue, -$1.grams) }
        case .name: sorted = lines.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        for (i, l) in sorted.enumerated() { l.order = i }
        f.touch()
    }

    static func move(_ f: Formula, from: IndexSet, to: Int) {
        var lines = f.sortedLines
        lines.move(fromOffsets: from, toOffset: to)
        for (i, l) in lines.enumerated() { l.order = i }
        f.touch()
    }

    /// Engine lines for scaling, in formula order.
    static func scaleInput(_ f: Formula) -> [(name: String, grams: Double, dilution: Double)] {
        f.sortedLines.filter(\.isResolved).map { ($0.displayName, $0.grams, $0.dilution) }
    }
}
