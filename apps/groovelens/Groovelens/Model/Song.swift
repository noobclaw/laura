import Foundation
import SwiftData

enum SongStatus: String, Codable {
    case analyzing, ready, failed
}

@Model
final class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var tempo: Double
    var beatsPerBar: Int
    var statusRaw: String
    var progress: Double
    var stageRaw: Int
    var errorMessage: String?
    var originalFileName: String
    var bestAccuracy: Double
    var bestGradeRaw: String?
    var bestStars: Int
    var playCount: Int
    var lastPlayedAt: Date?
    var fingerprint: [Int]
    var hitCount: Int
    var sourceKindRaw: String

    init(title: String, originalFileName: String, sourceKind: ImportSourceKind) {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.duration = 0
        self.tempo = 0
        self.beatsPerBar = 4
        self.statusRaw = SongStatus.analyzing.rawValue
        self.progress = 0
        self.stageRaw = 0
        self.errorMessage = nil
        self.originalFileName = originalFileName
        self.bestAccuracy = 0
        self.bestGradeRaw = nil
        self.bestStars = 0
        self.playCount = 0
        self.lastPlayedAt = nil
        self.fingerprint = Array(repeating: -1, count: 16)
        self.hitCount = 0
        self.sourceKindRaw = sourceKind.rawValue
    }

    var status: SongStatus {
        get { SongStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var bestGrade: Grade? {
        get { bestGradeRaw.flatMap(Grade.init(rawValue:)) }
        set { bestGradeRaw = newValue?.rawValue }
    }

    var sourceKind: ImportSourceKind { ImportSourceKind(rawValue: sourceKindRaw) ?? .file }

    var files: SongFiles { SongFiles(id: id, originalFileName: originalFileName) }
}

enum ImportSourceKind: String, Codable {
    case file, video, recording
}

@Model
final class PracticeSession {
    @Attribute(.unique) var id: UUID
    var songID: UUID
    var date: Date
    var accuracy: Double
    var gradeRaw: String
    var stars: Int
    var maxCombo: Int
    var xp: Int
    var modeRaw: String
    var speed: Double
    var seconds: Double
    var rangeLabel: String

    init(songID: UUID, accuracy: Double, grade: Grade, stars: Int, maxCombo: Int, xp: Int, mode: PlayMode, speed: Double, seconds: Double, rangeLabel: String) {
        self.id = UUID()
        self.songID = songID
        self.date = .now
        self.accuracy = accuracy
        self.gradeRaw = grade.rawValue
        self.stars = stars
        self.maxCombo = maxCombo
        self.xp = xp
        self.modeRaw = mode.rawValue
        self.speed = speed
        self.seconds = seconds
        self.rangeLabel = rangeLabel
    }

    var grade: Grade { Grade(rawValue: gradeRaw) ?? .d }
}

/// On-disk layout for one song: Application Support/Songs/<uuid>/
struct SongFiles {
    let id: UUID
    let originalFileName: String

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Songs", isDirectory: true)
    }

    var directory: URL { SongFiles.root.appendingPathComponent(id.uuidString, isDirectory: true) }
    var original: URL { directory.appendingPathComponent(originalFileName) }
    var drums: URL { directory.appendingPathComponent("drums.caf") }
    var drumless: URL { directory.appendingPathComponent("drumless.caf") }
    var chart: URL { directory.appendingPathComponent("chart.json") }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        var dir = directory
        try? dir.setResourceValues(values)
    }

    func loadChart() throws -> DrumChart {
        let data = try Data(contentsOf: chart)
        return try JSONDecoder().decode(DrumChart.self, from: data)
    }

    func save(_ chart: DrumChart) throws {
        let data = try JSONEncoder().encode(chart)
        try data.write(to: self.chart, options: .atomic)
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    var hasStems: Bool {
        FileManager.default.fileExists(atPath: drums.path) && FileManager.default.fileExists(atPath: drumless.path)
    }
}
