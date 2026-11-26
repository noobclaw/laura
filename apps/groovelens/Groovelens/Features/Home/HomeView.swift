import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A picked video, copied into tmp so AVFoundation can read it.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @Environment(PlayerProfile.self) private var profile
    @Environment(AnalysisCenter.self) private var analysis
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]

    @State private var showFileImporter = false
    @State private var showVideoPicker = false
    @State private var videoItem: PhotosPickerItem?
    @State private var showRecorder = false
    @State private var proReason: ProReason?
    @State private var analyzingSong: Song?
    @State private var importError: String?
    @State private var path = NavigationPath()
    @State private var openedSong: Song?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                hero
                questsCard
                tracks
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openedSong) { song in SongDetailView(song: song) }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importFile(url, kind: .file) }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showVideoPicker, selection: $videoItem, matching: .videos)
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                        importFile(movie.url, kind: .video)
                    }
                } catch {
                    importError = error.localizedDescription
                }
                videoItem = nil
            }
        }
        .sheet(isPresented: $showRecorder) {
            RecorderSheet { song in
                analysis.analyzeRecording(song: song, context: context, profile: profile)
                analyzingSong = song
            }
        }
        .sheet(item: $analyzingSong) { song in
            AnalysisSheet(song: song) { opened in
                analyzingSong = nil
                if opened { openedSong = song }
            }
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .sheet(item: $proReason) { reason in ProSheet(reason: reason) }
        .alert(String(localized: "Couldn’t import"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .task {
            // UI tour (CI screenshots): seed a synthesized demo song through the real import + analysis path.
            if ProcessInfo.processInfo.arguments.contains("-UITour"), songs.isEmpty,
               let url = try? DemoAudio.makeDemoFile() {
                importFile(url, kind: .file)
            }
        }
        .task(id: songs.count) {
            profile.ensureQuests(songs: songs) { try? $0.files.loadChart() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            LevelRing(level: profile.level, progress: profile.levelProgress)
            VStack(alignment: .leading, spacing: 3) {
                Text("GROOVELENS").font(Typo.display(15, weight: .bold)).tracking(0.6).foregroundStyle(Palette.text)
                Text(String(localized: "LV \(profile.level) · \(profile.title)"))
                    .font(Typo.hud(12)).foregroundStyle(Palette.textDim).lineLimit(1)
            }
            Spacer()
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ember)
                    Text("\(profile.streak)").font(Typo.hud(17, weight: .bold)).foregroundStyle(Palette.ember)
                        .contentTransition(.numericText())
                }
                Text(String(localized: "STREAK")).hudLabel(size: 9)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(profile.streak) day streak"))
        }
        .padding(.top, 6)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            DemoHighway(colors: profile.selectedSkin.laneColors)
                .frame(height: 230)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.32),
                                             .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(.horizontal, -16)
            HStack(spacing: 16) {
                Menu {
                    Button { startImport { showFileImporter = true } } label: { Label(String(localized: "Audio file"), systemImage: "doc.fill") }
                    Button { startImport { showVideoPicker = true } } label: { Label(String(localized: "Video from Photos"), systemImage: "video.fill") }
                    Button { startImport { requestRecording() } } label: { Label(String(localized: "Record now"), systemImage: "mic.fill") }
                } label: {
                    ZStack {
                        Circle().stroke(Palette.brand.opacity(0.6), lineWidth: 2).frame(width: 84, height: 84)
                            .modifier(PulseRing())
                        Circle()
                            .fill(LinearGradient(colors: [Palette.brand, Palette.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 74, height: 74)
                            .overlay(Circle().strokeBorder(.white.opacity(0.3)))
                            .shadow(color: Palette.brand.opacity(0.7), radius: 22)
                        Image(systemName: "plus").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel(Text("Chart a new song"))
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "Drop any song.")).font(Typo.display(20)).foregroundStyle(Palette.text)
                    Text(String(localized: "We pull the drums out and build your track — right on this iPhone."))
                        .font(Typo.body(13)).foregroundStyle(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    if !store.isPro {
                        Text(String(localized: "\(max(0, ProStore.freeSongLimit - profile.analysesStarted)) free songs left"))
                            .font(Typo.hud(12)).foregroundStyle(Palette.gold)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: Quests

    private var questsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "DAILY QUESTS")).hudLabel(Palette.cyan)
                Spacer()
                Text(String(localized: "Resets at midnight")).font(Typo.body(11)).foregroundStyle(Palette.textFaint)
            }
            ForEach(profile.quests) { q in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: q.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(q.completed ? Palette.mint : Palette.textFaint)
                        Text(q.title).font(Typo.body(14, weight: .semibold)).foregroundStyle(q.completed ? Palette.textDim : Palette.text)
                            .strikethrough(q.completed, color: Palette.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text("+\(q.xpReward) XP").font(Typo.hud(11)).foregroundStyle(Palette.textDim)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: [Palette.cyan, Palette.violet], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * q.fraction)
                                .shadow(color: Palette.cyan.opacity(0.7), radius: 6)
                        }
                    }
                    .frame(height: 6)
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: q.fraction)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .glassCard()
    }

    // MARK: Tracks

    private var tracks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Tracks")).font(Typo.display(17)).foregroundStyle(Palette.text)
                Spacer()
                if !songs.isEmpty {
                    Text("\(songs.count)").font(Typo.hud(13)).foregroundStyle(Palette.textFaint)
                }
            }
            if songs.isEmpty {
                EmptyStateView(symbol: "music.note",
                               title: String(localized: "Your stage is empty"),
                               message: String(localized: "Tap + and pick a song, a rehearsal video, or record your band. Charts appear here."))
                    .glassCard()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(songs) { song in
                        SongRow(song: song, job: analysis.job(for: song.id))
                            .accessibilityIdentifier("song-row")
                            .accessibilityValue(Text(verbatim: song.statusRaw))
                            .onTapGesture { open(song) }
                            .contextMenu {
                                if song.status == .failed {
                                    Button { retry(song) } label: { Label(String(localized: "Try again"), systemImage: "arrow.clockwise") }
                                }
                                Button(role: .destructive) { delete(song) } label: { Label(String(localized: "Delete"), systemImage: "trash") }
                            }
                            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: songs.map(\.id))
            }
        }
    }

    // MARK: Actions

    private func startImport(_ go: () -> Void) {
        if store.canAnalyzeAnotherSong(started: profile.analysesStarted) {
            go()
        } else {
            proReason = .songLimit
        }
    }

    private func requestRecording() {
        switch MicPermission.current {
        case .granted: showRecorder = true
        case .undetermined:
            Task {
                if await MicPermission.request() { showRecorder = true }
                else { importError = String(localized: "Microphone access is off. You can turn it on in Settings › Groovelens.") }
            }
        case .denied:
            importError = String(localized: "Microphone access is off. You can turn it on in Settings › Groovelens.")
        }
    }

    private func importFile(_ url: URL, kind: ImportSourceKind) {
        let title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "import-", with: "")
        let display = kind == .video ? String(localized: "Video — \(Date.now.formatted(date: .abbreviated, time: .shortened))") : title
        do {
            let song = try analysis.importAndAnalyze(source: url, kind: kind, title: display, context: context, profile: profile)
            analyzingSong = song
        } catch {
            importError = error.localizedDescription
        }
    }

    private func open(_ song: Song) {
        Haptics.tap()
        switch song.status {
        case .ready: openedSong = song
        case .analyzing: analyzingSong = song
        case .failed: retry(song)
        }
    }

    private func retry(_ song: Song) {
        guard FileManager.default.fileExists(atPath: song.files.original.path) else {
            importError = String(localized: "The original audio for this song is missing. Delete it and import again.")
            return
        }
        guard store.canAnalyzeAnotherSong(started: profile.analysesStarted) else { proReason = .songLimit; return }
        analysis.retry(song: song, context: context)
        analyzingSong = song
    }

    private func delete(_ song: Song) {
        analysis.cancel(songID: song.id)
        song.files.deleteAll()
        withAnimation { context.delete(song) }
        try? context.save()
    }
}

struct PulseRing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.45 : 0.95)
            .opacity(on ? 0 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

struct SongRow: View {
    let song: Song
    let job: AnalysisJob?

    var body: some View {
        HStack(spacing: 12) {
            switch song.status {
            case .ready:
                GradeBadge(grade: song.bestGrade, size: 44)
            case .analyzing:
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 3)
                    Circle().trim(from: 0, to: job?.progress ?? song.progress)
                        .stroke(Palette.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((job?.progress ?? song.progress) * 100))").font(Typo.hud(12, weight: .bold)).foregroundStyle(Palette.gold)
                }
                .frame(width: 44, height: 44)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18)).foregroundStyle(Palette.danger)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Palette.danger.opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(Typo.body(15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Group {
                    switch song.status {
                    case .ready:
                        HStack(spacing: 6) {
                            Text("\(Int(song.tempo.rounded())) BPM · \(song.beatsPerBar)/4 · \(formatDuration(song.duration))")
                            if song.bestStars > 0 { StarsView(stars: song.bestStars, size: 9) }
                        }
                    case .analyzing:
                        Text((job?.stage ?? AnalysisStage(rawValue: song.stageRaw) ?? .isolating).title)
                    case .failed:
                        Text(song.errorMessage ?? String(localized: "Analysis failed")).lineLimit(1)
                    }
                }
                .font(Typo.hud(12)).foregroundStyle(Palette.textDim)
            }
            Spacer(minLength: 6)
            if song.status == .ready {
                FingerprintView(cells: song.fingerprint, cell: 5)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.stroke)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
