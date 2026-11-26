import SwiftUI
import SwiftData

struct RootView: View {
    let storeFailed: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Environment(AppState.self) private var state
    @Environment(AppLock.self) private var lock
    @State private var showStoreError = false

    var body: some View {
        @Bindable var state = state
        ZStack {
            PaperBackground()
            Group {
                switch state.tab {
                case .bench: NavigationStack { BenchScreen() }
                case .shelf: NavigationStack { ShelfScreen() }
                case .library: NavigationStack { LibraryScreen() }
                case .lab: NavigationStack { LabScreen() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { TabBar() }
        }
        .sheet(item: $state.proReason) { reason in ProSheet(reason: reason) }
        .overlay { if lock.isLocked { LockScreen().transition(.opacity) } }
        .onAppear {
            if let first = SampleData.seedIfNeeded(context), state.currentFormulaID == nil { state.currentFormulaID = first.id }
            if storeFailed { showStoreError = true }
            if ProcessInfo.processInfo.arguments.contains("-UITour") { lock.isLocked = false }
        }
        .onChange(of: phase) { _, new in
            if new == .background { lock.lockIfNeeded() }
            if new == .background { try? context.save() }
        }
        .alert(Text("Your formula book couldn’t be opened"), isPresented: $showStoreError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Accord is running without saving so nothing on your phone is overwritten. Restart the app; if this keeps happening, contact support from Settings.")
        }
    }
}

/// Custom bottom bar: paper, hairline, amber marker under the current tab.
struct TabBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppState.Tab.allCases) { tab in
                let selected = state.tab == tab
                Button {
                    if state.tab != tab { Haptics.select() }
                    withAnimation(Theme.Motion.quick) { state.tab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                            .font(.system(size: 19, weight: .medium))
                            .frame(height: 24)
                        Text(verbatim: tab.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        Capsule().fill(selected ? Theme.amber : .clear).frame(width: 18, height: 3)
                    }
                    .foregroundStyle(selected ? Theme.amberInk : Theme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.top, 6)
        .background(Theme.paper.overlay(alignment: .top) { Rectangle().fill(Theme.hair).frame(height: 0.5) }.ignoresSafeArea(edges: .bottom))
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: Theme.Space.l) {
                Spacer()
                FlaconShape()
                    .fill(Theme.amber.opacity(0.25))
                    .overlay(FlaconShape().stroke(Theme.ink, lineWidth: 2))
                    .frame(width: 90, height: 120)
                Text("Accord is locked").font(Theme.display(28)).foregroundStyle(Theme.ink)
                if let f = lock.failure { Text(verbatim: f).font(.footnote).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center) }
                Spacer()
                Button { lock.unlock() } label: { Label("Unlock", systemImage: "faceid") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(Theme.Space.l)
            }
        }
        .onAppear { lock.unlock() }
    }
}
