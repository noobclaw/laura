import SwiftUI

/// First screen: the shelf itself — the spindle of sources, recently added records, every album.
struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showSources = false
    @State private var shareImage: ShareItem?
    @State private var spin = 0.0

    private let columns = [GridItem(.flexible(), spacing: Theme.s3), GridItem(.flexible(), spacing: Theme.s3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    header
                    hero
                    if model.library.index.albums.isEmpty {
                        emptyState
                    } else {
                        recent
                        albums
                    }
                }
                .padding(.horizontal, Theme.s3)
                .padding(.bottom, Theme.s5)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistView(artist: $0) }
            .navigationDestination(isPresented: $showSources) { SourcesView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $shareImage) { ShareSheet(item: $0) }
            .miniPlayerInset()
            .task(id: model.player.isPlaying) {
                guard model.player.isPlaying, !UIAccessibility.isReduceMotionEnabled else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    spin += 0.12
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "SPINDLE")
                .font(Theme.wordmark(34))
                .tracking(1.5)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                shareImage = ShareItem(image: ShareCards.shelf(model: model), title: String(localized: "My Spindle shelf", bundle: .l10n))
            } label: {
                Image(systemName: "square.and.arrow.up").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("home-share")
            .accessibilityLabel(Text("Share"))
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("home-settings")
            .accessibilityLabel(Text("Settings"))
        }
        .foregroundStyle(Theme.ink)
        .padding(.top, Theme.s2)
    }

    private var stats: (sources: Int, albums: Int, songs: Int) {
        (model.library.sources.count, model.library.index.albums.count, model.library.tracks.count)
    }

    private var hero: some View {
        let playingSource = model.player.current?.sourceID
        let discs = model.library.sources.map { s in
            SpindleStack.Disc(id: s.id, name: s.name, count: max(1, model.library.count(of: s.id)), active: s.id == playingSource)
        }
        return Button { showSources = true } label: {
            HStack(alignment: .center, spacing: Theme.s3) {
                SpindleStack(discs: discs, spin: spin)
                    .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: Theme.s2) {
                    Text(Format.number(stats.songs))
                        .font(Theme.display(44, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("songs on \(stats.sources) sources")
                        .font(.subheadline).foregroundStyle(Theme.sub)
                    busyLine
                    HStack(spacing: 4) {
                        Text("Sources").font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.top, Theme.s1)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.s3)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("home-sources")
        .accessibilityLabel(Text("\(stats.songs) songs on \(stats.sources) sources. Open sources"))
    }

    @ViewBuilder private var busyLine: some View {
        if let busy = model.library.scanStates.values.first(where: { $0.isBusy }) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                switch busy {
                case .scanning(let n): Text("Scanning… \(n) found").font(.caption).foregroundStyle(Theme.sub)
                case .enriching(let d, let t): Text("Reading tags \(d)/\(t)").font(.caption).foregroundStyle(Theme.sub)
                default: EmptyView()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text("Bring your music in")
                .font(Theme.display(28, relativeTo: .title))
                .foregroundStyle(Theme.ink)
            Text("Add a WebDAV address from your NAS, or choose a folder in Files — including SMB servers you’ve connected there.")
                .font(.body).foregroundStyle(Theme.sub)
            HStack(spacing: Theme.s2) {
                NavigationLink { AddWebDAVView() } label: { Text("Add WebDAV") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("empty-add-webdav")
                Button { showSources = true } label: { Text("Choose a folder") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.top, Theme.s2)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text("Recently added").sectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.s3) {
                    ForEach(model.library.index.recentlyAdded()) { a in
                        NavigationLink(value: a) {
                            VStack(alignment: .leading, spacing: 6) {
                                VinylView(albumKey: a.id, title: a.title, artwork: model.artworkImage(albumKey: a.id), size: 112)
                                Text(a.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            }
                            .frame(width: 112)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    private var albums: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text("Albums").sectionLabel()
                Spacer()
                Text(Format.number(stats.albums)).font(Theme.mono).foregroundStyle(Theme.sub)
            }
            LazyVGrid(columns: columns, spacing: Theme.s4) {
                ForEach(model.library.index.albums) { a in
                    NavigationLink(value: a) { AlbumTile(album: a) }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("album-\(a.title)")
                }
            }
        }
    }
}

struct AlbumTile: View {
    @Environment(AppModel.self) private var model
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                VinylView(albumKey: album.id, title: album.title, artwork: model.artworkImage(albumKey: album.id), size: geo.size.width,
                          highlighted: model.player.current?.albumKey == album.id)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(album.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
            Text(album.artist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
