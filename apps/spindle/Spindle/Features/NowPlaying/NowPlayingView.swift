import AVKit
import SwiftUI

/// The record turns with the music; the tone arm and the ring show where you are in the song.
struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var scrubbing: Double?
    @State private var showQueue = false
    @State private var share: ShareItem?

    var body: some View {
        let p = model.player
        NavigationStack {
            if let t = p.current {
                VStack(spacing: Theme.s3) {
                    turntable(t)
                        .padding(.top, Theme.s2)
                    VStack(spacing: 4) {
                        Text(t.title)
                            .font(Theme.display(28, relativeTo: .title))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .accessibilityIdentifier("now-title")
                        Text("\(t.artist) · \(t.album)").font(.subheadline).foregroundStyle(Theme.sub).lineLimit(1)
                        if p.status == .reconnecting {
                            Label("Reconnecting to your server…", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.signal)
                        }
                    }
                    .padding(.horizontal, Theme.s3)
                    scrubber
                    transport
                    secondaryRow
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.s3)
                .background(Theme.bg.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                            .accessibilityLabel(Text("Close"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            share = ShareItem(image: ShareCards.nowPlaying(model: model, track: t),
                                              title: String(localized: "Listening on Spindle", bundle: .l10n))
                        } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }
                        .accessibilityIdentifier("now-share")
                        .accessibilityLabel(Text("Share"))
                    }
                }
                .sheet(isPresented: $showQueue) { QueueView() }
                .sheet(item: $share) { ShareSheet(item: $0) }
                .task(id: p.isPlaying) {
                    guard p.isPlaying, !reduceMotion else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 33_000_000)
                        angle += 1.1   // ≈ 33⅓ rpm feel at 30 fps
                    }
                }
            } else {
                Text("Nothing is playing").foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg.ignoresSafeArea())
            }
        }
    }

    private var progress: Double {
        let p = model.player
        let t = scrubbing ?? p.currentTime
        return p.duration > 0 ? min(1, t / p.duration) : 0
    }

    private func turntable(_ t: Track) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ProgressRing(progress: progress, lineWidth: 3)
                    .frame(width: size, height: size)
                VinylView(albumKey: t.albumKey, title: t.album, artwork: model.artworkImage(albumKey: t.albumKey), size: size - 22,
                          angle: .degrees(angle))
                ToneArm(progress: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
                    .animation(Theme.medium, value: progress)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxHeight: 340)
        .accessibilityElement()
        .accessibilityLabel(Text("Record turning, \(Int(progress * 100)) percent through the song"))
        .accessibilityIdentifier("now-turntable")
    }

    private var scrubber: some View {
        let p = model.player
        return VStack(spacing: 2) {
            Slider(value: Binding(get: { scrubbing ?? p.currentTime }, set: { scrubbing = $0 }),
                   in: 0...max(1, p.duration), onEditingChanged: { editing in
                if !editing, let s = scrubbing { p.seek(to: s); scrubbing = nil }
            })
            .accessibilityLabel(Text("Position"))
            HStack {
                Text(Format.time(scrubbing ?? p.currentTime))
                Spacer()
                Text("-" + Format.time(max(0, p.duration - (scrubbing ?? p.currentTime))))
            }
            .font(Theme.mono).foregroundStyle(Theme.sub)
        }
    }

    private var transport: some View {
        let p = model.player
        return HStack(spacing: Theme.s5) {
            Button { p.previous() } label: { Image(systemName: "backward.fill").font(.title2).frame(width: 56, height: 56) }
                .accessibilityLabel(Text("Previous"))
            Button { Haptics.light(); p.togglePlay() } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 76, height: 76)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("now-toggle")
            .accessibilityLabel(p.isPlaying ? Text("Pause") : Text("Play"))
            Button { p.next() } label: { Image(systemName: "forward.fill").font(.title2).frame(width: 56, height: 56) }
                .accessibilityLabel(Text("Next"))
        }
        .foregroundStyle(Theme.ink)
    }

    private var secondaryRow: some View {
        let p = model.player
        return HStack {
            Button { p.toggleShuffle() } label: {
                Image(systemName: "shuffle").foregroundStyle(p.queue.shuffled ? Theme.accent : Theme.sub).frame(width: 44, height: 44)
            }
            .accessibilityLabel(p.queue.shuffled ? Text("Shuffle on") : Text("Shuffle off"))
            Button { p.cycleRepeat() } label: {
                Image(systemName: p.queue.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(p.queue.repeatMode == .off ? Theme.sub : Theme.accent).frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Repeat"))
            Spacer()
            sleepMenu
            RoutePicker().frame(width: 44, height: 44).accessibilityLabel(Text("AirPlay"))
            Button { showQueue = true } label: { Image(systemName: "list.bullet").foregroundStyle(Theme.ink).frame(width: 44, height: 44) }
                .accessibilityIdentifier("now-queue")
                .accessibilityLabel(Text("Up next"))
        }
    }

    @ViewBuilder private var sleepMenu: some View {
        let p = model.player
        let active = p.sleep != .off
        if model.pro.limits.hasSleepTimer {
            Menu {
                ForEach(SleepTimer.choices, id: \.self) { m in
                    Button { p.setSleep(minutes: m) } label: { Text("\(m) minutes") }
                }
                Button { p.setSleepEndOfTrack() } label: { Text("End of this song") }
                if active { Button("Turn off", role: .destructive) { p.setSleep(minutes: nil) } }
            } label: {
                Image(systemName: active ? "moon.zzz.fill" : "moon.zzz").foregroundStyle(active ? Theme.accent : Theme.sub).frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Sleep timer"))
        } else {
            Button { _ = model.requestSleepTimer() } label: {
                Image(systemName: "moon.zzz").foregroundStyle(Theme.sub).frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("now-sleep")
            .accessibilityLabel(Text("Sleep timer"))
        }
    }
}

/// Tone arm from the top-right corner; its tip travels from the outer groove to the label.
struct ToneArm: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func path(in rect: CGRect) -> Path {
        let pivot = CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.06)
        let len = rect.width * 0.56
        let start = 122.0, end = 146.0   // degrees, measured from +x going clockwise (screen coords)
        let a = (start + (end - start) * progress) * .pi / 180
        let tip = CGPoint(x: pivot.x + CGFloat(cos(a)) * len, y: pivot.y + CGFloat(sin(a)) * len)
        var p = Path()
        p.addEllipse(in: CGRect(x: pivot.x - 7, y: pivot.y - 7, width: 14, height: 14))
        p.move(to: pivot)
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x - 6, y: tip.y + 6))
        return p
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Theme.sub)
        v.activeTintColor = UIColor(Theme.accent)
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct QueueView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = model.player
        NavigationStack {
            List {
                if let t = p.current {
                    Section {
                        TrackRow(track: t, number: nil, subtitle: t.artist) {}
                    } header: { Text("Now playing").sectionLabel() }
                    .listRowBackground(Theme.surface)
                }
                Section {
                    ForEach(Array(p.queue.upcoming.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t, number: nil, subtitle: t.artist) { p.jump(toUpcoming: i) }
                            .listRowBackground(Theme.surface)
                    }
                    .onMove { p.moveUpcoming(from: $0, to: $1) }
                    .onDelete { p.removeUpcoming(at: $0) }
                } header: { Text("Up next").sectionLabel() }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle(Text("Up next"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
