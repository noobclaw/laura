import SwiftUI
import SwiftData

/// Pick the second formula, then show the difference.
struct ComparePickerSheet: View {
    let base: Formula
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Formula.updatedAt, order: .reverse) private var formulas: [Formula]

    /// Same-name versions first, then everything else.
    private var candidates: [Formula] {
        let others = formulas.filter { $0.id != base.id }
        return others.filter { $0.name == base.name || $0.id == base.parentID || $0.parentID == base.id }
            + others.filter { !($0.name == base.name || $0.id == base.parentID || $0.parentID == base.id) }
    }

    var body: some View {
        NavigationStack {
            List(candidates) { f in
                NavigationLink {
                    CompareScreen(a: base, b: f)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: f.name).foregroundStyle(Theme.ink)
                            Text(verbatim: "\(String(localized: "v\(f.version)", bundle: .l10n)) · \(Fmt.date(f.updatedAt))").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        if f.id == base.parentID { Tag(text: String(localized: "Previous", bundle: .l10n), tint: Theme.amberInk) }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle(Text("Compare “\(base.name)” with"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct CompareScreen: View {
    let a: Formula
    let b: Formula

    var body: some View {
        let ma = a.mix(), mb = b.mix()
        let rows = FormulaDiff.compare(ma, mb)
        let maxShare = max(rows.map { max($0.a, $0.b) }.max() ?? 1, 0.0001)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .top) {
                    column(a, mix: ma, tint: Theme.inkSoft)
                    Image(systemName: "arrow.right").foregroundStyle(Theme.inkSoft).padding(.top, 60)
                    column(b, mix: mb, tint: Theme.amberInk)
                }
                summary(rows)
                VStack(spacing: 0) {
                    ForEach(rows) { r in
                        diffRow(r, maxShare: maxShare).hairDivider()
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            }
            .screenPadding()
            .padding(.bottom, Theme.Space.xl)
        }
        .background(PaperBackground())
        .navigationTitle(Text("Changes"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func column(_ f: Formula, mix: MixResult, tint: Color) -> some View {
        let layers = Tier.Layer.allCases.map { layer in Tier.allCases.filter { $0.layer == layer }.reduce(0) { $0 + mix.grams(in: $1) } }
        return VStack(spacing: 6) {
            FlaconView(layers: layers.reduce(0, +) > 0 ? layers : [1, 1, 1]).frame(width: 70, height: 96)
            Text(verbatim: f.name).font(Theme.display(16, relativeTo: .headline)).lineLimit(2).multilineTextAlignment(.center)
            Text(verbatim: String(localized: "v\(f.version)", bundle: .l10n)).font(.caption).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
    }

    private func summary(_ rows: [DiffRow]) -> some View {
        let added = rows.filter { $0.kind == .added }.count
        let removed = rows.filter { $0.kind == .removed }.count
        let changed = rows.filter { $0.kind == .changed }.count
        return HStack(spacing: Theme.Space.s) {
            Tag(text: String(localized: "\(added) added", bundle: .l10n), tint: Theme.ok)
            Tag(text: String(localized: "\(removed) removed", bundle: .l10n), tint: Theme.danger)
            Tag(text: String(localized: "\(changed) changed", bundle: .l10n), tint: Theme.amberInk)
        }
    }

    private func diffRow(_ r: DiffRow, maxShare: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: r.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: deltaText(r)).font(Theme.figure(.subheadline)).foregroundStyle(color(r))
            }
            GeometryReader { g in
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(Theme.inkSoft.opacity(0.35)).frame(width: max(2, g.size.width * r.a / maxShare), height: 5)
                    Capsule().fill(color(r)).frame(width: max(2, g.size.width * r.b / maxShare), height: 5)
                }
            }
            .frame(height: 13)
            Text(verbatim: "\(Fmt.percent(r.a, decimals: 2)) → \(Fmt.percent(r.b, decimals: 2))").font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private func deltaText(_ r: DiffRow) -> String {
        switch r.kind {
        case .added: return String(localized: "new", bundle: .l10n)
        case .removed: return String(localized: "removed", bundle: .l10n)
        case .same: return "="
        case .changed: return (r.delta > 0 ? "+" : "−") + Fmt.number(abs(r.delta), maxDecimals: 2) + " " + String(localized: "pts", bundle: .l10n)
        }
    }

    private func color(_ r: DiffRow) -> Color {
        switch r.kind {
        case .added: return Theme.ok
        case .removed: return Theme.danger
        case .same: return Theme.inkSoft
        case .changed: return r.delta > 0 ? Theme.amberInk : Theme.heartNote
        }
    }
}
