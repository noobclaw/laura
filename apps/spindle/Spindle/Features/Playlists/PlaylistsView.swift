import SwiftUI

struct PlaylistsView: View {
    @Environment(AppModel.self) private var model
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if model.pro.limits.canAddPlaylist(existing: model.library.playlists.count) {
                            newName = ""
                            naming = true
                        } else {
                            model.paywall = .playlists
                        }
                    } label: {
                        Label("New Playlist", systemImage: "plus.circle.fill").font(.headline).foregroundStyle(Theme.accent)
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("playlists-new")
                    .listRowBackground(Theme.surface)
                }
                if model.library.playlists.isEmpty {
                    Section {
                        Text("Long-press any song and choose Add to Playlist, or make an empty playlist here.")
                            .font(.subheadline).foregroundStyle(Theme.sub).listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(model.library.playlists) { p in
                            NavigationLink(value: p) {
                                HStack(spacing: Theme.s3) {
                                    PlaylistStack(tracks: model.library.tracks(in: p))
                                    VStack(alignment: .leading) {
                                        Text(p.name).font(.headline).foregroundStyle(Theme.ink)
                                        Text("\(p.trackIDs.count) songs").font(.caption).foregroundStyle(Theme.sub)
                                    }
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                        .onDelete { offsets in
                            for o in offsets { model.library.deletePlaylist(model.library.playlists[o].id) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Text("Playlists"))
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlistID: $0.id) }
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistView(artist: $0) }
            .alert(String(localized: "New Playlist", bundle: .l10n), isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Create") { _ = model.createPlaylist(named: newName) }
                Button("Cancel", role: .cancel) {}
            }
            .miniPlayerInset()
        }
    }
}

/// Three overlapping records from the playlist's albums.
struct PlaylistStack: View {
    @Environment(AppModel.self) private var model
    let tracks: [Track]
    var body: some View {
        let keys = Array(NSOrderedSet(array: tracks.map(\.albumKey)).array.compactMap { $0 as? String }.prefix(3))
        ZStack(alignment: .leading) {
            if keys.isEmpty {
                VinylView(albumKey: "empty", title: "", size: 44)
            }
            ForEach(Array(keys.enumerated()), id: \.offset) { i, k in
                VinylView(albumKey: k, title: tracks.first { $0.albumKey == k }?.album ?? "", artwork: model.artworkImage(albumKey: k), size: 44)
                    .offset(x: CGFloat(i) * 12)
            }
        }
        .frame(width: 70, alignment: .leading)
    }
}

struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var model
    let playlistID: UUID
    @State private var renaming = false
    @State private var name = ""
    @State private var addToPlaylist: [Track]?

    var body: some View {
        if let p = model.library.playlists.first(where: { $0.id == playlistID }) {
            let tracks = model.library.tracks(in: p)
            List {
                Section {
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        Text(p.name).font(Theme.display(32, relativeTo: .largeTitle)).foregroundStyle(Theme.ink).lineLimit(2)
                        Text("\(tracks.count) songs").font(Theme.mono).foregroundStyle(Theme.sub)
                        HStack(spacing: Theme.s2) {
                            Button { model.player.play(tracks) } label: { Label("Play", systemImage: "play.fill") }
                                .buttonStyle(PrimaryButtonStyle()).disabled(tracks.isEmpty)
                            Button { model.player.play(tracks, shuffle: true) } label: { Label("Shuffle", systemImage: "shuffle") }
                                .buttonStyle(SecondaryButtonStyle()).disabled(tracks.isEmpty)
                            Button { model.download(tracks) } label: { Image(systemName: "arrow.down.circle").frame(width: 24) }
                                .buttonStyle(SecondaryButtonStyle()).disabled(tracks.isEmpty)
                                .accessibilityLabel(Text("Download"))
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t, number: i + 1, subtitle: t.artist) { model.player.play(tracks, startAt: i) }
                            .contextMenu { TrackMenu(track: t, addToPlaylist: $addToPlaylist) }
                            .listRowBackground(Theme.surface)
                    }
                    .onDelete { model.library.removeFromPlaylist(p.id, at: $0) }
                    .onMove { model.library.movePlaylistTracks(p.id, from: $0, to: $1) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { name = p.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                        EditButton()
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel(Text("More"))
                }
            }
            .alert(String(localized: "Rename Playlist", bundle: .l10n), isPresented: $renaming) {
                TextField("Name", text: $name)
                Button("Save") { model.library.renamePlaylist(p.id, to: name) }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: Binding(get: { addToPlaylist.map(TrackBatch.init) }, set: { addToPlaylist = $0?.tracks })) {
                AddToPlaylistSheet(tracks: $0.tracks)
            }
            .miniPlayerInset()
        } else {
            Text("This playlist was deleted.").foregroundStyle(Theme.sub)
        }
    }
}
