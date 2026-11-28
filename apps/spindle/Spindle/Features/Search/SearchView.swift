import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var debounced = ""
    @State private var addToPlaylist: [Track]?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            let result = model.library.index.search(debounced)
            List {
                Section {
                    HStack(spacing: Theme.s2) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.sub)
                        TextField("Songs, albums, artists", text: $query)
                            .focused($focused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .accessibilityIdentifier("search-field")
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.sub) }
                                .accessibilityLabel(Text("Clear"))
                        }
                    }
                    .frame(minHeight: 44)
                    .listRowBackground(Theme.surface)
                }
                if debounced.isEmpty {
                    Section {
                        Text("Search looks through every source at once, including songs you’ve downloaded.")
                            .font(.subheadline).foregroundStyle(Theme.sub)
                            .listRowBackground(Color.clear)
                    }
                } else if result.isEmpty {
                    Section {
                        Text("Nothing matches “\(debounced)”.").foregroundStyle(Theme.sub).listRowBackground(Color.clear)
                    }
                } else {
                    if !result.artists.isEmpty {
                        Section {
                            ForEach(result.artists) { a in
                                NavigationLink(value: a) {
                                    Label(a.name, systemImage: "person.fill").foregroundStyle(Theme.ink)
                                }
                                .listRowBackground(Theme.surface)
                            }
                        } header: { Text("Artists").sectionLabel() }
                    }
                    if !result.albums.isEmpty {
                        Section {
                            ForEach(result.albums) { a in
                                NavigationLink(value: a) {
                                    HStack(spacing: Theme.s3) {
                                        VinylView(albumKey: a.id, title: a.title, artwork: model.artworkImage(albumKey: a.id), size: 40)
                                        VStack(alignment: .leading) {
                                            Text(a.title).foregroundStyle(Theme.ink).lineLimit(1)
                                            Text(a.artist).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                                        }
                                    }
                                }
                                .listRowBackground(Theme.surface)
                            }
                        } header: { Text("Albums").sectionLabel() }
                    }
                    if !result.tracks.isEmpty {
                        Section {
                            ForEach(Array(result.tracks.enumerated()), id: \.element.id) { i, t in
                                TrackRow(track: t, number: nil, subtitle: "\(t.artist) · \(t.album)") {
                                    model.player.play(result.tracks, startAt: i)
                                }
                                .contextMenu { TrackMenu(track: t, addToPlaylist: $addToPlaylist) }
                                .listRowBackground(Theme.surface)
                                .accessibilityIdentifier("search-track-\(i)")
                            }
                        } header: { Text("Songs").sectionLabel() }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Text("Search"))
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistView(artist: $0) }
            .sheet(item: Binding(get: { addToPlaylist.map(TrackBatch.init) }, set: { addToPlaylist = $0?.tracks })) {
                AddToPlaylistSheet(tracks: $0.tracks)
            }
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !Task.isCancelled { debounced = query }
            }
            .miniPlayerInset()
        }
    }
}
