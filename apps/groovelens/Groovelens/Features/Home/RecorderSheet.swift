import SwiftUI

/// Record the band (or yourself) straight into a new song.
struct RecorderSheet: View {
    let onFinished: (Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recorder = Recorder()
    @State private var song: Song?
    @State private var localError: String?

    var body: some View {
        ZStack {
            NeonBackground()
            VStack(spacing: 22) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 5).padding(.top, 10)
                HStack {
                    Text(String(localized: "Record")).font(Typo.display(22)).foregroundStyle(Palette.text)
                    Spacer()
                    Button(String(localized: "Cancel")) { cancel() }
                        .font(Typo.body(15, weight: .semibold)).foregroundStyle(Palette.textDim)
                }
                .padding(.horizontal, 20)

                Text(String(localized: "Put your iPhone near the band, not on the kit. Up to 10 minutes."))
                    .font(Typo.body(14)).foregroundStyle(Palette.textDim).multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                meter.frame(height: 120).padding(.horizontal, 20)

                Text(formatDuration(recorder.elapsed))
                    .font(Typo.hud(48, weight: .bold)).foregroundStyle(recorder.isRecording ? Palette.danger : Palette.text)
                    .monospacedDigit()

                Button { toggle() } label: {
                    ZStack {
                        Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 4).frame(width: 86, height: 86)
                        RoundedRectangle(cornerRadius: recorder.isRecording ? 8 : 34, style: .continuous)
                            .fill(Palette.danger)
                            .frame(width: recorder.isRecording ? 34 : 68, height: recorder.isRecording ? 34 : 68)
                            .shadow(color: Palette.danger.opacity(0.8), radius: 16)
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: recorder.isRecording)
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel(Text(recorder.isRecording ? "Stop recording" : "Start recording"))

                if let err = localError ?? recorder.errorMessage {
                    Text(err).font(Typo.body(13)).foregroundStyle(Palette.danger).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                Spacer()
            }
        }
        .interactiveDismissDisabled(recorder.isRecording)
        .onChange(of: recorder.isRecording) { _, on in if !on && song != nil { finalize() } }
        .onDisappear { if recorder.isRecording { cancel() } }
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(recorder.levels.enumerated()), id: \.offset) { i, v in
                Capsule()
                    .fill(LinearGradient(colors: [Palette.brand, Palette.violet], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(4, CGFloat(v) * 120))
                    .opacity(0.35 + Double(i) / Double(max(recorder.levels.count, 1)) * 0.65)
            }
        }
        .animation(.linear(duration: 0.08), value: recorder.levels)
    }

    private func toggle() {
        if recorder.isRecording {
            recorder.stop()   // onChange(isRecording) finalizes, also when the 10-minute cap stops it
        } else {
            localError = nil
            let s = Song(title: String(localized: "Recording"), originalFileName: "original.m4a", sourceKind: .recording)
            do {
                try s.files.ensureDirectory()
            } catch {
                localError = error.localizedDescription
                return
            }
            song = s
            Haptics.hit()
            recorder.start(to: s.files.original)
            if !recorder.isRecording { s.files.deleteAll(); song = nil }
        }
    }

    private func finalize() {
        guard let song else { return }
        self.song = nil
        guard recorder.elapsed >= 8 else {
            localError = String(localized: "Record at least 8 seconds so we can find the beat.")
            song.files.deleteAll()
            return
        }
        song.title = String(localized: "Recording — \(Date.now.formatted(date: .abbreviated, time: .shortened))")
        Haptics.success()
        dismiss()
        onFinished(song)
    }

    private func cancel() {
        let s = song
        song = nil          // prevents finalize() from firing on the stop below
        recorder.discard()
        s?.files.deleteAll()
        dismiss()
    }
}
