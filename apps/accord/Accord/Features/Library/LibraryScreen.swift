import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var state
    @Environment(ProStore.self) private var store
    @Query(sort: \Material.name) private var materials: [Material]
    @State private var query = ""
    @State private var family: Family?
    @State private var filter: Filter = .all
    @State private var importing = false
    @State private var importMessage: String?
    @State private var newMaterial: Material?
    @State private var showDilution = false

    enum Filter: String, CaseIterable, Identifiable {
        case all, lowStock, expiring, unused
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "All", bundle: .l10n)
            case .lowStock: return String(localized: "Low stock", bundle: .l10n)
            case .expiring: return String(localized: "Past shelf life", bundle: .l10n)
            case .unused: return String(localized: "Not in any formula", bundle: .l10n)
            }
        }
    }

    private var filtered: [Material] {
        materials.filter { m in
            (family == nil || m.family == family) &&
            (query.isEmpty || m.name.localizedCaseInsensitiveContains(query) || m.odor.localizedCaseInsensitiveContains(query)
             || m.cas.contains(query) || m.supplier.localizedCaseInsensitiveContains(query)) &&
            {
                switch filter {
                case .all: return true
                case .lowStock: return m.isLowStock
                case .expiring: return m.isExpired
                case .unused: return m.lines.isEmpty
                }
            }()
        }
    }

    private var grouped: [(Family, [Material])] {
        Dictionary(grouping: filtered, by: \.family).sorted { $0.key.name < $1.key.name }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Materials").font(Theme.display(38, relativeTo: .largeTitle)).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { showDilution = true } label: {
                        Image(systemName: "drop.halffull").font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Theme.ink).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Dilution calculator"))
                    .accessibilityIdentifier("open-dilution")
                    Menu {
                        Button { if store.isPro { importing = true } else { state.proReason = .importData } } label: {
                            Label("Import from spreadsheet", systemImage: "tablecells")
                        }
                        Picker(selection: $filter) {
                            ForEach(Filter.allCases) { f in Text(verbatim: f.title).tag(f) }
                        } label: { Label("Show", systemImage: "line.3.horizontal.decrease") }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 20, weight: .medium))
                            .foregroundStyle(filter == .all ? Theme.ink : Theme.amberInk).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Filter and import"))
                }
                Text("\(materials.count) materials · \(alerts) need attention")
                    .font(.footnote).foregroundStyle(alerts > 0 ? Theme.warn : Theme.inkSoft)
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft)
                    TextField(text: $query) { Text("Name, odour, CAS or supplier") }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSoft) }
                            .accessibilityLabel(Text("Clear search"))
                    }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hair))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FamilyChip(title: String(localized: "All", bundle: .l10n), color: Theme.ink, selected: family == nil) { family = nil }
                        ForEach(Family.allCases) { f in
                            FamilyChip(title: f.name, color: Theme.color(f), selected: family == f) { family = family == f ? nil : f }
                        }
                    }
                }
            }
            .plainRow(top: Theme.Space.m)

            if filtered.isEmpty {
                ActionEmpty(title: "Nothing here", message: filter == .all ? "Add the materials on your shelf, or import the spreadsheet you already keep."
                                                                            : "No material matches this filter.",
                            action: "Add material") { addMaterial() }
                    .plainRow()
            }

            ForEach(grouped, id: \.0) { fam, items in
                Section {
                    ForEach(items) { m in
                        NavigationLink { MaterialDetailScreen(material: m) } label: { MaterialRow(material: m) }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.hair)
                            .accessibilityIdentifier("material-\(m.name)")
                    }
                } header: {
                    HStack(spacing: 6) {
                        Dot(color: Theme.color(fam), size: 10)
                        Text(verbatim: fam.name).font(Theme.display(18, italic: true, relativeTo: .headline)).foregroundStyle(Theme.ink)
                        Text(verbatim: "\(items.count)").font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    .textCase(nil)
                }
            }
            Color.clear.frame(height: 80).plainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { addMaterial() } label: { Label("New material", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                .background(Theme.paper.opacity(0.96))
                .accessibilityIdentifier("new-material")
        }
        .sheet(isPresented: $showDilution) { DilutionSheet() }
        .navigationDestination(item: $newMaterial) { m in MaterialDetailScreen(material: m, isNew: true) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            handleImport(result)
        }
        .alert(Text("Import"), isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: importMessage ?? "") }
    }

    private var alerts: Int { materials.filter { $0.isLowStock || $0.isExpired }.count }

    private func addMaterial() {
        let m = Material(name: String(localized: "New material", bundle: .l10n), family: family ?? .floral, tier: .heart)
        context.insert(m)
        newMaterial = m
    }

    private func handleImport(_ result: Swift.Result<URL, Error>) {
        do {
            let url = try result.get()
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let r = try CSVImport.run(text, fileName: url.lastPathComponent, into: context)
            switch r.kind {
            case .materials:
                importMessage = String(localized: "\(r.created) new materials, \(r.updated) updated.", bundle: .l10n)
            case .formula:
                importMessage = String(localized: "Imported a formula with \(r.updated) lines (\(r.created) new materials). It’s on your bench.", bundle: .l10n)
                if let f = r.formula { state.currentFormulaID = f.id }
            }
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

struct MaterialRow: View {
    let material: Material

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.color(material.tier)).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: material.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    if material.isNatural { Image(systemName: "leaf.fill").font(.caption2).foregroundStyle(Theme.ok).accessibilityLabel(Text("Natural")) }
                }
                if !material.odor.isEmpty {
                    Text(verbatim: material.odor).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: material.tier.name).font(.caption).foregroundStyle(Theme.inkSoft)
                if material.isExpired {
                    Tag(text: String(localized: "Past shelf life", bundle: .l10n), tint: Theme.danger)
                } else if material.isLowStock {
                    Tag(text: String(localized: "Low", bundle: .l10n), tint: Theme.warn)
                } else if let s = material.stockGrams {
                    Text(verbatim: Fmt.grams(s)).font(Theme.figure(.caption, weight: .regular)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
