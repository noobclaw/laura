import Charts
import SwiftData
import SwiftUI

struct ProgressScreen: View {
    @Environment(PlayerProfile.self) private var profile
    @Environment(ProStore.self) private var store
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @State private var proReason: ProReason?
    @State private var selectedAchievement: Achievement?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(String(localized: "Progress")).font(Typo.display(28)).foregroundStyle(Palette.text).padding(.top, 14)
                levelCard
                statsGrid
                streakCalendar
                if sessions.filter({ $0.modeRaw != PlayMode.watch.rawValue }).count >= 2 { trendChart }
                skins
                achievements
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $proReason) { ProSheet(reason: $0) }
    }

    private var levelCard: some View {
        HStack(spacing: 16) {
            LevelRing(level: profile.level, progress: profile.levelProgress, size: 74)
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.title).font(Typo.display(19)).foregroundStyle(Palette.text)
                Text("\(profile.xpIntoLevel) / \(profile.xpForLevel) XP").font(Typo.hud(13)).foregroundStyle(Palette.textDim)
                Text(profile.level >= Levels.maxLevel ? String(localized: "Max level reached")
                     : String(localized: "Next title at level \(((profile.level / 5) + 1) * 5)"))
                    .font(Typo.body(12)).foregroundStyle(Palette.textFaint)
            }
            Spacer()
        }
        .glassCard()
    }

    private var statsGrid: some View {
        let minutes = Int(profile.totalPracticeSeconds / 60)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(label: String(localized: "PRACTICE"), value: minutes >= 60 ? String(format: "%.1f", Double(minutes) / 60) : "\(minutes)",
                     unit: minutes >= 60 ? String(localized: "h") : String(localized: "min"), accent: Palette.cyan)
            StatTile(label: String(localized: "RUNS"), value: "\(profile.completedRuns)", accent: Palette.brand)
            StatTile(label: String(localized: "STREAK"), value: "\(profile.streak)", unit: String(localized: "days"), accent: Palette.ember)
            StatTile(label: String(localized: "BEST STREAK"), value: "\(profile.data.bestStreak)", unit: String(localized: "days"), accent: Palette.gold)
        }
    }

    /// Last 5 weeks, Monday first.
    private var streakCalendar: some View {
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: .now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7      // 0 = Monday
        let start = cal.date(byAdding: .day, value: -(weekday + 28), to: today) ?? today
        let days = (0..<35).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let active = profile.activeDays
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let mondayFirst = Array(symbols[1...]) + [symbols[0]]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "LAST 5 WEEKS")).hudLabel()
                Spacer()
                Label(String(localized: "1 rest day a week keeps your streak"), systemImage: "moon.zzz.fill")
                    .font(Typo.body(11)).foregroundStyle(Palette.textFaint)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(mondayFirst.enumerated()), id: \.offset) { _, s in
                    Text(s).font(Typo.hud(10)).foregroundStyle(Palette.textFaint)
                }
                ForEach(days, id: \.self) { d in
                    let key = PlayerProfile.dayKey(d)
                    let on = active.contains(key)
                    let isToday = cal.isDate(d, inSameDayAs: today)
                    let future = d > today
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(on ? AnyShapeStyle(LinearGradient(colors: [Palette.ember, Palette.brand], startPoint: .top, endPoint: .bottom))
                                 : AnyShapeStyle(Color.white.opacity(future ? 0.02 : 0.06)))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(isToday ? Palette.text : .clear, lineWidth: 1.5))
                        .shadow(color: on ? Palette.ember.opacity(0.5) : .clear, radius: 5)
                }
            }
        }
        .glassCard()
    }

    private var trendChart: some View {
        let runs = Array(sessions.filter { $0.modeRaw != PlayMode.watch.rawValue }.prefix(20).reversed())
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "ACCURACY · LAST \(runs.count) RUNS")).hudLabel()
            Chart(Array(runs.enumerated()), id: \.offset) { i, s in
                AreaMark(x: .value("Run", i), y: .value("Accuracy", s.accuracy * 100))
                    .foregroundStyle(LinearGradient(colors: [Palette.brand.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Run", i), y: .value("Accuracy", s.accuracy * 100))
                    .foregroundStyle(Palette.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Run", i), y: .value("Accuracy", s.accuracy * 100))
                    .foregroundStyle(Palette.grade(s.grade))
                    .symbolSize(30)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 60, 88, 100]) { v in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(Typo.hud(10)).foregroundStyle(Palette.textFaint) }
                }
            }
            .frame(height: 150)
        }
        .glassCard()
    }

    private var skins: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "STAGE SKINS")).hudLabel()
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(StageSkin.allCases) { skin in
                        let unlocked = profile.isUnlocked(skin, pro: store.isPro)
                        let selected = profile.selectedSkin == skin
                        Button {
                            if unlocked { Haptics.select(); profile.select(skin) } else { proReason = .skins }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    LinearGradient(colors: skin.background.reversed(), startPoint: .top, endPoint: .bottom)
                                    HStack(spacing: 4) {
                                        ForEach(0..<6, id: \.self) { i in
                                            Capsule().fill(skin.laneColors[i]).frame(width: 6, height: CGFloat(16 + (i * 7) % 22))
                                                .shadow(color: skin.laneColors[i].opacity(0.8), radius: 4)
                                        }
                                    }
                                    if !unlocked {
                                        Color.black.opacity(0.5)
                                        Image(systemName: "lock.fill").foregroundStyle(Palette.gold)
                                    }
                                }
                                .frame(width: 120, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(skin.title).font(Typo.body(14, weight: .semibold)).foregroundStyle(Palette.text)
                                Text(unlocked ? (selected ? String(localized: "In use") : String(localized: "Tap to use"))
                                     : String(localized: "Level \(skin.unlockLevel) or Pro"))
                                    .font(Typo.hud(11)).foregroundStyle(selected ? Palette.brand : Palette.textFaint)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? Palette.brand.opacity(0.12) : Palette.surface))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Palette.brand : Palette.stroke, lineWidth: selected ? 1.5 : 1))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "ACHIEVEMENTS")).hudLabel()
                Spacer()
                Text("\(Achievement.all.filter { profile.hasAchievement($0.id) }.count)/\(Achievement.all.count)")
                    .font(Typo.hud(12)).foregroundStyle(Palette.textDim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(Achievement.all) { a in
                    let got = profile.hasAchievement(a.id)
                    Button { selectedAchievement = a } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Hexagon().fill(got ? AnyShapeStyle(LinearGradient(colors: [Palette.gold, Palette.ember], startPoint: .top, endPoint: .bottom))
                                                   : AnyShapeStyle(Color.white.opacity(0.06)))
                                Hexagon().stroke(got ? Palette.gold : Palette.stroke, lineWidth: 1)
                                Image(systemName: a.symbol).font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(got ? Color.black.opacity(0.75) : Palette.textFaint)
                            }
                            .frame(width: 54, height: 60)
                            .shadow(color: got ? Palette.gold.opacity(0.5) : .clear, radius: 8)
                            Text(a.title).font(Typo.body(10, weight: .medium)).foregroundStyle(got ? Palette.text : Palette.textFaint)
                                .lineLimit(2).multilineTextAlignment(.center).frame(height: 26, alignment: .top)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(Text("\(a.title), \(got ? "unlocked" : "locked"). \(a.detail)"))
                }
            }
        }
        .glassCard()
        .popover(item: $selectedAchievement) { a in
            VStack(spacing: 8) {
                Image(systemName: a.symbol).font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.gold)
                Text(a.title).font(Typo.display(16)).foregroundStyle(Palette.text)
                Text(a.detail).font(Typo.body(13)).foregroundStyle(Palette.textDim).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(width: 260)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Color(hex: 0x1A1036))
        }
    }
}

struct Hexagon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w, y: r.minY + h * 0.25))
        p.addLine(to: CGPoint(x: r.minX + w, y: r.minY + h * 0.75))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.75))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.25))
        p.closeSubpath()
        return p
    }
}
