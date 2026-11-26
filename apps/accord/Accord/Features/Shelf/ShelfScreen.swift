import SwiftUI
import SwiftData

struct ShelfScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var state
    @Environment(ProStore.self) private var store
    @Query(sort: \Formula.updatedAt, order: .reverse) private var formulas: [Formula]
    @State private var query = ""
    @State private var category: String?
    @State private var showNew = false
    @State private var showSettings = false
    @State private var compareBase: Formula?
    @State private var exportFormula: Formula?
    @State private var toDelete: Formula?

    private var categories: [String] {
        Array(Set(formulas.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [Formula] {
        formulas.filter { f in
            (category == nil || f.category == category) &&
            (query.isEmpty || f.name.localizedCaseInsensitiveContains(query) || f.category.localizedCaseInsensitiveContains(query)
             || f.lines.contains { $0.displayName.localizedCaseInsensitiveContains(query) })
        }
    }

    private var userCount: Int { formulas.filter { !$0.isSample }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Formulas").font(Theme.display(38, relativeTo: .largeTitle)).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.ink).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Settings"))
                    .accessibilityIdentifier("open-settings")
                }
                if !store.isPro {
                    Text("\(max(0, ProStore.freeFormulaLimit - userCount)) of \(ProStore.freeFormulaLimit) free formulas left · examples don’t count")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                }

                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft)
                    TextField(text: $query) { Text("Search formulas or materials") }
                        .textInputAutocapitalization(.never)
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hair))

                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            FamilyChip(title: String(localized: "All", bundle: .l10n), color: Theme.ink, selected: category == nil) { category = nil }
                            ForEach(categories, id: \.self) { c in
                                FamilyChip(title: c, color: Theme.amber, selected: category == c) { category = category == c ? nil : c }
                            }
                        }
                    }
                }

                if filtered.isEmpty {
                    ActionEmpty(title: query.isEmpty ? "No formulas yet" : "Nothing matches",
                                message: query.isEmpty ? "Your formulas live here as bottles, filled with their top, heart and base."
                                                       : "Try another name, a category or a material.",
                                action: "New formula") { startNew() }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible(), spacing: Theme.Space.m)],
                              spacing: Theme.Space.l) {
                        ForEach(filtered) { f in
                            BottleCard(formula: f, isCurrent: f.id == state.currentFormulaID)
                                .onTapGesture { Haptics.tap(); state.open(f) }
                                .contextMenu { menu(for: f) }
                                .accessibilityIdentifier("bottle-\(f.name)")
                        }
                    }
                    .padding(.top, Theme.Space.s)
                }
            }
            .screenPadding()
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { startNew() } label: { Label("New formula", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                .background(Theme.paper.opacity(0.96))
                .accessibilityIdentifier("new-formula")
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewFormulaSheet() }
        .sheet(isPresented: $showSettings) { SettingsScreen() }
        .sheet(item: $compareBase) { f in ComparePickerSheet(base: f) }
        .sheet(item: $exportFormula) { f in ExportSheet(formula: f) }
        .confirmationDialog(Text("Delete “\(toDelete?.name ?? "")”?"), isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete formula and its lines", role: .destructive) {
                if let f = toDelete {
                    if state.currentFormulaID == f.id { state.currentFormulaID = nil }
                    context.delete(f)
                    try? context.save()
                }
                toDelete = nil
            }
        } message: { Text("Batches you already made keep their records.") }
    }

    private func startNew() {
        if FormulaActions.ensureRoom(context, store: store, state: state) { showNew = true }
    }

    @ViewBuilder private func menu(for f: Formula) -> some View {
        Button { state.open(f) } label: { Label("Open on the bench", systemImage: "flask") }
        Button {
            guard FormulaActions.ensureRoom(context, store: store, state: state) else { return }
            state.open(FormulaActions.duplicate(f, asVersion: true, in: context))
        } label: { Label("Save as new version", systemImage: "plus.square.on.square") }
        Button {
            guard FormulaActions.ensureRoom(context, store: store, state: state) else { return }
            FormulaActions.duplicate(f, asVersion: false, in: context)
        } label: { Label("Duplicate", systemImage: "doc.on.doc") }
        Button { if store.isPro { compareBase = f } else { state.proReason = .compare } } label: {
            Label("Compare with…", systemImage: "arrow.left.arrow.right")
        }
        Button { if store.isPro { exportFormula = f } else { state.proReason = .export } } label: {
            Label("Export…", systemImage: "square.and.arrow.up")
        }
        Button { f.isFavorite.toggle() } label: {
            Label(f.isFavorite ? "Remove star" as LocalizedStringKey : "Star", systemImage: f.isFavorite ? "star.slash" : "star")
        }
        Divider()
        Button(role: .destructive) { toDelete = f } label: { Label("Delete", systemImage: "trash") }
    }
}

struct BottleCard: View {
    let formula: Formula
    let isCurrent: Bool

    var body: some View {
        let mix = formula.mix()
        let layers = Tier.Layer.allCases.map { layer in Tier.allCases.filter { $0.layer == layer }.reduce(0) { $0 + mix.grams(in: $1) } }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ZStack(alignment: .topTrailing) {
                FlaconView(layers: layers.reduce(0, +) > 0 ? layers : [1, 1, 1], fill: layers.reduce(0, +) > 0 ? 0.8 : 0.0)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.m)
                    .background(Theme.sunken.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.amber, lineWidth: 2)
                        }
                    }
                if formula.isFavorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.amber).padding(8)
                }
            }
            Text(verbatim: formula.name)
                .font(Theme.display(19, relativeTo: .headline))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            HStack(spacing: 4) {
                if formula.version > 1 { Text(verbatim: String(localized: "v\(formula.version)", bundle: .l10n)) }
                Text(verbatim: formula.product.name).lineLimit(1)
            }
            .font(.caption).foregroundStyle(Theme.inkSoft)
            Text(verbatim: formula.isSample ? String(localized: "Example", bundle: .l10n) : Fmt.date(formula.updatedAt))
                .font(.caption2).foregroundStyle(Theme.inkSoft)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct NewFormulaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var state
    @Query(sort: \Formula.updatedAt, order: .reverse) private var formulas: [Formula]
    @State private var name = ""
    @State private var product: ProductType = .edp
    @State private var category = ""
    @FocusState private var focused: Bool

    private var categories: [String] { Array(Set(formulas.map(\.category).filter { !$0.isEmpty })).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $name) { Text("Name, e.g. Fig Leaf 1") }
                        .font(Theme.display(22, relativeTo: .title3))
                        .focused($focused)
                        .accessibilityIdentifier("new-formula-name")
                    Picker(selection: $product) {
                        ForEach(ProductType.allCases) { p in Text(verbatim: p.name).tag(p) }
                    } label: { Text("Product") }
                    TextField(text: $category) { Text("Category (optional)") }
                    if !categories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(categories, id: \.self) { c in
                                    FamilyChip(title: c, color: Theme.amber, selected: category == c) { category = c }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle(Text("New formula"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let f = FormulaActions.create(name: n.isEmpty ? String(localized: "Untitled", bundle: .l10n) : n,
                                                      product: product, category: category.trimmingCharacters(in: .whitespaces), in: context)
                        Haptics.success()
                        state.open(f)
                        dismiss()
                    }
                    .accessibilityIdentifier("create-formula")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
