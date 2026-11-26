import Foundation
import SwiftData

/// First-launch library and three example formulas. Names are generic (no trade names); the library
/// carries no regulatory limits: the user enters their own from supplier documents.
enum SampleData {
    struct Spec {
        let name: String
        let family: Family
        let tier: Tier
        let natural: Bool
        let dilution: Double
        let dropsPerGram: Double
        let odor: String
    }

    static let materials: [Spec] = [
        Spec(name: "Bergamot oil", family: .citrus, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Fresh, sparkling, slightly floral peel"),
        Spec(name: "Lemon oil", family: .citrus, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Bright zest, juicy"),
        Spec(name: "Sweet orange oil", family: .citrus, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Sweet, round orange peel"),
        Spec(name: "Pink grapefruit oil", family: .citrus, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Bitter-fresh, sulphury sparkle"),
        Spec(name: "Mandarin oil", family: .citrus, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Soft, sweet, slightly aldehydic"),
        Spec(name: "Lime oil (distilled)", family: .citrus, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Sharp, candied lime"),
        Spec(name: "Dihydromyrcenol", family: .citrus, tier: .topHeart, natural: false, dilution: 1, dropsPerGram: 32, odor: "Clean metallic citrus, laundry fresh"),
        Spec(name: "Petitgrain oil", family: .green, tier: .topHeart, natural: true, dilution: 1, dropsPerGram: 30, odor: "Green, woody leaf, bitter orange"),
        Spec(name: "Galbanum oil", family: .green, tier: .topHeart, natural: true, dilution: 0.1, dropsPerGram: 28, odor: "Intense green, snapped stems"),
        Spec(name: "cis-3-Hexenol", family: .green, tier: .top, natural: false, dilution: 0.1, dropsPerGram: 32, odor: "Cut grass"),
        Spec(name: "Lavender oil", family: .aromatic, tier: .topHeart, natural: true, dilution: 1, dropsPerGram: 30, odor: "Herbal, floral, camphor edge"),
        Spec(name: "Rosemary oil", family: .aromatic, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Camphoraceous, herbal"),
        Spec(name: "Clary sage oil", family: .aromatic, tier: .heart, natural: true, dilution: 1, dropsPerGram: 30, odor: "Herbal, tea-like, ambery"),
        Spec(name: "Linalool", family: .floral, tier: .topHeart, natural: false, dilution: 1, dropsPerGram: 32, odor: "Fresh floral-woody, lily of the valley hint"),
        Spec(name: "Linalyl acetate", family: .floral, tier: .top, natural: false, dilution: 1, dropsPerGram: 32, odor: "Bergamot-lavender, fruity"),
        Spec(name: "Methyl dihydrojasmonate", family: .floral, tier: .heart, natural: false, dilution: 1, dropsPerGram: 28, odor: "Transparent jasmine, airy"),
        Spec(name: "Phenylethyl alcohol", family: .floral, tier: .heart, natural: false, dilution: 1, dropsPerGram: 28, odor: "Soft rose petals"),
        Spec(name: "Geraniol", family: .floral, tier: .heart, natural: false, dilution: 1, dropsPerGram: 30, odor: "Rosy, slightly citrus"),
        Spec(name: "Citronellol", family: .floral, tier: .heart, natural: false, dilution: 1, dropsPerGram: 30, odor: "Fresh rose, waxy"),
        Spec(name: "Benzyl acetate", family: .floral, tier: .topHeart, natural: false, dilution: 1, dropsPerGram: 28, odor: "Jasmine, pear-like"),
        Spec(name: "Geranium oil", family: .floral, tier: .heart, natural: true, dilution: 1, dropsPerGram: 30, odor: "Rosy, minty-green"),
        Spec(name: "Jasmine absolute", family: .floral, tier: .heart, natural: true, dilution: 0.1, dropsPerGram: 22, odor: "Rich, indolic, fruity jasmine"),
        Spec(name: "Ylang ylang oil", family: .floral, tier: .heart, natural: true, dilution: 1, dropsPerGram: 28, odor: "Creamy, banana-floral"),
        Spec(name: "Indole", family: .animalic, tier: .heart, natural: false, dilution: 0.01, dropsPerGram: 30, odor: "Animalic white-flower depth"),
        Spec(name: "alpha-Ionone", family: .powdery, tier: .heart, natural: false, dilution: 1, dropsPerGram: 28, odor: "Violet, orris, woody"),
        Spec(name: "Heliotropin", family: .powdery, tier: .heartBase, natural: false, dilution: 0.1, dropsPerGram: 28, odor: "Almond-cherry powder"),
        Spec(name: "gamma-Decalactone", family: .fruity, tier: .heartBase, natural: false, dilution: 0.1, dropsPerGram: 28, odor: "Creamy peach"),
        Spec(name: "Ethyl maltol", family: .gourmand, tier: .heart, natural: false, dilution: 0.1, dropsPerGram: 30, odor: "Candy floss, caramel"),
        Spec(name: "Pink pepper oil", family: .spicy, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Rosy, peppery sparkle"),
        Spec(name: "Black pepper oil", family: .spicy, tier: .top, natural: true, dilution: 1, dropsPerGram: 30, odor: "Dry, crackling pepper"),
        Spec(name: "Cardamom oil", family: .spicy, tier: .topHeart, natural: true, dilution: 1, dropsPerGram: 30, odor: "Cool, eucalyptus-spice"),
        Spec(name: "Clove bud oil", family: .spicy, tier: .heart, natural: true, dilution: 0.1, dropsPerGram: 28, odor: "Warm, sweet clove"),
        Spec(name: "Atlas cedarwood oil", family: .woody, tier: .base, natural: true, dilution: 1, dropsPerGram: 25, odor: "Sweet, dry pencil shavings"),
        Spec(name: "Virginia cedarwood oil", family: .woody, tier: .heartBase, natural: true, dilution: 1, dropsPerGram: 25, odor: "Dry, clean cedar"),
        Spec(name: "Australian sandalwood oil", family: .woody, tier: .base, natural: true, dilution: 1, dropsPerGram: 20, odor: "Creamy, soft wood"),
        Spec(name: "Vetiver oil", family: .woody, tier: .base, natural: true, dilution: 1, dropsPerGram: 18, odor: "Smoky, earthy roots"),
        Spec(name: "Patchouli oil", family: .woody, tier: .base, natural: true, dilution: 1, dropsPerGram: 22, odor: "Earthy, dark, camphor-chocolate"),
        Spec(name: "Guaiacwood oil", family: .woody, tier: .base, natural: true, dilution: 1, dropsPerGram: 20, odor: "Smoky rose-wood"),
        Spec(name: "OTNE", family: .woody, tier: .base, natural: false, dilution: 1, dropsPerGram: 25, odor: "Velvety cedar-amber glow"),
        Spec(name: "Labdanum resinoid", family: .amber, tier: .base, natural: true, dilution: 0.5, dropsPerGram: 15, odor: "Dark, leathery amber"),
        Spec(name: "Benzoin resinoid", family: .amber, tier: .base, natural: true, dilution: 0.5, dropsPerGram: 15, odor: "Vanillic, balsamic"),
        Spec(name: "Ambroxide", family: .amber, tier: .base, natural: false, dilution: 0.1, dropsPerGram: 28, odor: "Warm mineral amber, skin-like"),
        Spec(name: "Vanillin", family: .gourmand, tier: .base, natural: false, dilution: 0.1, dropsPerGram: 30, odor: "Vanilla"),
        Spec(name: "Ethyl vanillin", family: .gourmand, tier: .base, natural: false, dilution: 0.1, dropsPerGram: 30, odor: "Intense creamy vanilla"),
        Spec(name: "Tonka bean absolute", family: .gourmand, tier: .base, natural: true, dilution: 0.1, dropsPerGram: 20, odor: "Hay, almond, tobacco sweetness"),
        Spec(name: "Coumarin", family: .powdery, tier: .base, natural: false, dilution: 0.1, dropsPerGram: 30, odor: "Hay, tonka, warm powder"),
        Spec(name: "Ethylene brassylate", family: .musk, tier: .base, natural: false, dilution: 1, dropsPerGram: 25, odor: "Clean, sweet white musk"),
        Spec(name: "Pentadecanolide", family: .musk, tier: .base, natural: false, dilution: 0.1, dropsPerGram: 25, odor: "Soft, powdery musk"),
        Spec(name: "HHCB", family: .musk, tier: .base, natural: false, dilution: 0.5, dropsPerGram: 25, odor: "Floral laundry musk"),
        Spec(name: "Watermelon ketone", family: .aquatic, tier: .topHeart, natural: false, dilution: 0.01, dropsPerGram: 30, odor: "Marine, melon, sea breeze"),
        Spec(name: "Isobutyl quinoline", family: .leather, tier: .heart, natural: false, dilution: 0.01, dropsPerGram: 30, odor: "Earthy green leather"),
        Spec(name: "Birch tar oil", family: .leather, tier: .base, natural: true, dilution: 0.01, dropsPerGram: 25, odor: "Smoky, tarry leather"),
    ]

    /// (material name or "Base:<formula>", grams, override dilution)
    typealias Row = (String, Double, Double?)

    static let cologne: [Row] = [
        ("Bergamot oil", 30, nil), ("Lemon oil", 12, nil), ("Petitgrain oil", 10, nil), ("Lavender oil", 8, nil),
        ("Linalool", 10, nil), ("Methyl dihydrojasmonate", 15, nil), ("Ethylene brassylate", 10, nil), ("Atlas cedarwood oil", 5, nil),
    ]
    static let amberBase: [Row] = [
        ("Labdanum resinoid", 30, nil), ("Benzoin resinoid", 20, nil), ("Vanillin", 15, nil), ("Coumarin", 15, nil),
        ("Ambroxide", 10, nil), ("Patchouli oil", 10, nil),
    ]
    static let eveningAmber: [Row] = [
        ("Base:Amber Base", 35, nil), ("Bergamot oil", 15, nil), ("Pink pepper oil", 5, nil), ("Cardamom oil", 3, nil),
        ("Jasmine absolute", 4, nil), ("Methyl dihydrojasmonate", 12, nil), ("OTNE", 15, nil), ("Ethylene brassylate", 8, nil),
        ("Australian sandalwood oil", 3, nil),
    ]

    /// Starter names and descriptions are translated at seeding time (keys live in the string catalog,
    /// added by scripts/build_strings.py from localization/seed.py); afterwards they are the user's data.
    static func loc(_ english: String) -> String {
        Bundle.l10n.localizedString(forKey: english, value: english, table: "Localizable")
    }

    /// Seeds the library on first launch. Returns the formula to open on the bench.
    @MainActor @discardableResult
    static func seedIfNeeded(_ context: ModelContext) -> Formula? {
        let count = (try? context.fetchCount(FetchDescriptor<Material>())) ?? 0
        guard count == 0 else { return nil }
        var byName: [String: Material] = [:]
        for s in materials {
            let m = Material(name: loc(s.name), family: s.family, tier: s.tier, odor: loc(s.odor), isNatural: s.natural,
                             dropsPerGram: s.dropsPerGram, defaultDilution: s.dilution)
            context.insert(m)
            byName[s.name] = m
        }
        func build(_ name: String, _ product: ProductType, _ category: String, _ rows: [Row], bases: [String: Formula]) -> Formula {
            let f = Formula(name: loc(name), product: product, category: loc(category), isSample: true)
            context.insert(f)
            for (i, row) in rows.enumerated() {
                if row.0.hasPrefix("Base:"), let b = bases[String(row.0.dropFirst(5))] {
                    let line = FormulaLine(order: i, grams: row.1, base: b)
                    context.insert(line)
                    line.formula = f
                } else if let m = byName[row.0] {
                    let line = FormulaLine(order: i, grams: row.1, material: m, dilution: row.2 ?? m.defaultDilution, solvent: m.defaultSolvent)
                    context.insert(line)
                    line.formula = f
                }
            }
            return f
        }
        let cologne = build("Bergamot Cologne", .edc, "Citrus", cologne, bases: [:])
        let amber = build("Amber Base", .concentrate, "Bases", amberBase, bases: [:])
        let evening = build("Evening Amber", .edp, "Amber", eveningAmber, bases: ["Amber Base": amber])
        cologne.updatedAt = Date().addingTimeInterval(-60)
        amber.updatedAt = Date().addingTimeInterval(-120)
        evening.updatedAt = Date()
        try? context.save()
        return evening
    }
}
