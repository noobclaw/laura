import Foundation

/// One formula line as the engine sees it. Grams are what goes on the scale (solution, not neat).
struct MixLine: Sendable {
    var key: String
    var name: String
    var grams: Double
    /// Fraction of active material in what is weighed: 1 = neat, 0.1 = a 10 % dilution.
    var dilution: Double = 1
    var solvent: Solvent = .ethanol
    var tier: Tier = .heart
    var family: Family = .floral
    /// User's maximum for this material, as a percent of the finished product (e.g. 0.8 means 0.8 %).
    var limitPercent: Double? = nil
    /// Cost of one gram of the neat material.
    var costPerGram: Double? = nil
    /// When the line is a base (a formula used inside another formula), its own lines.
    var children: [MixLine]? = nil
}

/// A neat material after dilutions and bases are unpacked.
struct MixComponent: Identifiable, Sendable, Equatable {
    var key: String
    var name: String
    var tier: Tier
    var family: Family
    var pureGrams: Double
    var limitPercent: Double?
    var costPerGram: Double?
    var id: String { key }
}

struct MixResult: Sendable {
    /// Neat materials, aggregated by key, heaviest first.
    var components: [MixComponent]
    /// Solvent grams carried in by dilutions.
    var solvents: [Solvent: Double]
    /// Everything on the scale.
    var totalGrams: Double

    var activeGrams: Double { components.reduce(0) { $0 + $1.pureGrams } }
    var solventGrams: Double { solvents.values.reduce(0, +) }

    /// Share of a component in the concentrate, 0…1.
    func share(_ c: MixComponent) -> Double { totalGrams > 0 ? c.pureGrams / totalGrams : 0 }

    /// Grams of neat material per layer.
    func grams(in tier: Tier) -> Double { components.filter { $0.tier == tier }.reduce(0) { $0 + $1.pureGrams } }
    func grams(in family: Family) -> Double { components.filter { $0.family == family }.reduce(0) { $0 + $1.pureGrams } }

    /// Cost of the whole batch as written, and whether any material had no price.
    var cost: (value: Double, missing: Int) {
        var v = 0.0, missing = 0
        for c in components {
            if let p = c.costPerGram { v += p * c.pureGrams } else { missing += 1 }
        }
        return (v, missing)
    }
}

enum FormulaMath {
    static let maxDepth = 6

    /// Unpacks dilutions and nested bases into neat materials + solvents.
    static func mix(_ lines: [MixLine]) -> MixResult {
        var comps: [String: MixComponent] = [:]
        var order: [String] = []
        var solvents: [Solvent: Double] = [:]
        var total = 0.0
        for line in lines where line.grams.isFinite && line.grams > 0 {
            total += line.grams
            accumulate(line, factor: 1, depth: 0, comps: &comps, order: &order, solvents: &solvents)
        }
        let list = order.compactMap { comps[$0] }.sorted { $0.pureGrams > $1.pureGrams }
        return MixResult(components: list, solvents: solvents, totalGrams: total)
    }

    private static func accumulate(_ line: MixLine, factor: Double, depth: Int,
                                   comps: inout [String: MixComponent], order: inout [String],
                                   solvents: inout [Solvent: Double]) {
        let grams = line.grams * factor
        guard grams > 0 else { return }
        let d = min(max(line.dilution, 0), 1)
        let active = grams * d
        if d < 1 { solvents[line.solvent, default: 0] += grams - active }

        if let children = line.children, depth < maxDepth {
            let childTotal = children.reduce(0) { $0 + max($1.grams, 0) }
            guard childTotal > 0 else { return }
            let scale = active / childTotal
            for child in children {
                accumulate(child, factor: scale, depth: depth + 1, comps: &comps, order: &order, solvents: &solvents)
            }
            return
        }
        if var c = comps[line.key] {
            c.pureGrams += active
            comps[line.key] = c
        } else {
            comps[line.key] = MixComponent(key: line.key, name: line.name, tier: line.tier, family: line.family,
                                           pureGrams: active, limitPercent: line.limitPercent, costPerGram: line.costPerGram)
            order.append(line.key)
        }
    }

    // MARK: - Entry helpers

    /// Grams for one line so that it makes up `percent` (0…100) of the concentrate, keeping the others fixed.
    /// Returns nil when that is impossible (100 % with other lines present, or a negative value).
    static func grams(forPercent percent: Double, othersTotal: Double) -> Double? {
        let p = percent / 100
        guard p.isFinite, p > 0 else { return p == 0 ? 0 : nil }
        if othersTotal <= 0 { return p >= 1 ? 1 : nil }
        guard p < 1 else { return nil }
        return p / (1 - p) * othersTotal
    }

    static func drops(fromGrams g: Double, dropsPerGram: Double) -> Double { g * max(dropsPerGram, 0.0001) }
    static func grams(fromDrops n: Double, dropsPerGram: Double) -> Double { n / max(dropsPerGram, 0.0001) }
}

// MARK: - Finished product & compliance

struct ComplianceRow: Identifiable, Sendable {
    enum Status: Int, Sendable { case ok, near, over }
    var component: MixComponent
    /// Percent of the finished product (0…100).
    var inProduct: Double
    var limit: Double
    var status: Status
    var id: String { component.key }
}

enum Compliance {
    /// Checks every material that has a user limit against its level in the finished product.
    static func check(_ mix: MixResult, concentration: Double) -> [ComplianceRow] {
        let c = min(max(concentration, 0), 1)
        return mix.components.compactMap { comp in
            guard let limit = comp.limitPercent, limit >= 0 else { return nil }
            let inProduct = mix.share(comp) * c * 100
            let status: ComplianceRow.Status = inProduct > limit + 1e-9 ? .over : (inProduct > limit * 0.8 ? .near : .ok)
            return ComplianceRow(component: comp, inProduct: inProduct, limit: limit, status: status)
        }
        .sorted { ($0.status.rawValue, $0.inProduct / max($0.limit, 1e-9)) > ($1.status.rawValue, $1.inProduct / max($1.limit, 1e-9)) }
    }

    /// Highest concentration at which every limited material stays within its limit (0…1), nil if none limited.
    static func maxSafeConcentration(_ mix: MixResult) -> Double? {
        var best: Double?
        for comp in mix.components {
            guard let limit = comp.limitPercent else { continue }
            let share = mix.share(comp)
            guard share > 0 else { continue }
            let c = min(1, limit / 100 / share)
            best = min(best ?? 1, c)
        }
        return best
    }
}

// MARK: - Evaporation sketch

/// Illustrative model: each tier decays exponentially with its half-life. It is a sketch for comparing
/// drafts, not a measurement, and the UI says so.
struct EvaporationCurve: Sendable {
    static let hours: [Double] = stride(from: 0.0, through: 24.0, by: 0.25).map { $0 }

    /// For each sample time, remaining grams per layer (top / heart / base).
    var samples: [[Double]]
    var initial: Double

    init(_ mix: MixResult) {
        initial = mix.activeGrams
        samples = EvaporationCurve.hours.map { t in
            var layers = [0.0, 0.0, 0.0]
            for c in mix.components {
                layers[c.tier.layer.rawValue] += EvaporationCurve.remaining(c.pureGrams, tier: c.tier, at: t)
            }
            return layers
        }
    }

    static func remaining(_ grams: Double, tier: Tier, at hours: Double) -> Double {
        grams * exp(-log(2) * hours / tier.halfLifeHours)
    }

    /// Materials you would mostly smell at a given time, strongest first.
    static func dominant(_ mix: MixResult, at hours: Double, limit: Int = 3) -> [(MixComponent, Double)] {
        let rows = mix.components.map { ($0, remaining($0.pureGrams, tier: $0.tier, at: hours)) }
        let sum = rows.reduce(0) { $0 + $1.1 }
        guard sum > 0 else { return [] }
        return rows.sorted { $0.1 > $1.1 }.prefix(limit).map { ($0.0, $0.1 / sum) }
    }

    /// Hours until the total falls under 10 % of the start (rough "longevity" figure).
    var longevityHours: Double {
        guard initial > 0 else { return 0 }
        for (i, s) in samples.enumerated() where s.reduce(0, +) < initial * 0.1 {
            return EvaporationCurve.hours[i]
        }
        return 24
    }
}

// MARK: - Scaling

struct ScalePlan: Sendable {
    enum Mode: Sendable, Equatable {
        case factor(Double)
        case concentrate(grams: Double)
        case bottle(ml: Double, concentration: Double, waterShare: Double)
    }

    struct Row: Sendable, Identifiable {
        var id: Int
        var name: String
        var grams: Double
        var dilution: Double
        var isSolventTopUp: Bool = false
    }

    var rows: [Row]
    var factor: Double
    var concentrateGrams: Double
    var ethanolGrams: Double
    var waterGrams: Double
    var totalGrams: Double { concentrateGrams + ethanolGrams + waterGrams }

    static let ethanolDensity = 0.789
    static let concentrateDensity = 0.95
    static let waterDensity = 1.0

    /// `lines` are (name, grams, dilution) as written in the formula.
    static func make(_ lines: [(name: String, grams: Double, dilution: Double)], mode: Mode) -> ScalePlan {
        let base = lines.reduce(0) { $0 + max($1.grams, 0) }
        var factor = 1.0, ethanol = 0.0, water = 0.0
        switch mode {
        case .factor(let f):
            factor = max(f, 0)
        case .concentrate(let g):
            factor = base > 0 ? max(g, 0) / base : 0
        case .bottle(let ml, let conc, let waterShare):
            let c = min(max(conc, 0), 1), w = min(max(waterShare, 0), 0.5)
            // Volume of the finished product = concentrate + diluent, each by its own density.
            let diluentDensity = (1 - w) * ethanolDensity + w * waterDensity
            let density = c * concentrateDensity + (1 - c) * diluentDensity
            let mass = max(ml, 0) * density
            let concentrate = mass * c
            factor = base > 0 ? concentrate / base : 0
            ethanol = mass * (1 - c) * (1 - w)
            water = mass * (1 - c) * w
        }
        let rows = lines.enumerated().map { Row(id: $0.offset, name: $0.element.name, grams: $0.element.grams * factor, dilution: $0.element.dilution) }
        return ScalePlan(rows: rows, factor: factor, concentrateGrams: base * factor, ethanolGrams: ethanol, waterGrams: water)
    }
}

// MARK: - Version compare

struct DiffRow: Identifiable, Sendable {
    enum Kind: Sendable { case added, removed, changed, same }
    var key: String
    var name: String
    /// Percent of concentrate (0…100) in A and B.
    var a: Double
    var b: Double
    var kind: Kind
    var id: String { key }
    var delta: Double { b - a }
}

enum FormulaDiff {
    static func compare(_ a: MixResult, _ b: MixResult, tolerance: Double = 0.005) -> [DiffRow] {
        var rows: [String: DiffRow] = [:]
        for c in a.components { rows[c.key] = DiffRow(key: c.key, name: c.name, a: a.share(c) * 100, b: 0, kind: .removed) }
        for c in b.components {
            let pb = b.share(c) * 100
            if var r = rows[c.key] {
                r.b = pb
                r.kind = abs(r.b - r.a) <= tolerance ? .same : .changed
                rows[c.key] = r
            } else {
                rows[c.key] = DiffRow(key: c.key, name: c.name, a: 0, b: pb, kind: .added)
            }
        }
        return rows.values.sorted { abs($0.delta) == abs($1.delta) ? $0.name < $1.name : abs($0.delta) > abs($1.delta) }
    }
}
