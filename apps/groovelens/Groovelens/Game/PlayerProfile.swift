import Foundation
import Observation
import SwiftUI

// MARK: - Levels

enum Levels {
    static let maxLevel = 50

    /// Total XP needed to reach `level` (level 1 = 0).
    static func xpToReach(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        var total = 0
        for n in 1..<level { total += Int(100 * pow(Double(n), 1.4)) }
        return total
    }

    static func level(forXP xp: Int) -> Int {
        var l = 1
        while l < maxLevel && xp >= xpToReach(l + 1) { l += 1 }
        return l
    }

    static func title(for level: Int) -> String {
        switch level {
        case ..<5: return String(localized: "Garage Kid", bundle: .l10n)
        case 5..<10: return String(localized: "Groove Cadet", bundle: .l10n)
        case 10..<15: return String(localized: "Pocket Keeper", bundle: .l10n)
        case 15..<20: return String(localized: "Fill Hunter", bundle: .l10n)
        case 20..<25: return String(localized: "Backbeat Boss", bundle: .l10n)
        case 25..<30: return String(localized: "Session Player", bundle: .l10n)
        case 30..<35: return String(localized: "Tour Drummer", bundle: .l10n)
        case 35..<40: return String(localized: "Session Pro", bundle: .l10n)
        case 40..<45: return String(localized: "Rhythm Architect", bundle: .l10n)
        default: return String(localized: "Groove Legend", bundle: .l10n)
        }
    }
}

// MARK: - Skins

enum StageSkin: String, Codable, CaseIterable, Identifiable {
    case neon, vintage, studio, arcade
    var id: String { rawValue }

    var title: String {
        switch self {
        case .neon: return String(localized: "Neon", bundle: .l10n)
        case .vintage: return String(localized: "Vintage", bundle: .l10n)
        case .studio: return String(localized: "Studio", bundle: .l10n)
        case .arcade: return String(localized: "Arcade", bundle: .l10n)
        }
    }

    var unlockLevel: Int {
        switch self {
        case .neon: return 1
        case .vintage: return 5
        case .studio: return 10
        case .arcade: return 15
        }
    }

    var laneColors: [Color] {
        switch self {
        case .neon: return Palette.lanes
        case .vintage: return [Color(hex: 0xF08A4B), Color(hex: 0xF2C14E), Color(hex: 0xE9DCC9), Color(hex: 0xC97C5D), Color(hex: 0x9FB38B), Color(hex: 0xD9A5B3)]
        case .studio: return [Color(hex: 0xFFB13B), Color(hex: 0xF4F1EA), Color(hex: 0x7FD1FF), Color(hex: 0xB9B4FF), Color(hex: 0x8EE3B8), Color(hex: 0xFF8FB1)]
        case .arcade: return [Color(hex: 0xFF7A2F), Color(hex: 0xFFC21A), Color(hex: 0x29B6F6), Color(hex: 0x7B5CFF), Color(hex: 0x22C58B), Color(hex: 0xFF4F8B)]
        }
    }

    var background: [Color] {
        switch self {
        case .neon: return [Color(hex: 0x07041A), Color(hex: 0x130A33)]
        case .vintage: return [Color(hex: 0x1A120C), Color(hex: 0x2B1D14)]
        case .studio: return [Color(hex: 0x0E0F11), Color(hex: 0x1D1F24)]
        case .arcade: return [Color(hex: 0x1B1035), Color(hex: 0x2B1D3D)]
        }
    }
}

// MARK: - Quests

enum QuestKind: String, Codable {
    case sectionAccuracy   // reach accuracy on a section of a song
    case speedClear        // clear any run at ≥ speed
    case tapCombo          // reach a combo in Tap mode
    case practiceMinutes   // practice for N minutes
    case fillClear         // clear a fill at ≥ 80 %
}

struct Quest: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: QuestKind
    var target: Double
    var songID: UUID?
    var songTitle: String?
    var sectionLabel: String?
    var sectionKind: SectionKind?
    var sectionOrdinal: Int?
    var progress: Double = 0
    var completed = false
    var xpReward: Int

    func matchesSection(key: String?, label: String?) -> Bool {
        if let kind = sectionKind { return key == "\(kind.rawValue)-\(sectionOrdinal ?? 1)" }
        return sectionLabel == nil || sectionLabel == label
    }

    var title: String {
        switch kind {
        case .sectionAccuracy:
            let pct = Int(target * 100)
            if let kind = sectionKind, let t = songTitle {
                let s = ChartSection.label(kind: kind, ordinal: sectionOrdinal ?? 1)
                return String(localized: "Hit \(pct)% on the \(s) of “\(t)”", bundle: .l10n)
            }
            if let s = sectionLabel, let t = songTitle {
                return String(localized: "Hit \(pct)% on the \(s) of “\(t)”", bundle: .l10n)
            }
            return String(localized: "Hit \(pct)% on any section", bundle: .l10n)
        case .speedClear:
            return String(localized: "Clear a run at \(Int(target * 100))% speed", bundle: .l10n)
        case .tapCombo:
            return String(localized: "Reach a \(Int(target))-note combo in Tap mode", bundle: .l10n)
        case .practiceMinutes:
            return String(localized: "Practice for \(Int(target)) minutes", bundle: .l10n)
        case .fillClear:
            return String(localized: "Nail a fill with 80% accuracy", bundle: .l10n)
        }
    }

    var fraction: Double { completed ? 1 : min(1, progress / max(target, 0.0001)) }
}

// MARK: - Achievements

struct Achievement: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String

    /// Computed so titles follow an in-app language switch.
    static var all: [Achievement] { [
        Achievement(id: "first_chart", title: String(localized: "First Chart", bundle: .l10n), detail: String(localized: "Chart your first song", bundle: .l10n), symbol: "music.note.list"),
        Achievement(id: "first_clear", title: String(localized: "Sound Check", bundle: .l10n), detail: String(localized: "Finish your first run", bundle: .l10n), symbol: "checkmark.seal.fill"),
        Achievement(id: "first_s", title: String(localized: "Flawless", bundle: .l10n), detail: String(localized: "Earn an S grade", bundle: .l10n), symbol: "crown.fill"),
        Achievement(id: "combo_50", title: String(localized: "In the Pocket", bundle: .l10n), detail: String(localized: "Reach a 50-note combo", bundle: .l10n), symbol: "flame.fill"),
        Achievement(id: "combo_100", title: String(localized: "Locked In", bundle: .l10n), detail: String(localized: "Reach a 100-note combo", bundle: .l10n), symbol: "bolt.fill"),
        Achievement(id: "combo_250", title: String(localized: "Metronome Heart", bundle: .l10n), detail: String(localized: "Reach a 250-note combo", bundle: .l10n), symbol: "heart.fill"),
        Achievement(id: "streak_3", title: String(localized: "Habit Forming", bundle: .l10n), detail: String(localized: "Practice 3 days in a row", bundle: .l10n), symbol: "calendar"),
        Achievement(id: "streak_7", title: String(localized: "Week of Grooves", bundle: .l10n), detail: String(localized: "Practice 7 days in a row", bundle: .l10n), symbol: "calendar.badge.checkmark"),
        Achievement(id: "streak_30", title: String(localized: "Iron Wrists", bundle: .l10n), detail: String(localized: "Practice 30 days in a row", bundle: .l10n), symbol: "medal.fill"),
        Achievement(id: "songs_5", title: String(localized: "Setlist", bundle: .l10n), detail: String(localized: "Chart 5 songs", bundle: .l10n), symbol: "square.stack.3d.up.fill"),
        Achievement(id: "full_speed", title: String(localized: "Full Tempo", bundle: .l10n), detail: String(localized: "Clear a run at 100% speed with an A or better", bundle: .l10n), symbol: "speedometer"),
        Achievement(id: "kit_mode", title: String(localized: "Real Sticks", bundle: .l10n), detail: String(localized: "Finish a run in Kit mode", bundle: .l10n), symbol: "mic.fill"),
        Achievement(id: "fill_master", title: String(localized: "Fill Master", bundle: .l10n), detail: String(localized: "Nail 10 fills", bundle: .l10n), symbol: "sparkles"),
        Achievement(id: "level_10", title: String(localized: "Pocket Keeper", bundle: .l10n), detail: String(localized: "Reach level 10", bundle: .l10n), symbol: "star.circle.fill"),
        Achievement(id: "level_25", title: String(localized: "Session Player", bundle: .l10n), detail: String(localized: "Reach level 25", bundle: .l10n), symbol: "star.square.fill"),
        Achievement(id: "hours_10", title: String(localized: "Ten Hours In", bundle: .l10n), detail: String(localized: "Practice for 10 hours total", bundle: .l10n), symbol: "clock.fill")
    ] }
}

// MARK: - Profile

/// Everything the game layer remembers. Stored as JSON in UserDefaults.
@Observable
final class PlayerProfile {
    struct Stored: Codable {
        var xp = 0
        var streak = 0
        var bestStreak = 0
        var lastActiveDay: String?
        var restTokens = 1
        var restTokenWeek: String?
        var activeDays: [String] = []
        var questDay: String?
        var quests: [Quest] = []
        var achievements: [String] = []
        var selectedSkin: StageSkin = .neon
        var analysesStarted = 0
        var completedRuns = 0
        var practiceSeconds: Double = 0
        var fillsNailed = 0
        var lastReviewPrompt: Date?
        var latencyOffset: Double = 0
        var leftHanded = false
        var clickVolume: Float = 0.8
    }

    private(set) var data: Stored
    @ObservationIgnored private let key = "groovelens.profile.v1"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Stored.self, from: raw) {
            data = s
        } else {
            data = Stored()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) { defaults.set(raw, forKey: key) }
    }

    var xp: Int { data.xp }
    var level: Int { Levels.level(forXP: data.xp) }
    var title: String { Levels.title(for: level) }
    var levelProgress: Double {
        let lo = Levels.xpToReach(level), hi = Levels.xpToReach(level + 1)
        guard hi > lo else { return 1 }
        return Double(data.xp - lo) / Double(hi - lo)
    }
    var xpIntoLevel: Int { data.xp - Levels.xpToReach(level) }
    var xpForLevel: Int { Levels.xpToReach(level + 1) - Levels.xpToReach(level) }
    var streak: Int { data.streak }
    var quests: [Quest] { data.quests }
    var selectedSkin: StageSkin { data.selectedSkin }

    func isUnlocked(_ skin: StageSkin, pro: Bool) -> Bool { pro || level >= skin.unlockLevel }
    func select(_ skin: StageSkin) { data.selectedSkin = skin; save() }

    var latencyOffset: Double {
        get { data.latencyOffset }
        set { data.latencyOffset = newValue; save() }
    }
    var leftHanded: Bool {
        get { data.leftHanded }
        set { data.leftHanded = newValue; save() }
    }
    var clickVolume: Float {
        get { data.clickVolume }
        set { data.clickVolume = newValue; save() }
    }

    var analysesStarted: Int { data.analysesStarted }
    func registerAnalysisStarted() {
        data.analysesStarted += 1
        unlock("first_chart")
        if data.analysesStarted >= 5 { unlock("songs_5") }
        save()
    }

    /// A failed analysis gives its free-song slot back (PLAN: failures don't count).
    func refundAnalysis() {
        data.analysesStarted = max(0, data.analysesStarted - 1)
        save()
    }

    func hasAchievement(_ id: String) -> Bool { data.achievements.contains(id) }

    @discardableResult
    private func unlock(_ id: String) -> Bool {
        guard !data.achievements.contains(id) else { return false }
        data.achievements.append(id)
        return true
    }

    static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func weekKey(_ date: Date = .now) -> String {
        let c = Calendar(identifier: .iso8601)
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
    }

    /// Streak value as it should be displayed today (a missed day breaks it).
    func refreshStreak(now: Date = .now) {
        let week = PlayerProfile.weekKey(now)
        if data.restTokenWeek != week { data.restTokenWeek = week; data.restTokens = 1 }
        guard let last = data.lastActiveDay, let lastDate = PlayerProfile.date(from: last) else { save(); return }
        let gap = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastDate),
                                                  to: Calendar.current.startOfDay(for: now)).day ?? 0
        if gap == 2 && data.restTokens > 0 {
            // One rest day per week keeps the streak alive.
            data.restTokens -= 1
            if let y = Calendar.current.date(byAdding: .day, value: -1, to: now) { data.lastActiveDay = PlayerProfile.dayKey(y) }
        } else if gap > 1 {
            data.streak = 0
        }
        save()
    }

    static func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    var activeDays: Set<String> { Set(data.activeDays) }
    var totalPracticeSeconds: Double { data.practiceSeconds }
    var completedRuns: Int { data.completedRuns }

    // MARK: Daily quests

    func ensureQuests(songs: [Song], charts: (Song) -> DrumChart?) {
        let today = PlayerProfile.dayKey()
        guard data.questDay != today || data.quests.isEmpty else { return }
        // Stable per-day seed (String.hashValue is randomized per launch).
        var seed: UInt64 = 0xcbf29ce484222325
        for b in today.utf8 { seed = (seed ^ UInt64(b)) &* 0x100000001b3 }
        var rng = SeededGenerator(seed: seed)
        var quests: [Quest] = []
        let ready = songs.filter { $0.status == .ready }
        if let song = ready.randomElement(using: &rng), let chart = charts(song), let section = chart.sections.randomElement(using: &rng) {
            quests.append(Quest(kind: .sectionAccuracy, target: 0.9, songID: song.id, songTitle: song.title, sectionKind: section.kind, sectionOrdinal: section.ordinal, xpReward: 150))
        } else {
            quests.append(Quest(kind: .tapCombo, target: 30, xpReward: 100))
        }
        let pool: [Quest] = [
            Quest(kind: .speedClear, target: 0.8, xpReward: 100),
            Quest(kind: .tapCombo, target: 50, xpReward: 120),
            Quest(kind: .practiceMinutes, target: 5, xpReward: 80),
            Quest(kind: .fillClear, target: 1, xpReward: 120)
        ]
        for q in pool.shuffled(using: &rng) where quests.count < 3 && !quests.contains(where: { $0.kind == q.kind }) {
            quests.append(q)
        }
        data.quests = quests
        data.questDay = today
        save()
    }

    // MARK: Results

    struct RunReport {
        var xpGained: Int
        var questXP: Int
        var levelBefore: Int
        var levelAfter: Int
        var newAchievements: [Achievement]
        var completedQuests: [Quest]
        var unlockedSkins: [StageSkin]
        var shouldAskForReview: Bool
    }

    struct RunInput {
        var songID: UUID
        var sectionLabel: String?
        var sectionKey: String? = nil
        var isFill: Bool
        var accuracy: Double
        var grade: Grade
        var maxCombo: Int
        var speed: Double
        var mode: PlayMode
        var seconds: Double
        var runXP: Int
    }

    func record(_ run: RunInput) -> RunReport {
        let levelBefore = level
        let skinsBefore = Set(StageSkin.allCases.filter { levelBefore >= $0.unlockLevel })
        var gained = run.runXP

        // Streak.
        let today = PlayerProfile.dayKey()
        if data.lastActiveDay != today {
            if let last = data.lastActiveDay, let lastDate = PlayerProfile.date(from: last),
               let gap = Calendar.current.dateComponents([.day], from: lastDate, to: PlayerProfile.date(from: today) ?? .now).day, gap == 1 {
                data.streak += 1
            } else {
                data.streak = 1
            }
            data.lastActiveDay = today
            data.bestStreak = max(data.bestStreak, data.streak)
            if !data.activeDays.contains(today) { data.activeDays.append(today) }
            if data.activeDays.count > 120 { data.activeDays.removeFirst(data.activeDays.count - 120) }
        }

        data.completedRuns += 1
        data.practiceSeconds += run.seconds
        if run.isFill && run.accuracy >= 0.8 { data.fillsNailed += 1 }

        // Quests.
        var completed: [Quest] = []
        var questXP = 0
        for i in data.quests.indices where !data.quests[i].completed {
            var q = data.quests[i]
            switch q.kind {
            case .sectionAccuracy:
                if (q.songID == nil || q.songID == run.songID) && q.matchesSection(key: run.sectionKey, label: run.sectionLabel) {
                    q.progress = max(q.progress, run.accuracy)
                }
            case .speedClear:
                if run.accuracy >= 0.6 && run.mode != .watch { q.progress = max(q.progress, run.speed) }
            case .tapCombo:
                if run.mode == .tap { q.progress = max(q.progress, Double(run.maxCombo)) }
            case .practiceMinutes:
                q.progress += run.seconds / 60
            case .fillClear:
                if run.isFill && run.accuracy >= 0.8 { q.progress = 1 }
            }
            if q.progress >= q.target - 0.0001 {
                q.completed = true
                questXP += q.xpReward
                completed.append(q)
            }
            data.quests[i] = q
        }
        gained += questXP
        data.xp += gained

        // Achievements.
        var newOnes: [String] = []
        func check(_ id: String, _ cond: Bool) { if cond && unlock(id) { newOnes.append(id) } }
        check("first_clear", run.mode != .watch)
        check("first_s", run.grade == .s && run.mode != .watch)
        check("combo_50", run.maxCombo >= 50)
        check("combo_100", run.maxCombo >= 100)
        check("combo_250", run.maxCombo >= 250)
        check("streak_3", data.streak >= 3)
        check("streak_7", data.streak >= 7)
        check("streak_30", data.streak >= 30)
        check("full_speed", run.speed >= 0.999 && run.grade >= .a && run.mode != .watch)
        check("kit_mode", run.mode == .kit)
        check("fill_master", data.fillsNailed >= 10)
        check("level_10", level >= 10)
        check("level_25", level >= 25)
        check("hours_10", data.practiceSeconds >= 36_000)

        // Review prompt: on the 3rd completed run, then at most every 90 days.
        var ask = false
        if run.mode != .watch && data.completedRuns >= 3 {
            if let last = data.lastReviewPrompt {
                ask = Date.now.timeIntervalSince(last) > 90 * 86_400
            } else {
                ask = true
            }
            if ask { data.lastReviewPrompt = .now }
        }
        save()

        let skinsAfter = Set(StageSkin.allCases.filter { level >= $0.unlockLevel })
        return RunReport(xpGained: gained, questXP: questXP, levelBefore: levelBefore, levelAfter: level,
                         newAchievements: Achievement.all.filter { newOnes.contains($0.id) },
                         completedQuests: completed,
                         unlockedSkins: StageSkin.allCases.filter { skinsAfter.contains($0) && !skinsBefore.contains($0) },
                         shouldAskForReview: ask)
    }

    #if DEBUG
    func resetForTesting() { data = Stored(); save() }
    #endif
}

/// Deterministic RNG so the day's quests don't reshuffle on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
