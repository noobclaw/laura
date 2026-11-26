import SwiftData
import SwiftUI

@main
struct GroovelensApp: App {
    @State private var language = AppLanguage()
    @State private var store = ProStore()
    @State private var profile = PlayerProfile()
    @State private var analysis = AnalysisCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                // Rebuild every screen when the in-app language changes; the tab survives via SceneStorage.
                .id(language.code)
                .environment(\.locale, language.locale)
                .environment(language)
                .environment(store)
                .environment(profile)
                .environment(analysis)
                .onAppear { analysis.profile = profile }
                .preferredColorScheme(.dark)
                .tint(Palette.brand)
        }
        .modelContainer(for: [Song.self, PracticeSession.self])
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case stage, fills, progress, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stage: return String(localized: "Stage")
        case .fills: return String(localized: "Fills")
        case .progress: return String(localized: "Progress")
        case .settings: return String(localized: "Settings")
        }
    }
    var symbol: String {
        switch self {
        case .stage: return "dot.radiowaves.left.and.right"
        case .fills: return "sparkles"
        case .progress: return "chart.bar.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerProfile.self) private var profile
    @Environment(AnalysisCenter.self) private var analysis
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]
    @SceneStorage("groovelens.tab") private var tab: AppTab = .stage

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.ground.ignoresSafeArea()
            Group {
                switch tab {
                case .stage: NavigationStack { HomeView() }
                case .fills: NavigationStack { FillsView() }
                case .progress: NavigationStack { ProgressScreen() }
                case .settings: NavigationStack { SettingsView() }
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }
            NeonTabBar(selection: $tab)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
        .task { recoverInterruptedAnalyses() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { profile.refreshStreak() }
        }
    }

    /// Songs left "analyzing" by a previous session (app quit mid-way) become retryable.
    private func recoverInterruptedAnalyses() {
        profile.refreshStreak()
        for song in songs where song.status == .analyzing && analysis.job(for: song.id) == nil {
            song.status = .failed
            song.errorMessage = String(localized: "Analysis stopped when the app closed. Tap to try again.")
        }
        try? context.save()
    }
}

struct NeonTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                Button {
                    guard selection != t else { return }
                    Haptics.select()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = t }
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            if selection == t {
                                Capsule().fill(Palette.brand).frame(width: 24, height: 3)
                                    .shadow(color: Palette.brand, radius: 6)
                                    .matchedGeometryEffect(id: "bar", in: ns)
                            } else {
                                Capsule().fill(.clear).frame(width: 24, height: 3)
                            }
                        }
                        Image(systemName: t.symbol).font(.system(size: 17, weight: .semibold))
                        Text(t.title).font(Typo.label(10)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selection == t ? Palette.text : Palette.textFaint)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(Text(t.title))
                .accessibilityIdentifier("tab-\(t.rawValue)")
                .accessibilityAddTraits(selection == t ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0x120B2C, alpha: 0.72)))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.stroke))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        }
    }
}
