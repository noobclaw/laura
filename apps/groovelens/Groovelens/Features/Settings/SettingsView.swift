import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(ProStore.self) private var store
    @Environment(PlayerProfile.self) private var profile
    @State private var proReason: ProReason?
    @State private var showCalibration = false
    @State private var showLicenses = false

    var body: some View {
        @Bindable var profile = profile
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(String(localized: "Settings")).font(Typo.display(28)).foregroundStyle(Palette.text).padding(.top, 14)

                proCard

                section(String(localized: "PLAY")) {
                    Toggle(isOn: $profile.leftHanded) {
                        row("hand.raised.fill", String(localized: "Left-handed layout"), String(localized: "Mirrors the lanes and pads."), Palette.violet)
                    }
                    Divider().overlay(Palette.stroke)
                    VStack(alignment: .leading, spacing: 8) {
                        row("metronome.fill", String(localized: "Click volume"), nil, Palette.cyan)
                        Slider(value: $profile.clickVolume, in: 0...1).tint(Palette.cyan)
                    }
                    Divider().overlay(Palette.stroke)
                    Button { showCalibration = true } label: {
                        HStack {
                            row("timer", String(localized: "Timing calibration"),
                                String(localized: "Current offset: \(Int((profile.latencyOffset * 1000).rounded())) ms"), Palette.gold)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.textFaint)
                        }
                    }
                }

                section(String(localized: "PRIVACY")) {
                    row("lock.shield.fill", String(localized: "Everything stays on this iPhone"),
                        String(localized: "Songs are analyzed on device. Nothing is uploaded, there are no accounts and no tracking."), Palette.mint)
                }

                section(String(localized: "ABOUT")) {
                    HStack {
                        row("info.circle.fill", String(localized: "Version"), nil, Palette.textDim)
                        Spacer()
                        Text(appVersion).font(Typo.hud(13)).foregroundStyle(Palette.textDim)
                    }
                    Divider().overlay(Palette.stroke)
                    Button { showLicenses = true } label: {
                        HStack {
                            row("doc.text.fill", String(localized: "Fonts & licenses"), nil, Palette.textDim)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.textFaint)
                        }
                    }
                }
                Text(String(localized: "Automatic transcription can miss or mislabel hits. Use the chart editor to fix anything that looks wrong."))
                    .font(Typo.body(12)).foregroundStyle(Palette.textFaint).padding(.horizontal, 4)
            }
            .tint(Palette.brand)
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $proReason) { ProSheet(reason: $0) }
        .sheet(isPresented: $showCalibration) { CalibrationSheet() }
        .sheet(isPresented: $showLicenses) { LicensesView() }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GROOVELENS PRO").font(Typo.display(15, weight: .heavy)).foregroundStyle(store.isPro ? Palette.gold : Palette.text)
                Spacer()
                if store.isPro { Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.gold) }
            }
            Text(store.isPro ? String(localized: "Unlocked. Every feature is yours.")
                 : String(localized: "Unlimited songs, Kit mode, speed trainer, every fill, exports and all stages."))
                .font(Typo.body(14)).foregroundStyle(Palette.textDim)
            if !store.isPro {
                NeonButton(title: store.displayPrice.map { String(localized: "Unlock Pro — \($0)") } ?? String(localized: "Unlock Pro"),
                           symbol: "lock.open.fill") { proReason = .settings }
            }
            Button {
                Task { await store.restore() }
            } label: {
                HStack(spacing: 6) {
                    if store.isRestoring { ProgressView().controlSize(.small) }
                    Text(String(localized: "Restore purchases"))
                }
                .font(Typo.body(14, weight: .semibold)).foregroundStyle(Palette.textDim)
            }
            .disabled(store.isRestoring)
            if let m = store.message { Text(m).font(Typo.body(12)).foregroundStyle(Palette.textDim) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Palette.brand.opacity(0.22), Palette.violet.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.brand.opacity(0.45)))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).hudLabel().padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) { content() }.glassCard()
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String?, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body(15, weight: .medium)).foregroundStyle(Palette.text)
                if let detail { Text(detail).font(Typo.body(12)).foregroundStyle(Palette.textDim).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

// MARK: - Calibration

/// Plays a steady click; the player taps along; the median offset becomes the timing correction.
@MainActor
@Observable
final class ClickCalibrator {
    static let bpm = 100.0
    static let clicks = 16

    private(set) var running = false
    private(set) var offsets: [Double] = []
    private(set) var beat = -1

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var firstClickHost: Double = 0
    @ObservationIgnored private var timer: Timer?

    var period: Double { 60 / ClickCalibrator.bpm }
    var result: Double? {
        guard offsets.count >= 6 else { return nil }
        let s = offsets.sorted()
        return s[s.count / 2]
    }

    func start() {
        stop()
        offsets = []
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
            if player.engine == nil { engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: mono) }
            guard let hi = PlaybackEngine.makeClick(format: mono, frequency: 1760, amplitude: 0.9),
                  let lo = PlaybackEngine.makeClick(format: mono, frequency: 1320, amplitude: 0.7) else { return }
            try engine.start()
            let sr = mono.sampleRate
            for i in 0..<ClickCalibrator.clicks {
                let at = AVAudioTime(sampleTime: AVAudioFramePosition(Double(i) * period * sr), atRate: sr)
                player.scheduleBuffer(i % 4 == 0 ? hi : lo, at: at, options: [], completionHandler: nil)
            }
            let lead = 0.3
            let hostStart = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: lead)
            player.play(at: AVAudioTime(hostTime: hostStart))
            firstClickHost = AVAudioTime.seconds(forHostTime: hostStart) + session.outputLatency
            running = true
            let t = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } catch {
            running = false
        }
    }

    private func tick() {
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let b = Int(floor((now - firstClickHost) / period))
        if b != beat { beat = b }
        if now - firstClickHost > Double(ClickCalibrator.clicks) * period + 0.3 { stop() }
    }

    func tap() {
        guard running else { return }
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let rel = (now - firstClickHost) / period
        let nearest = rel.rounded()
        guard nearest >= 2, nearest < Double(ClickCalibrator.clicks) else { return }   // skip the first two clicks
        let off = (rel - nearest) * period
        if abs(off) < 0.2 { offsets.append(off) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
        engine.stop()
        running = false
    }
}

struct CalibrationSheet: View {
    @Environment(PlayerProfile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var cal = ClickCalibrator()
    @State private var flash = false

    var body: some View {
        ZStack {
            NeonBackground()
            VStack(spacing: 20) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 5).padding(.top, 10)
                Text(String(localized: "Timing calibration")).font(Typo.display(22)).foregroundStyle(Palette.text)
                Text(String(localized: "Use the headphones or speaker you play with. Tap the big pad exactly on each click."))
                    .font(Typo.body(14)).foregroundStyle(Palette.textDim).multilineTextAlignment(.center).padding(.horizontal, 30)

                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(cal.running && cal.beat >= 0 && cal.beat % 4 == i ? Palette.brand : Color.white.opacity(0.1))
                            .frame(width: 14, height: 14)
                            .shadow(color: Palette.brand.opacity(cal.beat % 4 == i ? 0.9 : 0), radius: 8)
                    }
                }

                Button {
                    cal.tap()
                    Haptics.hit(0.7)
                    flash = true
                    withAnimation(.easeOut(duration: 0.25)) { flash = false }
                } label: {
                    Circle()
                        .fill(RadialGradient(colors: [Palette.brand.opacity(flash ? 0.9 : 0.5), Palette.violet.opacity(0.3)], center: .center, startRadius: 0, endRadius: 120))
                        .overlay(Circle().strokeBorder(Palette.brand, lineWidth: 2))
                        .overlay(Text(cal.running ? String(localized: "TAP") : "").font(Typo.display(26, weight: .heavy)).foregroundStyle(.white))
                        .frame(width: 220, height: 220)
                        .shadow(color: Palette.brand.opacity(0.6), radius: flash ? 30 : 14)
                }
                .buttonStyle(.plain)
                .disabled(!cal.running)

                if let r = cal.result, !cal.running {
                    VStack(spacing: 6) {
                        Text("\(r >= 0 ? "+" : "")\(Int((r * 1000).rounded())) ms").font(Typo.hud(36, weight: .bold)).foregroundStyle(Palette.gold)
                        Text(r >= 0 ? String(localized: "You tap a little after the click. We’ll correct for it.")
                                    : String(localized: "You tap a little ahead of the click. We’ll correct for it."))
                            .font(Typo.body(13)).foregroundStyle(Palette.textDim).multilineTextAlignment(.center)
                    }
                    NeonButton(title: String(localized: "Save"), symbol: "checkmark") {
                        profile.latencyOffset = r
                        Haptics.success()
                        dismiss()
                    }
                    .padding(.horizontal, 30)
                } else if !cal.running {
                    if !cal.offsets.isEmpty {
                        Text(String(localized: "Not enough taps landed near the clicks. Try again."))
                            .font(Typo.body(13)).foregroundStyle(Palette.danger)
                    }
                    NeonButton(title: String(localized: "Start"), symbol: "play.fill") { cal.start() }.padding(.horizontal, 30)
                } else {
                    Text(String(localized: "\(cal.offsets.count) taps")).font(Typo.hud(14)).foregroundStyle(Palette.textDim)
                }
                Button(String(localized: "Reset to 0 ms")) { profile.latencyOffset = 0; dismiss() }
                    .font(Typo.body(13)).foregroundStyle(Palette.textFaint)
                Spacer()
            }
        }
        .onDisappear { cal.stop() }
    }
}

struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private func text(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(String(localized: "Groovelens uses the Unbounded and Chakra Petch typefaces under the SIL Open Font License 1.1."))
                        .font(Typo.body(14)).foregroundStyle(Palette.text)
                    Text(String(localized: "Drum separation uses harmonic–percussive median filtering (Fitzgerald, 2010). Beat tracking follows Ellis (2007)."))
                        .font(Typo.body(14)).foregroundStyle(Palette.textDim)
                    ForEach(["OFL-Unbounded", "OFL-ChakraPetch"], id: \.self) { name in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name).font(Typo.hud(13, weight: .bold)).foregroundStyle(Palette.gold)
                            Text(text(name)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.textDim)
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.ground)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } }
            }
            .navigationTitle(String(localized: "Licenses"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
