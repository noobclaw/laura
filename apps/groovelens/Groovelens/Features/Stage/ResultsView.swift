import StoreKit
import SwiftData
import SwiftUI

struct ResultsView: View {
    let song: Song
    let result: StageResult
    let onRetry: () -> Void
    let onClose: () -> Void

    @Environment(PlayerProfile.self) private var profile
    @Environment(\.modelContext) private var context
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var report: PlayerProfile.RunReport?
    @State private var shown = 0.0          // 0 → 1 reveal driver
    @State private var starsShown = 0
    @State private var xpFill = 0.0
    @State private var recordedID: UUID?

    private var isWatch: Bool { result.setup.mode == .watch }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(isWatch ? String(localized: "SESSION COMPLETE") : String(localized: "RESULTS")).hudLabel(Palette.cyan)
                    .padding(.top, 24)
                Text(song.title).font(Typo.display(20)).foregroundStyle(Palette.text).multilineTextAlignment(.center).lineLimit(2)
                Text(result.setup.rangeLabel).font(Typo.hud(13)).foregroundStyle(Palette.textDim)

                if !isWatch {
                    gradeHero
                    StarsView(stars: starsShown, size: 26).animation(.spring(response: 0.3, dampingFraction: 0.5), value: starsShown)
                    counts
                    if !result.timings.isEmpty { timingMap }
                }
                xpCard
                if let report, !report.newAchievements.isEmpty || !report.completedQuests.isEmpty || !report.unlockedSkins.isEmpty {
                    unlocks(report)
                }
                VStack(spacing: 12) {
                    NeonButton(title: String(localized: "Play again"), symbol: "arrow.counterclockwise") { onRetry() }
                    Button(String(localized: "Done")) { onClose() }
                        .font(Typo.body(16, weight: .semibold)).foregroundStyle(Palette.textDim)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .onAppear(perform: recordOnce)
    }

    // MARK: Hero

    private var gradeHero: some View {
        ZStack {
            if !reduceMotion {
                RaysView(color: Palette.grade(result.grade)).frame(width: 300, height: 300).opacity(shown)
            }
            VStack(spacing: 0) {
                Text(result.grade.rawValue)
                    .font(Typo.display(120, weight: .heavy))
                    .foregroundStyle(LinearGradient(colors: [.white, Palette.grade(result.grade)], startPoint: .top, endPoint: .bottom))
                    .neonGlow(Palette.grade(result.grade), radius: 28)
                    .scaleEffect(reduceMotion ? 1 : 0.4 + 0.6 * shown)
                    .opacity(shown)
                CountingPercent(value: result.accuracy * shown)
                    .font(Typo.hud(30, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: 14) {
                    Label("\(result.maxCombo)", systemImage: "bolt.fill").foregroundStyle(Palette.gold)
                    if result.finalSpeed < 0.999 || result.setup.speedTrainer {
                        Label("\(Int((result.finalSpeed * 100).rounded()))%", systemImage: "speedometer").foregroundStyle(Palette.ember)
                    }
                    if result.passes > 0 {
                        Label("\(result.passes)", systemImage: "repeat").foregroundStyle(Palette.mint)
                    }
                }
                .font(Typo.hud(14)).padding(.top, 4)
            }
        }
        .frame(height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Grade \(result.grade.rawValue), \(Int((result.accuracy * 100).rounded())) percent, max combo \(result.maxCombo)"))
    }

    private var counts: some View {
        HStack(spacing: 8) {
            ForEach([Judgement.perfect, .great, .good, .miss], id: \.self) { j in
                StatTile(label: j.title, value: "\(result.counts[j] ?? 0)", accent: color(j))
            }
        }
    }

    private func color(_ j: Judgement) -> Color {
        switch j {
        case .perfect: return Palette.gold
        case .great: return Palette.cyan
        case .good: return Palette.mint
        case .miss: return Palette.danger
        }
    }

    /// One cell per bar: blue = early, red = late, green = in the pocket; brightness = accuracy.
    private var timingMap: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "TIMING BY BAR")).hudLabel()
                Spacer()
                HStack(spacing: 10) {
                    legend(Palette.cyan, String(localized: "Early"))
                    legend(Palette.mint, String(localized: "On it"))
                    legend(Palette.danger, String(localized: "Late"))
                }
            }
            let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(result.timings) { t in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(timingColor(t).opacity(0.25 + 0.75 * t.accuracy))
                        .frame(height: 22)
                        .overlay(Text("\(t.bar + 1)").font(Typo.hud(9)).foregroundStyle(.black.opacity(0.6)))
                }
            }
            Text(timingSummary).font(Typo.body(13)).foregroundStyle(Palette.textDim)
        }
        .glassCard()
    }

    private func legend(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(s).font(Typo.body(11)).foregroundStyle(Palette.textFaint)
        }
    }

    private func timingColor(_ t: BarTiming) -> Color {
        if t.notes == 0 { return Palette.textFaint }
        if t.meanOffset < -0.025 { return Palette.cyan }
        if t.meanOffset > 0.025 { return Palette.danger }
        return Palette.mint
    }

    private var timingSummary: String {
        let played = result.timings.filter { $0.notes > 0 }
        guard !played.isEmpty else { return "" }
        let mean = played.reduce(0) { $0 + $1.meanOffset } / Double(played.count)
        let ms = Int((abs(mean) * 1000).rounded())
        if ms <= 10 { return String(localized: "Dead in the pocket — on average within \(ms) ms.") }
        return mean < 0 ? String(localized: "You’re rushing by about \(ms) ms. Lean back.")
                        : String(localized: "You’re dragging by about \(ms) ms. Push a little.")
    }

    // MARK: XP

    private var xpCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("+\(result.xp + (report?.questXP ?? 0)) XP").font(Typo.hud(22, weight: .bold)).foregroundStyle(Palette.brand)
                Spacer()
                if let r = report, r.levelAfter > r.levelBefore {
                    Text(String(localized: "LEVEL UP!")).font(Typo.display(14, weight: .heavy)).foregroundStyle(Palette.gold)
                        .neonGlow(Palette.gold, radius: 10)
                        .scaleEffect(shown > 0.99 ? 1 : 0.5).opacity(shown > 0.99 ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.8), value: shown)
                }
            }
            HStack(spacing: 12) {
                LevelRing(level: profile.level, progress: profile.levelProgress, size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.title).font(Typo.body(14, weight: .semibold)).foregroundStyle(Palette.text)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(LinearGradient(colors: [Palette.brand, Palette.violet], startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * xpFill)
                                .shadow(color: Palette.brand.opacity(0.7), radius: 6)
                        }
                    }
                    .frame(height: 8)
                    Text("\(profile.xpIntoLevel) / \(profile.xpForLevel) XP").font(Typo.hud(11)).foregroundStyle(Palette.textFaint)
                }
            }
        }
        .glassCard()
    }

    private func unlocks(_ r: PlayerProfile.RunReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "UNLOCKED")).hudLabel(Palette.gold)
            ForEach(r.newAchievements) { a in
                unlockRow(symbol: a.symbol, color: Palette.gold, title: a.title, detail: a.detail)
            }
            ForEach(r.completedQuests) { q in
                unlockRow(symbol: "checkmark.seal.fill", color: Palette.mint, title: q.title, detail: String(localized: "Quest complete · +\(q.xpReward) XP"))
            }
            ForEach(r.unlockedSkins) { s in
                unlockRow(symbol: "paintpalette.fill", color: Palette.violet, title: String(localized: "\(s.title) stage"), detail: String(localized: "New stage skin — pick it in Progress."))
            }
        }
        .glassCard()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func unlockRow(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                .frame(width: 38, height: 38).background(Circle().fill(color.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body(14, weight: .semibold)).foregroundStyle(Palette.text)
                Text(detail).font(Typo.body(12)).foregroundStyle(Palette.textDim)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Recording

    private func recordOnce() {
        guard recordedID != result.id else { return }
        recordedID = result.id
        let input = PlayerProfile.RunInput(songID: song.id, sectionLabel: result.setup.rangeLabel, isFill: result.setup.isFill,
                                           accuracy: result.accuracy, grade: result.grade, maxCombo: result.maxCombo,
                                           speed: result.finalSpeed, mode: result.setup.mode, seconds: result.seconds, runXP: result.xp)
        let startProgress = profile.levelProgress
        let r = profile.record(input)
        report = r

        song.playCount += 1
        song.lastPlayedAt = .now
        if !isWatch && result.accuracy > song.bestAccuracy && result.finalSpeed >= 0.999 && !result.setup.isFill {
            song.bestAccuracy = result.accuracy
            song.bestGrade = result.grade
            song.bestStars = result.stars
        }
        context.insert(PracticeSession(songID: song.id, accuracy: result.accuracy, grade: result.grade, stars: result.stars,
                                       maxCombo: result.maxCombo, xp: r.xpGained, mode: result.setup.mode,
                                       speed: result.finalSpeed, seconds: result.seconds, rangeLabel: result.setup.rangeLabel))
        try? context.save()

        // Reveal choreography.
        xpFill = r.levelAfter > r.levelBefore ? 0 : startProgress
        if reduceMotion {
            shown = 1; starsShown = result.stars; xpFill = profile.levelProgress
        } else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.15)) { shown = 1 }
            for i in 0..<result.stars {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 + 0.22 * Double(i)) {
                    starsShown = i + 1
                    Haptics.hit(0.6)
                }
            }
            withAnimation(.easeOut(duration: 1.0).delay(0.9)) { xpFill = profile.levelProgress }
        }
        if !isWatch && result.grade >= .a { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Haptics.success() } }
        if r.shouldAskForReview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { requestReview() }
        }
    }
}

/// Number that counts up smoothly when its value animates.
struct CountingPercent: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text("\(String(format: "%.1f", value * 100))%").monospacedDigit()
    }
}

struct RaysView: View {
    let color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .radians(t * 0.25))
                for i in 0..<16 {
                    let a0 = Double(i) / 16 * .pi * 2
                    let a1 = a0 + .pi / 32
                    var p = Path()
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: cos(a0) * r, y: sin(a0) * r))
                    p.addLine(to: CGPoint(x: cos(a1) * r, y: sin(a1) * r))
                    p.closeSubpath()
                    g.fill(p, with: .radialGradient(Gradient(colors: [color.opacity(0.35), .clear]), center: .zero, startRadius: 0, endRadius: r))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
