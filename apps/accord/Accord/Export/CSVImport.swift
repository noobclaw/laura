import Foundation
import SwiftData

/// Reads the spreadsheets perfumers already keep: a materials list or a single formula.
enum CSVImport {
    enum Kind { case materials, formula }

    struct Result {
        var kind: Kind
        var created: Int
        var updated: Int
        var formula: Formula?
    }

    enum Failure: LocalizedError {
        case empty, noNameColumn, noAmountColumn
        var errorDescription: String? {
            switch self {
            case .empty: return String(localized: "The file has no rows.", bundle: .l10n)
            case .noNameColumn: return String(localized: "Couldn’t find a column for the material name (Name or Material).", bundle: .l10n)
            case .noAmountColumn: return String(localized: "Couldn’t find an amount column (Grams, Amount, Weight or Parts).", bundle: .l10n)
            }
        }
    }

    /// Splits CSV text; detects ";" or tab separators used by spreadsheet apps in comma-decimal locales.
    static func parse(_ text: String) -> [[String]] {
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let firstLine = cleaned.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let sep: Character = firstLine.contains("\t") ? "\t" : (firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ",")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(cleaned)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" {
                quoted = true
            } else if c == sep {
                row.append(field); field = ""
            } else if c == "\n" {
                row.append(field); field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    static func column(_ header: [String], _ names: [String]) -> Int? {
        let h = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        for n in names { if let i = h.firstIndex(where: { $0 == n || $0.hasPrefix(n + " ") || $0.hasPrefix(n + "(") }) { return i } }
        return nil
    }

    static func number(_ s: String?) -> Double? {
        guard var s, !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: " ", with: "")
        // "1.234,5" → 1234.5 ; "1,234.5" → 1234.5 ; "12,5" → 12.5
        if s.contains(",") && s.contains(".") {
            s = s.lastIndex(of: ",")! > s.lastIndex(of: ".")! ? s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                                                                : s.replacingOccurrences(of: ",", with: "")
        } else {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        return Double(s.filter { "0123456789.-eE".contains($0) })
    }

    static func detect(_ header: [String]) -> Kind {
        column(header, ["grams", "gram", "g", "amount", "weight", "parts", "qty", "quantity"]) != nil ? .formula : .materials
    }

    @MainActor
    static func run(_ text: String, fileName: String, into context: ModelContext) throws -> Result {
        let rows = parse(text)
        guard rows.count >= 2, let header = rows.first else { throw Failure.empty }
        guard let nameCol = column(header, ["name", "material", "ingredient", "raw material"]) else { throw Failure.noNameColumn }
        var library = try context.fetch(FetchDescriptor<Material>())
        func find(_ name: String) -> Material? { library.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }

        let familyCol = column(header, ["family", "category", "olfactive family"])
        let tierCol = column(header, ["tier", "note", "level", "volatility"])
        let costCol = column(header, ["cost per gram", "cost/g", "price per gram", "cost", "price"])
        let stockCol = column(header, ["stock", "stock (g)", "in stock", "on hand"])
        let limitCol = column(header, ["limit", "max", "ifra", "max %"])
        let supplierCol = column(header, ["supplier", "vendor"])
        let casCol = column(header, ["cas", "cas number"])
        let dilCol = column(header, ["dilution", "strength", "conc"])
        let noteCol = column(header, ["notes", "note", "comment", "odor", "odour", "description"])

        func family(_ s: String?) -> Family? {
            guard let s = s?.lowercased(), !s.isEmpty else { return nil }
            return Family.allCases.first { s.contains($0.rawValue) || s.contains($0.name.lowercased()) }
        }
        func tier(_ s: String?) -> Tier? {
            guard let s = s?.lowercased(), !s.isEmpty else { return nil }
            if let n = Int(s), let t = Tier(rawValue: n) { return t }
            if s.contains("top") && s.contains("heart") || s.contains("top") && s.contains("middle") { return .topHeart }
            if s.contains("heart") && s.contains("base") || s.contains("middle") && s.contains("base") { return .heartBase }
            if s.contains("top") || s.contains("head") { return .top }
            if s.contains("heart") || s.contains("middle") { return .heart }
            if s.contains("base") || s.contains("bottom") { return .base }
            return nil
        }
        func dilution(_ s: String?) -> Double? {
            guard let v = number(s), v > 0 else { return nil }
            return v > 1 ? min(v / 100, 1) : v
        }

        let kind = detect(header)
        var created = 0, updated = 0
        let body = rows.dropFirst()

        switch kind {
        case .materials:
            for r in body {
                guard let name = r[safe: nameCol], !name.isEmpty else { continue }
                let m: Material
                if let existing = find(name) { m = existing; updated += 1 } else {
                    m = Material(name: name, family: family(familyCol.flatMap { r[safe: $0] }) ?? .floral,
                                 tier: tier(tierCol.flatMap { r[safe: $0] }) ?? .heart)
                    context.insert(m); library.append(m); created += 1
                }
                if let f = family(familyCol.flatMap { r[safe: $0] }) { m.family = f }
                if let t = tier(tierCol.flatMap { r[safe: $0] }) { m.tier = t }
                if let v = number(costCol.flatMap { r[safe: $0] }) { m.costPerGram = v }
                if let v = number(stockCol.flatMap { r[safe: $0] }) { m.stockGrams = v }
                if let v = number(limitCol.flatMap { r[safe: $0] }) { m.limitPercent = v }
                if let v = supplierCol.flatMap({ r[safe: $0] }), !v.isEmpty { m.supplier = v }
                if let v = casCol.flatMap({ r[safe: $0] }), !v.isEmpty { m.cas = v }
                if let v = dilution(dilCol.flatMap { r[safe: $0] }) { m.defaultDilution = v }
                if let v = noteCol.flatMap({ r[safe: $0] }), !v.isEmpty { m.odor = v }
            }
            try context.save()
            return Result(kind: .materials, created: created, updated: updated, formula: nil)

        case .formula:
            guard let amountCol = column(header, ["grams", "gram", "g", "amount", "weight", "parts", "qty", "quantity"]) else { throw Failure.noAmountColumn }
            let title = (fileName as NSString).deletingPathExtension
            let f = Formula(name: title.isEmpty ? String(localized: "Imported formula", bundle: .l10n) : title, product: .edp)
            context.insert(f)
            var order = 0
            for r in body {
                guard let name = r[safe: nameCol], !name.isEmpty, name.lowercased() != "total",
                      let g = number(r[safe: amountCol]), g > 0 else { continue }
                let m: Material
                if let existing = find(name) { m = existing } else {
                    m = Material(name: name, family: family(familyCol.flatMap { r[safe: $0] }) ?? .floral,
                                 tier: tier(tierCol.flatMap { r[safe: $0] }) ?? .heart)
                    context.insert(m); library.append(m); created += 1
                }
                let d = dilution(dilCol.flatMap { r[safe: $0] }) ?? m.defaultDilution
                let line = FormulaLine(order: order, grams: g, material: m, dilution: d, solvent: m.defaultSolvent)
                context.insert(line)
                line.formula = f
                order += 1
            }
            try context.save()
            return Result(kind: .formula, created: created, updated: order, formula: f)
        }
    }
}
