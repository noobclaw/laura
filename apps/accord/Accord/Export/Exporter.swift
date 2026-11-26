import Foundation
import SwiftData
import UIKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv, markdown, pdf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .csv: return String(localized: "Spreadsheet (CSV)", bundle: .l10n)
        case .markdown: return String(localized: "Notes (Markdown)", bundle: .l10n)
        case .pdf: return String(localized: "Printable sheet (PDF)", bundle: .l10n)
        }
    }
    var symbol: String {
        switch self {
        case .csv: return "tablecells"
        case .markdown: return "text.alignleft"
        case .pdf: return "doc.richtext"
        }
    }
    var ext: String {
        switch self {
        case .csv: return "csv"
        case .markdown: return "md"
        case .pdf: return "pdf"
        }
    }
}

enum Exporter {
    static func fileName(_ base: String, ext: String) -> String {
        let safe = base.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "-")
        return (safe.isEmpty ? "Accord" : safe) + "." + ext
    }

    static func write(_ data: Data, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    static func export(_ f: Formula, as format: ExportFormat) throws -> URL {
        let name = fileName(f.name + (f.version > 1 ? " v\(f.version)" : ""), ext: format.ext)
        switch format {
        case .csv: return try write(Data(csv(f).utf8), name: name)
        case .markdown: return try write(Data(markdown(f).utf8), name: name)
        case .pdf: return try write(pdf(f), name: name)
        }
    }

    // MARK: CSV

    static func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") { return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return s
    }

    /// Machine-readable: "." decimals regardless of language, so it re-imports anywhere.
    @MainActor static func csv(_ f: Formula) -> String {
        let total = f.totalGrams
        var out = "Material,Grams,Percent,Dilution,Solvent,Neat grams,Tier,Family,Note\n"
        for l in f.sortedLines {
            let pct = total > 0 ? l.grams / total * 100 : 0
            let cols = [
                l.displayName, String(format: "%.4f", l.grams), String(format: "%.3f", pct),
                String(format: "%.4f", l.dilution), l.solvent.rawValue, String(format: "%.4f", l.grams * l.dilution),
                l.material.map { "\($0.tier.rawValue)" } ?? "base", l.material?.family.rawValue ?? "", l.note,
            ]
            out += cols.map(csvField).joined(separator: ",") + "\n"
        }
        return out
    }

    // MARK: Markdown

    @MainActor static func markdown(_ f: Formula) -> String {
        let total = f.totalGrams
        let mix = f.mix()
        var out = "# \(f.name)\n\n"
        out += "\(f.product.name)"
        if f.product != .concentrate { out += " · \(Fmt.percent(f.concentration * 100, decimals: 1))" }
        out += " · \(Fmt.grams(total))\n\n"
        out += "| \(String(localized: "Material", bundle: .l10n)) | \(AmountUnit.grams.short) | % | \(String(localized: "Dilution", bundle: .l10n)) |\n|---|---:|---:|---|\n"
        for l in f.sortedLines {
            let pct = total > 0 ? l.grams / total * 100 : 0
            out += "| \(l.displayName) | \(Fmt.number(l.grams)) | \(Fmt.number(pct, maxDecimals: 2)) | \(Fmt.dilution(l.dilution)) |\n"
        }
        out += "\n## \(String(localized: "Pyramid", bundle: .l10n))\n\n"
        let active = max(mix.activeGrams, 0.0001)
        for t in Tier.allCases {
            out += "- \(t.name): \(Fmt.percent(mix.grams(in: t) / active * 100, decimals: 0))\n"
        }
        if !f.notes.isEmpty { out += "\n## \(String(localized: "Notes", bundle: .l10n))\n\n\(f.notes)\n" }
        out += "\n_\(String(localized: "Made with Accord", bundle: .l10n)) · \(Fmt.date(Date()))_\n"
        return out
    }

    // MARK: PDF

    @MainActor static func pdf(_ f: Formula) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 points
        let margin: CGFloat = 48
        let total = f.totalGrams
        let ink = UIColor(hex: 0x2A2420), soft = UIColor(hex: 0x6B6158), amber = UIColor(hex: 0x8A6210)
        let titleFont = UIFont(name: "BodoniModa-Medium", size: 30) ?? .systemFont(ofSize: 30, weight: .semibold)
        let body = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let bodyBold = UIFont.systemFont(ofSize: 11, weight: .semibold)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            ctx.beginPage()
            var y = margin
            func draw(_ s: String, _ font: UIFont, _ color: UIColor, x: CGFloat, width: CGFloat, align: NSTextAlignment = .left) -> CGFloat {
                let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byTruncatingTail
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
                let h = (s as NSString).boundingRect(with: CGSize(width: width, height: 200), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil).height
                (s as NSString).draw(in: CGRect(x: x, y: y, width: width, height: h + 2), withAttributes: attrs)
                return ceil(h)
            }
            let width = page.width - margin * 2
            y += draw(f.name, titleFont, ink, x: margin, width: width) + 4
            var meta = f.product.name
            if f.product != .concentrate { meta += " · " + Fmt.percent(f.concentration * 100, decimals: 1) }
            meta += " · " + Fmt.grams(total) + " · " + Fmt.date(f.updatedAt)
            if f.version > 1 { meta += " · v\(f.version)" }
            y += draw(meta, .systemFont(ofSize: 11), soft, x: margin, width: width) + 18

            let cols: [(String, CGFloat, NSTextAlignment)] = [
                (String(localized: "Material", bundle: .l10n), 0.46, .left), (AmountUnit.grams.short, 0.16, .right),
                ("%", 0.14, .right), (String(localized: "Dilution", bundle: .l10n), 0.24, .right),
            ]
            func row(_ values: [String], font: UIFont, color: UIColor) {
                var x = margin
                var h: CGFloat = 0
                for (i, c) in cols.enumerated() {
                    let w = width * c.1
                    h = max(h, draw(values[i], font, color, x: x, width: w - 6, align: c.2))
                    x += w
                }
                y += h + 7
            }
            row(cols.map(\.0), font: bodyBold, color: amber)
            for l in f.sortedLines {
                if y > page.height - margin - 40 { ctx.beginPage(); y = margin }
                let pct = total > 0 ? l.grams / total * 100 : 0
                row([l.displayName, Fmt.number(l.grams), Fmt.number(pct, maxDecimals: 2), Fmt.dilution(l.dilution)], font: body, color: ink)
            }
            y += 8
            row([String(localized: "Total", bundle: .l10n), Fmt.number(total), "100", ""], font: bodyBold, color: ink)
            if !f.notes.isEmpty {
                y += 14
                y += draw(f.notes, .systemFont(ofSize: 11), soft, x: margin, width: width)
            }
            _ = draw(String(localized: "Made with Accord", bundle: .l10n), .italicSystemFont(ofSize: 9), soft, x: margin, width: width)
        }
    }
}

// MARK: - Backup

struct BackupFile: Codable {
    var app = "Accord"
    var format = 1
    var exportedAt = Date()
    var materials: [MaterialDTO] = []
    var formulas: [FormulaDTO] = []
    var batches: [BatchDTO] = []

    struct MaterialDTO: Codable {
        var id: UUID; var name: String; var family: String; var tier: Int; var odor: String; var supplier: String; var cas: String
        var costPerGram: Double?; var stockGrams: Double?; var lowStockGrams: Double?; var purchaseDate: Date?; var shelfLifeMonths: Int?
        var dropsPerGram: Double; var limitPercent: Double?; var defaultDilution: Double; var defaultSolvent: String
        var notes: String; var isNatural: Bool; var createdAt: Date
    }
    struct LineDTO: Codable {
        var order: Int; var grams: Double; var unit: String; var dilution: Double; var solvent: String; var flag: String; var note: String
        var materialID: UUID?; var baseID: UUID?
    }
    struct FormulaDTO: Codable {
        var id: UUID; var name: String; var category: String; var notes: String; var createdAt: Date; var updatedAt: Date
        var version: Int; var parentID: UUID?; var product: String; var concentration: Double; var isSample: Bool; var isFavorite: Bool
        var lines: [LineDTO]
    }
    struct NoteDTO: Codable { var date: Date; var text: String; var rating: Int }
    struct BatchDTO: Codable {
        var id: UUID; var formulaID: UUID?; var formulaName: String; var formulaVersion: Int; var madeAt: Date; var product: String
        var concentration: Double; var bottleML: Double; var concentrateGrams: Double; var ethanolGrams: Double; var waterGrams: Double
        var notes: String; var entries: [BatchEntry]; var reminderDays: [Int]; var rating: Int; var agingNotes: [NoteDTO]
    }
}

enum Backup {
    @MainActor static func make(_ context: ModelContext) throws -> URL {
        var file = BackupFile()
        let materials = try context.fetch(FetchDescriptor<Material>())
        file.materials = materials.map {
            .init(id: $0.id, name: $0.name, family: $0.familyRaw, tier: $0.tierRaw, odor: $0.odor, supplier: $0.supplier, cas: $0.cas,
                  costPerGram: $0.costPerGram, stockGrams: $0.stockGrams, lowStockGrams: $0.lowStockGrams, purchaseDate: $0.purchaseDate,
                  shelfLifeMonths: $0.shelfLifeMonths, dropsPerGram: $0.dropsPerGram, limitPercent: $0.limitPercent,
                  defaultDilution: $0.defaultDilution, defaultSolvent: $0.defaultSolventRaw, notes: $0.notes, isNatural: $0.isNatural, createdAt: $0.createdAt)
        }
        file.formulas = try context.fetch(FetchDescriptor<Formula>()).map { f in
            .init(id: f.id, name: f.name, category: f.category, notes: f.notes, createdAt: f.createdAt, updatedAt: f.updatedAt,
                  version: f.version, parentID: f.parentID, product: f.productRaw, concentration: f.concentration,
                  isSample: f.isSample, isFavorite: f.isFavorite,
                  lines: f.sortedLines.map { l in
                      .init(order: l.order, grams: l.grams, unit: l.unitRaw, dilution: l.dilution, solvent: l.solventRaw,
                            flag: l.flagRaw, note: l.note, materialID: l.material?.id, baseID: l.base?.id)
                  })
        }
        file.batches = try context.fetch(FetchDescriptor<Batch>()).map { b in
            .init(id: b.id, formulaID: b.formulaID, formulaName: b.formulaName, formulaVersion: b.formulaVersion, madeAt: b.madeAt,
                  product: b.productRaw, concentration: b.concentration, bottleML: b.bottleML, concentrateGrams: b.concentrateGrams,
                  ethanolGrams: b.ethanolGrams, waterGrams: b.waterGrams, notes: b.notes, entries: b.entries,
                  reminderDays: b.reminderDays, rating: b.rating,
                  agingNotes: b.agingNotes.map { .init(date: $0.date, text: $0.text, rating: $0.rating) })
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = Date().formatted(.iso8601.year().month().day())
        return try Exporter.write(try enc.encode(file), name: "Accord-backup-\(stamp).json")
    }

    struct Summary { var materials = 0, formulas = 0, batches = 0 }

    /// Merges a backup: anything whose id already exists is kept as it is on the phone.
    @MainActor static func restore(_ data: Data, into context: ModelContext) throws -> Summary {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let file = try dec.decode(BackupFile.self, from: data)
        guard file.app == "Accord" else { throw CocoaError(.fileReadCorruptFile) }
        var summary = Summary()
        var materials = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Material>()).map { ($0.id, $0) })
        for d in file.materials where materials[d.id] == nil {
            let m = Material(name: d.name, family: Family(rawValue: d.family) ?? .floral, tier: Tier(rawValue: d.tier) ?? .heart,
                             odor: d.odor, isNatural: d.isNatural, dropsPerGram: d.dropsPerGram, defaultDilution: d.defaultDilution)
            m.id = d.id; m.supplier = d.supplier; m.cas = d.cas; m.costPerGram = d.costPerGram; m.stockGrams = d.stockGrams
            m.lowStockGrams = d.lowStockGrams; m.purchaseDate = d.purchaseDate; m.shelfLifeMonths = d.shelfLifeMonths
            m.limitPercent = d.limitPercent; m.defaultSolventRaw = d.defaultSolvent; m.notes = d.notes; m.createdAt = d.createdAt
            context.insert(m)
            materials[d.id] = m
            summary.materials += 1
        }
        var formulas = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Formula>()).map { ($0.id, $0) })
        var fresh: [(Formula, [BackupFile.LineDTO])] = []
        for d in file.formulas where formulas[d.id] == nil {
            let f = Formula(name: d.name, product: ProductType(rawValue: d.product) ?? .edp, category: d.category, isSample: d.isSample)
            f.id = d.id; f.notes = d.notes; f.createdAt = d.createdAt; f.updatedAt = d.updatedAt; f.version = d.version
            f.parentID = d.parentID; f.concentration = d.concentration; f.isFavorite = d.isFavorite
            context.insert(f)
            formulas[d.id] = f
            fresh.append((f, d.lines))
            summary.formulas += 1
        }
        // Second pass so bases can point at formulas restored in the same file.
        for (f, lines) in fresh {
            for d in lines {
                let l = FormulaLine(order: d.order, grams: d.grams, material: d.materialID.flatMap { materials[$0] },
                                    base: d.baseID.flatMap { formulas[$0] }, dilution: d.dilution, solvent: Solvent(rawValue: d.solvent) ?? .ethanol)
                l.unitRaw = d.unit; l.flagRaw = d.flag; l.note = d.note
                context.insert(l)
                l.formula = f
            }
        }
        let existingBatches = Set(try context.fetch(FetchDescriptor<Batch>()).map(\.id))
        for d in file.batches where !existingBatches.contains(d.id) {
            let b = Batch(restoredName: d.formulaName, entries: d.entries)
            b.bottleML = d.bottleML; b.concentrateGrams = d.concentrateGrams; b.ethanolGrams = d.ethanolGrams; b.waterGrams = d.waterGrams
            b.id = d.id; b.formulaID = d.formulaID; b.formulaName = d.formulaName; b.formulaVersion = d.formulaVersion
            b.madeAt = d.madeAt; b.productRaw = d.product; b.concentration = d.concentration; b.notes = d.notes
            b.reminderDays = d.reminderDays; b.rating = d.rating
            context.insert(b)
            for n in d.agingNotes {
                let note = AgingNote(text: n.text, rating: n.rating)
                note.date = n.date
                context.insert(note)
                note.batch = b
            }
            summary.batches += 1
        }
        try context.save()
        return summary
    }
}
