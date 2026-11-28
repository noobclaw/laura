import SwiftUI

struct AlbumView: View {
    @Environment(AppModel.self) private var model
    let album: Album
    @State private var addToPlaylist: [Track]?

    /// Re-read from the index so tags arriving later update the page.
    private var live: Album { model.library.index.albumsByKey[album.id] ?? album }

    var body: some View {
        let a = live
        List {
            Section {
                VStack(spacing: Theme.s3) {
                    VinylView(albumKey: a.id, title: a.title, artwork: model.artworkImage(albumKey: a.id), size: 220,
                              highlighted: model.player.current?.albumKey == a.id)
                        .padding(.top, Theme.s2)
                    VStack(spacing: 4) {
                        Text(a.title)
                            .font(Theme.display(30, relativeTo: .title))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        NavigationLink(value: model.library.index.artists.first { $0.name == a.artist } ?? Artist(name: a.artist, albums: [a])) {
                            Text(a.artist).font(.headline).foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        Text(summary(a)).font(Theme.mono).foregroundStyle(Theme.sub)
                    }
                    HStack(spacing: Theme.s2) {
                        Button { Haptics.light(); model.player.play(a.tracks) } label: { Label("Play", systemImage: "play.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("album-play")
                        Button { Haptics.light(); model.player.play(a.tracks, shuffle: true) } label: { Label("Shuffle", systemImage: "shuffle") }
                            .buttonStyle(SecondaryButtonStyle())
                        Button { model.download(a.tracks) } label: { Image(systemName: downloadIcon(a)).frame(width: 24) }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("album-download")
                            .accessibilityLabel(Text("Download"))
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                ForEach(Array(a.tracks.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, number: t.trackNumber ?? (i + 1)) {
                        model.player.play(a.tracks, startAt: i)
                    }
                    .accessibilityIdentifier("track-\(i)")
                    .contextMenu { TrackMenu(track: t, addToPlaylist: $addToPlaylist) }
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { addToPlaylist.map(TrackBatch.init) }, set: { addToPlaylist = $0?.tracks })) {
            AddToPlaylistSheet(tracks: $0.tracks)
        }
        .miniPlayerInset()
    }

    private func summary(_ a: Album) -> String {
        let total = a.tracks.compactMap(\.duration).reduce(0, +)
        let songs = String(localized: "\(a.tracks.count) songs", bundle: .l10n)
        return total > 0 ? songs + " · " + Format.time(total) : songs
    }

    private func downloadIcon(_ a: Album) -> String {
        if a.tracks.allSatisfy({ model.isOffline($0) || !$0.isPlayable }) { return "checkmark.circle.fill" }
        if a.tracks.contains(where: { model.isQueuedForDownload($0) }) { return "arrow.down.circle.dotted" }
        return "arrow.down.circle"
    }
}

struct TrackBatch: Identifiable {
    let tracks: [Track]
    var id: String { tracks.map(\.id).joined(separator: ",") }
}

struct TrackRow: View {
    @Environment(AppModel.self) private var model
    let track: Track
    var number: Int?
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        let playing = model.player.current?.id == track.id
        Button(action: action) {
            HStack(spacing: Theme.s3) {
                Group {
                    if playing {
                        Image(systemName: model.player.isPlaying ? "waveform" : "pause.fill").foregroundStyle(Theme.signal)
                            .symbolEffect(.variableColor.iterative, isActive: model.player.isPlaying && !UIAccessibility.isReduceMotionEnabled)
                    } else if let number {
                        Text(verbatim: String(number)).font(Theme.mono).foregroundStyle(Theme.sub)
                    }
                }
                .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).foregroundStyle(track.isPlayable ? Theme.ink : Theme.sub).lineLimit(2)
                    if !track.isPlayable {
                        Text("This format can’t play on iPhone").font(.caption).foregroundStyle(Theme.signal)
                    } else if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.s2)
                if model.isOffline(track) {
                    Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(Theme.accent)
                        .accessibilityLabel(Text("Downloaded"))
                } else if model.isQueuedForDownload(track) {
                    ProgressView().controlSize(.mini)
                }
                if let d = track.duration { Text(Format.time(d)).font(Theme.mono).foregroundStyle(Theme.sub) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!track.isPlayable)
    }
}

/// Long-press menu shared by every list of songs.
struct TrackMenu: View {
    @Environment(AppModel.self) private var model
    let track: Track
    @Binding var addToPlaylist: [Track]?

    var body: some View {
        Button { model.player.playNext(track) } label: { Label("Play Next", systemImage: "text.insert") }
        Button { addToPlaylist = [track] } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
        if model.isOffline(track) {
            Button(role: .destructive) { model.removeDownload(track) } label: { Label("Remove Download", systemImage: "trash") }
        } else if track.isPlayable {
            Button { model.download([track]) } label: { Label("Download", systemImage: "arrow.down.circle") }
        }
    }
}

struct ArtistView: View {
    @Environment(AppModel.self) private var model
    let artist: Artist
    private let columns = [GridItem(.flexible(), spacing: Theme.s3), GridItem(.flexible(), spacing: Theme.s3)]

    var body: some View {
        let live = model.library.index.artists.first { $0.name == artist.name } ?? artist
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s3) {
                Text(live.name)
                    .font(Theme.display(34, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Button { model.player.play(live.albums.flatMap(\.tracks), shuffle: true) } label: {
                    Label("Shuffle all", systemImage: "shuffle")
                }
                .buttonStyle(PrimaryButtonStyle())
                LazyVGrid(columns: columns, spacing: Theme.s4) {
                    ForEach(live.albums) { a in
                        NavigationLink(value: a) { AlbumTile(album: a) }.buttonStyle(PressStyle())
                    }
                }
            }
            .padding(Theme.s3)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerInset()
    }
}

struct AddToPlaylistSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tracks: [Track]
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New playlist name", text: $newName)
                            .submitLabel(.done)
                        Button("Create") {
                            if let p = model.createPlaylist(named: newName) {
                                model.library.add(tracks.map(\.id), to: p.id)
                                Haptics.success()
                                dismiss()
                            } else {
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("playlist-create")
                    }
                }
                Section {
                    ForEach(model.library.playlists) { p in
                        Button {
                            model.library.add(tracks.map(\.id), to: p.id)
                            Haptics.success()
                            dismiss()
                        } label: {
                            HStack {
                                Text(p.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(verbatim: String(p.trackIDs.count)).font(Theme.mono).foregroundStyle(Theme.sub)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("Add to Playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
