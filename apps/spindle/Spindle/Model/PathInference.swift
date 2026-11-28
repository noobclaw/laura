import Foundation

/// Builds artist / album / track number / title from a path like `Artist/Album/01 Title.flac`,
/// so a library appears the moment a folder listing arrives (tags are read later).
enum PathInference {
    struct Guess: Equatable {
        var artist: String
        var album: String
        var trackNumber: Int?
        var title: String
    }

    private static let discFolder = try! NSRegularExpression(pattern: "^(cd|disc|disk|side)\\s*[0-9a-z]{1,2}$", options: [.caseInsensitive])
    private static let discTrack = try! NSRegularExpression(pattern: "^\\d{1,2}-(\\d{1,3})\\s*[-._)]?\\s+(.+)$")
    private static let numbered = try! NSRegularExpression(pattern: "^(\\d{1,3})(?:\\s*[-._)]\\s*|\\s+)(.+)$")

    static func guess(path: String) -> Guess {
        var parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        let file = parts.popLast() ?? path
        // "CD1", "Disc 2" belong to the album above them.
        if let last = parts.last, matches(discFolder, last) { parts.removeLast() }

        let base = (file as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        var title = base
        var number: Int?
        if let m = capture(discTrack, base) {
            number = Int(m[0]); title = m[1]
        } else if let m = capture(numbered, base) {
            number = Int(m[0]); title = m[1]
        }
        title = title.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = base }

        var artist = Unknown.artist
        var album = Unknown.album
        if parts.count >= 2 {
            album = parts[parts.count - 1]
            artist = parts[parts.count - 2]
        } else if parts.count == 1 {
            let folder = parts[0]
            // "Artist - Album" in a single folder.
            if let range = folder.range(of: " - ") {
                artist = String(folder[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                album = String(folder[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                album = folder
            }
        }
        return Guess(artist: artist, album: album, trackNumber: number, title: title)
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func capture(_ re: NSRegularExpression, _ s: String) -> [String]? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        var out: [String] = []
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            out.append(String(s[r]))
        }
        return out
    }
}
