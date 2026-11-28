import Foundation

/// Pure grouping and search over a list of tracks. Rebuilt whenever the library changes.
struct LibraryIndex {
    let albums: [Album]
    let artists: [Artist]
    let albumsByKey: [String: Album]

    init(tracks: [Track]) {
        var groups: [String: [Track]] = [:]
        for t in tracks { groups[t.albumKey, default: []].append(t) }
        var albums: [Album] = []
        albums.reserveCapacity(groups.count)
        for (key, list) in groups {
            let sorted = list.sorted(by: LibraryIndex.trackOrder)
            let first = sorted[0]
            albums.append(Album(id: key, title: first.album, artist: first.albumArtist ?? first.artist,
                                tracks: sorted, addedAt: list.map(\.addedAt).max() ?? first.addedAt))
        }
        albums.sort { a, b in
            let c = a.title.localizedStandardCompare(b.title)
            return c == .orderedSame ? a.artist.localizedStandardCompare(b.artist) == .orderedAscending : c == .orderedAscending
        }
        self.albums = albums
        self.albumsByKey = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })

        var byArtist: [String: [Album]] = [:]
        for a in albums { byArtist[a.artist, default: []].append(a) }
        self.artists = byArtist.map { Artist(name: $0.key, albums: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func trackOrder(_ a: Track, _ b: Track) -> Bool {
        switch (a.trackNumber, b.trackNumber) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.path.localizedStandardCompare(b.path) == .orderedAscending
        }
    }

    func recentlyAdded(limit: Int = 12) -> [Album] {
        Array(albums.sorted { $0.addedAt > $1.addedAt }.prefix(limit))
    }

    struct SearchResult {
        var tracks: [Track] = []
        var albums: [Album] = []
        var artists: [Artist] = []
        var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && artists.isEmpty }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    func search(_ query: String, limit: Int = 60) -> SearchResult {
        let q = LibraryIndex.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return SearchResult() }
        var r = SearchResult()
        r.artists = artists.filter { LibraryIndex.normalize($0.name).contains(q) }.prefix(10).map { $0 }
        r.albums = albums.filter { LibraryIndex.normalize($0.title).contains(q) || LibraryIndex.normalize($0.artist).contains(q) }
            .prefix(20).map { $0 }
        var tracks: [Track] = []
        outer: for a in albums {
            for t in a.tracks where LibraryIndex.normalize(t.title).contains(q) || LibraryIndex.normalize(t.artist).contains(q)
                || LibraryIndex.normalize(t.album).contains(q) {
                tracks.append(t)
                if tracks.count >= limit { break outer }
            }
        }
        r.tracks = tracks
        return r
    }
}
