import Foundation
import WidgetKit

/// Writes a small snapshot of maturing batches to the App Group for the home-screen widget.
/// The widget target has its own copy of this format (AccordWidget/AccordWidget.swift).
enum WidgetBridge {
    static let group = "group.com.noobclaw.accord"
    static let key = "accord.widget.snapshot"

    struct Snapshot: Codable {
        struct Item: Codable {
            var name: String
            var madeAt: Date
            var rating: Int
            var layers: [Double]
        }
        var items: [Item]
        var language: String
        var noir: Bool
    }

    @MainActor
    static func write(_ batches: [Batch], formulas: [Formula]) {
        let items = batches.sorted { $0.madeAt > $1.madeAt }.prefix(6).map { b -> Snapshot.Item in
            var layers = [1.0, 1.0, 1.0]
            if let f = formulas.first(where: { $0.id == b.formulaID }) {
                let mix = f.mix()
                layers = Tier.Layer.allCases.map { layer in Tier.allCases.filter { $0.layer == layer }.reduce(0) { $0 + mix.grams(in: $1) } }
            }
            return Snapshot.Item(name: b.formulaName, madeAt: b.madeAt, rating: b.rating, layers: layers)
        }
        let snap = Snapshot(items: Array(items), language: AppLanguage.currentCode, noir: Theme.isNoir)
        guard let data = try? JSONEncoder().encode(snap), let defaults = UserDefaults(suiteName: group) else { return }
        if defaults.data(forKey: key) == data { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
