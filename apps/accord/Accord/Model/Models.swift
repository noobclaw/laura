import Foundation
import SwiftData

@Model
final class Material {
    var id: UUID = UUID()
    var name: String = ""
    var familyRaw: String = Family.floral.rawValue
    var tierRaw: Int = Tier.heart.rawValue
    var odor: String = ""
    var supplier: String = ""
    var cas: String = ""
    var costPerGram: Double?
    var stockGrams: Double?
    var lowStockGrams: Double?
    var purchaseDate: Date?
    var shelfLifeMonths: Int?
    var dropsPerGram: Double = 25
    /// Maximum in the finished product, percent (user's own figure from their supplier / IFRA certificate).
    var limitPercent: Double?
    /// Dilution the user keeps this material at, 0…1 (1 = neat).
    var defaultDilution: Double = 1
    var defaultSolventRaw: String = Solvent.ethanol.rawValue
    var notes: String = ""
    var isNatural: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \FormulaLine.material)
    var lines: [FormulaLine] = []

    init(name: String, family: Family, tier: Tier, odor: String = "", isNatural: Bool = false,
         dropsPerGram: Double = 25, defaultDilution: Double = 1) {
        self.id = UUID()
        self.name = name
        self.familyRaw = family.rawValue
        self.tierRaw = tier.rawValue
        self.odor = odor
        self.isNatural = isNatural
        self.dropsPerGram = dropsPerGram
        self.defaultDilution = defaultDilution
        self.createdAt = Date()
    }

    var family: Family {
        get { Family(rawValue: familyRaw) ?? .floral }
        set { familyRaw = newValue.rawValue }
    }
    var tier: Tier {
        get { Tier(rawValue: tierRaw) ?? .heart }
        set { tierRaw = newValue.rawValue }
    }
    var defaultSolvent: Solvent {
        get { Solvent(rawValue: defaultSolventRaw) ?? .ethanol }
        set { defaultSolventRaw = newValue.rawValue }
    }

    var isLowStock: Bool {
        guard let stock = stockGrams, let low = lowStockGrams else { return false }
        return stock <= low
    }

    var expiryDate: Date? {
        guard let purchaseDate, let months = shelfLifeMonths, months > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: purchaseDate)
    }

    var isExpired: Bool { (expiryDate ?? .distantFuture) < Date() }

    /// Formulas that use this material directly, newest first.
    var formulas: [Formula] {
        var seen = Set<UUID>()
        return lines.compactMap(\.formula).filter { seen.insert($0.id).inserted }.sorted { $0.updatedAt > $1.updatedAt }
    }
}

@Model
final class Formula {
    var id: UUID = UUID()
    var name: String = ""
    var category: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var version: Int = 1
    /// Formula this one was copied from, for version history.
    var parentID: UUID?
    var productRaw: String = ProductType.edp.rawValue
    var concentration: Double = ProductType.edp.defaultConcentration
    /// Bundled examples do not count against the free limit.
    var isSample: Bool = false
    var isFavorite: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \FormulaLine.formula)
    var lines: [FormulaLine] = []

    /// Lines in other formulas that use this one as a base.
    @Relationship(deleteRule: .nullify, inverse: \FormulaLine.base)
    var usedAsBaseIn: [FormulaLine] = []

    init(name: String, product: ProductType = .edp, category: String = "", isSample: Bool = false) {
        self.id = UUID()
        self.name = name
        self.productRaw = product.rawValue
        self.concentration = product.defaultConcentration
        self.category = category
        self.isSample = isSample
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var product: ProductType {
        get { ProductType(rawValue: productRaw) ?? .edp }
        set { productRaw = newValue.rawValue }
    }

    var sortedLines: [FormulaLine] { lines.sorted { $0.order < $1.order } }

    var totalGrams: Double { lines.reduce(0) { $0 + max($1.grams, 0) } }

    func touch() { updatedAt = Date() }

    /// Engine input. `visited` guards against a base that (indirectly) contains itself.
    func mixLines(visited: Set<UUID> = []) -> [MixLine] {
        let seen = visited.union([id])
        return sortedLines.compactMap { $0.mixLine(visited: seen) }
    }

    func mix() -> MixResult { FormulaMath.mix(mixLines()) }

    /// True if `other` appears anywhere inside this formula's bases (or is this formula).
    func contains(base other: Formula, depth: Int = 0) -> Bool {
        if other.id == id { return true }
        guard depth < FormulaMath.maxDepth else { return true }
        return lines.contains { line in line.base.map { $0.contains(base: other, depth: depth + 1) } ?? false }
    }

    var usesBases: Bool { lines.contains { $0.base != nil } }
}

@Model
final class FormulaLine {
    var id: UUID = UUID()
    var order: Int = 0
    /// What goes on the scale, in grams (solution if diluted).
    var grams: Double = 0
    var unitRaw: String = AmountUnit.grams.rawValue
    var dilution: Double = 1
    var solventRaw: String = Solvent.ethanol.rawValue
    var flagRaw: String = LineFlag.none.rawValue
    var note: String = ""

    var formula: Formula?
    var material: Material?
    var base: Formula?

    init(order: Int, grams: Double, material: Material? = nil, base: Formula? = nil,
         dilution: Double = 1, solvent: Solvent = .ethanol) {
        self.id = UUID()
        self.order = order
        self.grams = grams
        self.material = material
        self.base = base
        self.dilution = dilution
        self.solventRaw = solvent.rawValue
    }

    var unit: AmountUnit {
        get { AmountUnit(rawValue: unitRaw) ?? .grams }
        set { unitRaw = newValue.rawValue }
    }
    var solvent: Solvent {
        get { Solvent(rawValue: solventRaw) ?? .ethanol }
        set { solventRaw = newValue.rawValue }
    }
    var flag: LineFlag {
        get { LineFlag(rawValue: flagRaw) ?? .none }
        set { flagRaw = newValue.rawValue }
    }

    var displayName: String {
        material?.name ?? base?.name ?? String(localized: "Missing material", bundle: .l10n)
    }

    var dropsPerGram: Double { material?.dropsPerGram ?? 25 }

    /// Tier shown for the row: the material's, or the heaviest tier inside a base.
    var tier: Tier {
        if let m = material { return m.tier }
        if let b = base {
            let mix = b.mix()
            return Tier.allCases.max { mix.grams(in: $0) < mix.grams(in: $1) } ?? .heart
        }
        return .heart
    }

    func mixLine(visited: Set<UUID>) -> MixLine? {
        if let m = material {
            return MixLine(key: m.id.uuidString, name: m.name, grams: grams, dilution: dilution, solvent: solvent,
                           tier: m.tier, family: m.family, limitPercent: m.limitPercent, costPerGram: m.costPerGram)
        }
        if let b = base {
            if visited.contains(b.id) {
                // A loop: count it as an opaque ingredient instead of recursing forever.
                return MixLine(key: "base:" + b.id.uuidString, name: b.name, grams: grams, dilution: dilution, solvent: solvent)
            }
            return MixLine(key: "base:" + b.id.uuidString, name: b.name, grams: grams, dilution: dilution, solvent: solvent,
                           children: b.mixLines(visited: visited))
        }
        return nil
    }
}

/// One weighed ingredient in a batch, frozen at the time it was made.
struct BatchEntry: Codable, Hashable, Sendable {
    var name: String
    var target: Double
    var actual: Double
    var dilution: Double
    var materialID: UUID?
}

@Model
final class Batch {
    var id: UUID = UUID()
    var formulaID: UUID?
    var formulaName: String = ""
    var formulaVersion: Int = 1
    var madeAt: Date = Date()
    var productRaw: String = ProductType.edp.rawValue
    var concentration: Double = 0.18
    var bottleML: Double = 0
    var concentrateGrams: Double = 0
    var ethanolGrams: Double = 0
    var waterGrams: Double = 0
    var notes: String = ""
    var entriesData: Data = Data()
    /// Days after making on which to remind the user to smell it.
    var reminderDays: [Int] = []
    var rating: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \AgingNote.batch)
    var agingNotes: [AgingNote] = []

    init(formula: Formula, entries: [BatchEntry], bottleML: Double, concentrateGrams: Double,
         ethanolGrams: Double, waterGrams: Double) {
        self.id = UUID()
        self.formulaID = formula.id
        self.formulaName = formula.name
        self.formulaVersion = formula.version
        self.productRaw = formula.productRaw
        self.concentration = formula.concentration
        self.bottleML = bottleML
        self.concentrateGrams = concentrateGrams
        self.ethanolGrams = ethanolGrams
        self.waterGrams = waterGrams
        self.madeAt = Date()
        self.entries = entries
    }

    /// For restoring from a backup, where the formula may no longer exist.
    init(restoredName: String, entries: [BatchEntry]) {
        self.id = UUID()
        self.formulaName = restoredName
        self.madeAt = Date()
        self.entries = entries
    }

    var entries: [BatchEntry] {
        get { (try? JSONDecoder().decode([BatchEntry].self, from: entriesData)) ?? [] }
        set { entriesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var product: ProductType { ProductType(rawValue: productRaw) ?? .edp }

    var ageDays: Int { max(0, Calendar.current.dateComponents([.day], from: madeAt, to: Date()).day ?? 0) }

    var sortedNotes: [AgingNote] { agingNotes.sorted { $0.date > $1.date } }

    /// Largest deviation between target and actual, as a fraction of target.
    var worstDeviation: Double {
        entries.map { $0.target > 0 ? abs($0.actual - $0.target) / $0.target : 0 }.max() ?? 0
    }
}

@Model
final class AgingNote {
    var id: UUID = UUID()
    var date: Date = Date()
    var text: String = ""
    /// 1…5, 0 = not rated.
    var rating: Int = 0
    var batch: Batch?

    init(text: String, rating: Int) {
        self.id = UUID()
        self.date = Date()
        self.text = text
        self.rating = rating
    }
}
