import XCTest
import SwiftData
@testable import Accord

final class MixTests: XCTestCase {
    func testDilutionCountsOnlyActiveMaterial() {
        let lines = [
            MixLine(key: "a", name: "A", grams: 10, dilution: 0.1, solvent: .ethanol),
            MixLine(key: "b", name: "B", grams: 9),
        ]
        let mix = FormulaMath.mix(lines)
        XCTAssertEqual(mix.totalGrams, 19, accuracy: 1e-9)
        XCTAssertEqual(mix.activeGrams, 10, accuracy: 1e-9)
        XCTAssertEqual(mix.solvents[.ethanol] ?? 0, 9, accuracy: 1e-9)
        let a = mix.components.first { $0.key == "a" }!
        XCTAssertEqual(a.pureGrams, 1, accuracy: 1e-9)
        XCTAssertEqual(mix.share(a), 1.0 / 19.0, accuracy: 1e-9)
    }

    func testSameMaterialOnTwoLinesIsAggregated() {
        let mix = FormulaMath.mix([MixLine(key: "a", name: "A", grams: 2), MixLine(key: "a", name: "A", grams: 3, dilution: 0.5)])
        XCTAssertEqual(mix.components.count, 1)
        XCTAssertEqual(mix.components[0].pureGrams, 3.5, accuracy: 1e-9)
    }

    func testNestedBaseIsScaledToItsLineWeight() {
        // Base: 30 g X + 10 g Y (10 % dilution). Used at 4 g in the parent.
        let base = MixLine(key: "base", name: "Base", grams: 4, children: [
            MixLine(key: "x", name: "X", grams: 30),
            MixLine(key: "y", name: "Y", grams: 10, dilution: 0.1, solvent: .dpg),
        ])
        let mix = FormulaMath.mix([base, MixLine(key: "z", name: "Z", grams: 6)])
        XCTAssertEqual(mix.totalGrams, 10, accuracy: 1e-9)
        XCTAssertEqual(mix.components.first { $0.key == "x" }!.pureGrams, 3, accuracy: 1e-9)
        XCTAssertEqual(mix.components.first { $0.key == "y" }!.pureGrams, 0.1, accuracy: 1e-9)
        XCTAssertEqual(mix.solvents[.dpg] ?? 0, 0.9, accuracy: 1e-9)
        XCTAssertNil(mix.components.first { $0.key == "base" })
    }

    func testDilutedBaseCarriesItsOwnSolvent() {
        let base = MixLine(key: "base", name: "Base", grams: 10, dilution: 0.5, solvent: .ethanol, children: [MixLine(key: "x", name: "X", grams: 1)])
        let mix = FormulaMath.mix([base])
        XCTAssertEqual(mix.components[0].pureGrams, 5, accuracy: 1e-9)
        XCTAssertEqual(mix.solvents[.ethanol] ?? 0, 5, accuracy: 1e-9)
    }

    func testZeroAndNegativeLinesAreIgnored() {
        let mix = FormulaMath.mix([MixLine(key: "a", name: "A", grams: 0), MixLine(key: "b", name: "B", grams: -3), MixLine(key: "c", name: "C", grams: .nan)])
        XCTAssertEqual(mix.totalGrams, 0)
        XCTAssertTrue(mix.components.isEmpty)
    }

    func testPercentEntryKeepsOtherLinesFixed() {
        // Others weigh 30 g; we want this line to be 25 % → 10 g.
        XCTAssertEqual(FormulaMath.grams(forPercent: 25, othersTotal: 30)!, 10, accuracy: 1e-9)
        XCTAssertNil(FormulaMath.grams(forPercent: 100, othersTotal: 30))
        XCTAssertNil(FormulaMath.grams(forPercent: -5, othersTotal: 30))
        XCTAssertEqual(FormulaMath.grams(forPercent: 0, othersTotal: 30), 0)
        XCTAssertEqual(FormulaMath.grams(forPercent: 100, othersTotal: 0), 1)
    }

    func testDropsRoundTrip() {
        let g = FormulaMath.grams(fromDrops: 50, dropsPerGram: 25)
        XCTAssertEqual(g, 2, accuracy: 1e-9)
        XCTAssertEqual(FormulaMath.drops(fromGrams: g, dropsPerGram: 25), 50, accuracy: 1e-9)
    }

    func testCostSkipsUnpricedMaterials() {
        let mix = FormulaMath.mix([MixLine(key: "a", name: "A", grams: 10, dilution: 0.1, costPerGram: 2), MixLine(key: "b", name: "B", grams: 5)])
        XCTAssertEqual(mix.cost.value, 2, accuracy: 1e-9) // 1 g neat × 2
        XCTAssertEqual(mix.cost.missing, 1)
    }
}

final class ProductTests: XCTestCase {
    func testComplianceUsesFinishedProductLevel() {
        // A is 10 % of the concentrate; at 20 % load it's 2 % of the product.
        let mix = FormulaMath.mix([MixLine(key: "a", name: "A", grams: 10, limitPercent: 1.5), MixLine(key: "b", name: "B", grams: 90, limitPercent: 50)])
        let rows = Compliance.check(mix, concentration: 0.2)
        let a = rows.first { $0.component.key == "a" }!
        XCTAssertEqual(a.inProduct, 2, accuracy: 1e-9)
        XCTAssertEqual(a.status, .over)
        XCTAssertEqual(rows.first?.component.key, "a", "violations sort first")
        XCTAssertEqual(rows.first { $0.component.key == "b" }!.status, .ok)
        XCTAssertEqual(Compliance.maxSafeConcentration(mix)!, 0.15, accuracy: 1e-9)
    }

    func testNearLimitWarning() {
        let mix = FormulaMath.mix([MixLine(key: "a", name: "A", grams: 9, limitPercent: 1), MixLine(key: "b", name: "B", grams: 91)])
        XCTAssertEqual(Compliance.check(mix, concentration: 0.1).first!.status, .near) // 0.9 % of 1 %
    }

    func testBottlePlanMassBalance() {
        let plan = ScalePlan.make([("A", 60, 1), ("B", 40, 0.1)], mode: .bottle(ml: 50, concentration: 0.2, waterShare: 0))
        let density = 0.2 * ScalePlan.concentrateDensity + 0.8 * ScalePlan.ethanolDensity
        XCTAssertEqual(plan.totalGrams, 50 * density, accuracy: 1e-6)
        XCTAssertEqual(plan.concentrateGrams / plan.totalGrams, 0.2, accuracy: 1e-9)
        XCTAssertEqual(plan.rows[0].grams / plan.rows[1].grams, 1.5, accuracy: 1e-9, "ratios are preserved")
        XCTAssertEqual(plan.waterGrams, 0)
    }

    func testBottlePlanWithWater() {
        let plan = ScalePlan.make([("A", 1, 1)], mode: .bottle(ml: 100, concentration: 0.1, waterShare: 0.1))
        XCTAssertEqual(plan.waterGrams / (plan.waterGrams + plan.ethanolGrams), 0.1, accuracy: 1e-9)
    }

    func testConcentrateAndFactorModes() {
        let lines: [(name: String, grams: Double, dilution: Double)] = [("A", 3, 1), ("B", 1, 1)]
        XCTAssertEqual(ScalePlan.make(lines, mode: .concentrate(grams: 20)).rows[0].grams, 15, accuracy: 1e-9)
        XCTAssertEqual(ScalePlan.make(lines, mode: .factor(2.5)).concentrateGrams, 10, accuracy: 1e-9)
        XCTAssertEqual(ScalePlan.make([], mode: .concentrate(grams: 20)).factor, 0)
    }

    func testEvaporationFadesTopFirst() {
        let mix = FormulaMath.mix([MixLine(key: "t", name: "T", grams: 50, tier: .top), MixLine(key: "b", name: "B", grams: 50, tier: .base)])
        let curve = EvaporationCurve(mix)
        let start = curve.samples.first!, end = curve.samples.last!
        XCTAssertEqual(start[0], 50, accuracy: 1e-9)
        XCTAssertLessThan(end[0], 0.01)
        XCTAssertGreaterThan(end[2], 20)
        // Monotonic decrease.
        for i in 1..<curve.samples.count { XCTAssertLessThanOrEqual(curve.samples[i].reduce(0, +), curve.samples[i - 1].reduce(0, +) + 1e-9) }
        XCTAssertEqual(EvaporationCurve.dominant(mix, at: 8).first?.0.key, "b")
        XCTAssertEqual(EvaporationCurve.dominant(mix, at: 0).map(\.1).reduce(0, +), 1, accuracy: 1e-9)
    }

    func testDiffClassifiesChanges() {
        let a = FormulaMath.mix([MixLine(key: "x", name: "X", grams: 50), MixLine(key: "y", name: "Y", grams: 50)])
        let b = FormulaMath.mix([MixLine(key: "x", name: "X", grams: 60), MixLine(key: "z", name: "Z", grams: 40)])
        let rows = FormulaDiff.compare(a, b)
        XCTAssertEqual(rows.first { $0.key == "x" }?.kind, .changed)
        XCTAssertEqual(rows.first { $0.key == "x" }!.delta, 10, accuracy: 1e-9)
        XCTAssertEqual(rows.first { $0.key == "y" }?.kind, .removed)
        XCTAssertEqual(rows.first { $0.key == "z" }?.kind, .added)
    }
}

final class CSVTests: XCTestCase {
    func testParsesQuotesAndSemicolons() {
        let rows = CSVImport.parse("Name;Grams\n\"Rose; absolute\";1,5\nLinalool;10\n")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1][0], "Rose; absolute")
        XCTAssertEqual(CSVImport.number(rows[1][1]), 1.5)
    }

    func testNumberFormats() {
        XCTAssertEqual(CSVImport.number("1.234,5"), 1234.5)
        XCTAssertEqual(CSVImport.number("1,234.5"), 1234.5)
        XCTAssertEqual(CSVImport.number("12 %"), 12)
        XCTAssertNil(CSVImport.number(""))
    }

    func testDetectsKind() {
        XCTAssertEqual(CSVImport.detect(["Material", "Grams"]), .formula)
        XCTAssertEqual(CSVImport.detect(["Name", "Family", "Cost per gram"]), .materials)
    }
}

@MainActor
final class StoreTests: XCTestCase {
    /// Containers must outlive their contexts, so keep every one the test creates.
    private var containers: [ModelContainer] = []

    private func container() throws -> ModelContainer {
        let c = try ModelContainer(for: Material.self, Formula.self, FormulaLine.self, Batch.self, AgingNote.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        containers.append(c)
        return c
    }

    func testSeedBuildsNestedSample() throws {
        let c = try container()
        let ctx = c.mainContext
        let evening = SampleData.seedIfNeeded(ctx)
        XCTAssertNotNil(evening)
        XCTAssertNil(SampleData.seedIfNeeded(ctx), "seeds only once")
        XCTAssertTrue(evening!.usesBases)
        let mix = evening!.mix()
        XCTAssertEqual(mix.totalGrams, 100, accuracy: 1e-9)
        XCTAssertTrue(mix.components.contains { $0.name.lowercased().contains("labdanum") || $0.name.contains("Labdanum") || $0.pureGrams > 0 })
        XCTAssertEqual(FormulaActions.userFormulaCount(ctx), 0, "samples don't count")
    }

    func testDuplicateAsVersionKeepsLines() throws {
        let ctx = try container().mainContext
        let f = SampleData.seedIfNeeded(ctx)!
        let v2 = FormulaActions.duplicate(f, asVersion: true, in: ctx)
        XCTAssertEqual(v2.version, 2)
        XCTAssertEqual(v2.parentID, f.id)
        XCTAssertEqual(v2.lines.count, f.lines.count)
        XCTAssertEqual(v2.totalGrams, f.totalGrams, accuracy: 1e-9)
        XCTAssertEqual(FormulaDiff.compare(f.mix(), v2.mix()).filter { $0.kind != .same }.count, 0)
    }

    func testBaseCycleDoesNotRecurseForever() throws {
        let ctx = try container().mainContext
        let a = Formula(name: "A"), b = Formula(name: "B")
        ctx.insert(a); ctx.insert(b)
        let m = Material(name: "M", family: .woody, tier: .base)
        ctx.insert(m)
        _ = FormulaActions.addLine(to: a, material: m, grams: 1, dilution: 1, solvent: .ethanol, unit: .grams, in: ctx)
        _ = FormulaActions.addLine(to: a, base: b, grams: 1, dilution: 1, solvent: .ethanol, unit: .grams, in: ctx)
        _ = FormulaActions.addLine(to: b, base: a, grams: 1, dilution: 1, solvent: .ethanol, unit: .grams, in: ctx)
        XCTAssertTrue(a.contains(base: b))
        XCTAssertTrue(b.contains(base: a))
        let mix = a.mix()
        XCTAssertGreaterThan(mix.totalGrams, 0)
    }

    func testBackupRoundTrip() throws {
        let src = try container().mainContext
        let f = SampleData.seedIfNeeded(src)!
        let mat = try src.fetch(FetchDescriptor<Material>()).first!
        mat.costPerGram = 1.25
        let batch = Batch(formula: f, entries: [BatchEntry(name: "X", target: 1, actual: 1.1, dilution: 1, materialID: mat.id)],
                          bottleML: 50, concentrateGrams: 10, ethanolGrams: 30, waterGrams: 0)
        src.insert(batch)
        let note = AgingNote(text: "Rounder", rating: 4)
        src.insert(note); note.batch = batch
        try src.save()
        let url = try Backup.make(src)
        let dst = try container().mainContext
        let s = try Backup.restore(try Data(contentsOf: url), into: dst)
        XCTAssertEqual(s.formulas, 3)
        XCTAssertEqual(s.batches, 1)
        let restored = try dst.fetch(FetchDescriptor<Formula>()).first { $0.id == f.id }!
        XCTAssertEqual(restored.mix().totalGrams, f.mix().totalGrams, accuracy: 1e-9)
        XCTAssertTrue(restored.usesBases, "base links survive")
        XCTAssertEqual(try dst.fetch(FetchDescriptor<Material>()).first { $0.id == mat.id }?.costPerGram, 1.25)
        XCTAssertEqual(try dst.fetch(FetchDescriptor<AgingNote>()).first?.text, "Rounder")
        // Restoring twice adds nothing.
        let again = try Backup.restore(try Data(contentsOf: url), into: dst)
        XCTAssertEqual(again.formulas + again.materials + again.batches, 0)
    }

    func testCSVFormulaImportCreatesMissingMaterials() throws {
        let ctx = try container().mainContext
        SampleData.seedIfNeeded(ctx)
        let before = try ctx.fetchCount(FetchDescriptor<Material>())
        let r = try CSVImport.run("Material,Grams,Dilution\nBergamot oil,10,\nMystery accord,2,10%\nTotal,12,\n", fileName: "Test.csv", into: ctx)
        XCTAssertEqual(r.kind, .formula)
        XCTAssertEqual(r.updated, 2)
        XCTAssertEqual(r.created, 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Material>()), before + 1)
        XCTAssertEqual(r.formula?.sortedLines.last?.dilution ?? 0, 0.1, accuracy: 1e-9)
    }

    func testInventoryDeductsNeatGrams() throws {
        let ctx = try container().mainContext
        let m = Material(name: "M", family: .woody, tier: .base)
        m.stockGrams = 10
        ctx.insert(m)
        Inventory.deduct([BatchEntry(name: "M", target: 5, actual: 4, dilution: 0.5, materialID: m.id)], in: ctx)
        XCTAssertEqual(m.stockGrams ?? 0, 8, accuracy: 1e-9)
    }
}

final class LanguageTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(AppLanguage.normalize("zh-Hans-CN"), "zh-Hans")
        XCTAssertEqual(AppLanguage.normalize("zh-TW"), "zh-Hant")
        XCTAssertEqual(AppLanguage.normalize("pt-PT"), "pt-BR")
        XCTAssertEqual(AppLanguage.normalize("de-AT"), "de")
        XCTAssertEqual(AppLanguage.normalize("ru"), "en")
    }

    func testEveryLanguageHasABundleAndTranslatesKeyStrings() {
        for code in AppLanguage.supported {
            let path = Bundle.main.path(forResource: code, ofType: "lproj")
            XCTAssertNotNil(path, "missing \(code).lproj")
            guard let path, let b = Bundle(path: path) else { continue }
            let v = b.localizedString(forKey: "Add material", value: "§", table: "Localizable")
            XCTAssertNotEqual(v, "§", code)
            XCTAssertEqual(b.localizedString(forKey: "tag.base", value: "§", table: "Localizable") == "tag.base", false, "tag.base unresolved in \(code)")
            if code != "en" { XCTAssertNotEqual(v, "Add material", "untranslated in \(code)") }
        }
    }

    @MainActor
    func testInAppSwitchChangesCodeBuiltStrings() {
        let lang = AppLanguage()
        lang.select("ja")
        XCTAssertNotEqual(Tier.top.name, "Top")
        lang.select("de")
        XCTAssertNotEqual(AppState.Tab.shelf.title, "Formulas")
        lang.select(nil)
    }
}
