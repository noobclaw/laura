import SwiftUI

@main
struct SpindleApp: App {
    @State private var model: AppModel

    init() {
        // UI tests start clean: wipe stored data before any store (language, Pro, library) reads it.
        if ProcessInfo.processInfo.arguments.contains("-UITourReset") { AppModel.resetAllData() }
        _model = State(initialValue: AppModel())
    }

    /// UI tests force a scheme to screenshot both; users follow the system.
    static var forcedScheme: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITourDark") { return .dark }
        if args.contains("-UITourLight") { return .light }
        return nil
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, model.language.locale)
                .id(model.language.code)
                .tint(Theme.accent)
                .preferredColorScheme(SpindleApp.forcedScheme)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            ShelfView()
                .tabItem { Label("Shelf", systemImage: "square.stack.3d.up") }
                .tag(0)
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)
            PlaylistsView()
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
                .tag(2)
        }
        .sheet(item: $model.paywall) { reason in PaywallView(reason: reason) }
        .sheet(isPresented: $model.showNowPlaying) { NowPlayingView() }
        .overlay(alignment: .bottom) {
            if model.showReviewCard {
                ReviewCard().padding(.horizontal, Theme.s3).padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) { ToastView() }
        .animation(Theme.medium, value: model.showReviewCard)
        .alert(String(localized: "Library restored", bundle: .l10n), isPresented: Binding(
            get: { model.library.loadMessage != nil }, set: { if !$0 { model.library.loadMessage = nil } })) {
            Button("OK") { model.library.loadMessage = nil }
        } message: { Text(model.library.loadMessage ?? "") }
    }
}

/// Mini player pinned above the tab bar on every tab.
struct MiniPlayerInset: ViewModifier {
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if model.player.current != nil { MiniPlayer() }
        }
    }
}

extension View {
    func miniPlayerInset() -> some View { modifier(MiniPlayerInset()) }
}

struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @State private var spin = 0.0

    var body: some View {
        let p = model.player
        if let t = p.current {
            HStack(spacing: Theme.s3) {
                Button { model.showNowPlaying = true } label: {
                    HStack(spacing: Theme.s3) {
                        VinylView(albumKey: t.albumKey, title: t.album, artwork: model.artworkImage(albumKey: t.albumKey), size: 44,
                                  angle: .degrees(spin))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(p.status == .reconnecting ? String(localized: "Reconnecting…", bundle: .l10n) : t.artist)
                                .font(.caption).foregroundStyle(p.status == .reconnecting ? Theme.signal : Theme.sub).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("mini-player")
                .accessibilityLabel(Text("Now playing: \(t.title)"))

                Button { Haptics.light(); p.togglePlay() } label: {
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).foregroundStyle(Theme.ink).frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("mini-toggle")
                .accessibilityLabel(p.isPlaying ? Text("Pause") : Text("Play"))
                Button { p.next() } label: {
                    Image(systemName: "forward.fill").font(.body).foregroundStyle(Theme.ink).frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Next"))
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2)
            .background(Theme.surface)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    Rectangle().fill(Theme.accent)
                        .frame(width: geo.size.width * (p.duration > 0 ? min(1, p.currentTime / p.duration) : 0), height: 2)
                }
                .frame(height: 2)
            }
            .task(id: p.isPlaying) {
                guard p.isPlaying, !UIAccessibility.isReduceMotionEnabled else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    spin += 3
                }
            }
        }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let message = model.toast ?? model.player.notice
        Group {
            if let message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.s3).padding(.vertical, Theme.s2)
                    .background(Theme.ink.opacity(0.92), in: Capsule())
                    .padding(.top, Theme.s2)
                    .padding(.horizontal, Theme.s3)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        model.toast = nil
                        model.player.notice = nil
                    }
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(Theme.medium, value: message)
    }
}
