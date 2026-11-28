import Photos
import SwiftUI

struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
}

/// 1080×1350 cards. They never contain source names, addresses or paths.
@MainActor
enum ShareCards {
    static let size = CGSize(width: 360, height: 450)   // rendered at 3x

    static func render<V: View>(_ view: V) -> UIImage {
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        r.scale = 3
        return r.uiImage ?? UIImage()
    }

    struct ShelfStats: Equatable { var sources: Int; var albums: Int; var songs: Int }

    static func shelfStats(_ model: AppModel) -> ShelfStats {
        ShelfStats(sources: model.library.sources.count, albums: model.library.index.albums.count, songs: model.library.tracks.count)
    }

    static func shelf(model: AppModel) -> UIImage {
        let stats = shelfStats(model)
        let discs = model.library.sources.enumerated().map { i, s in
            // Names never appear; the generated colours use the index only.
            SpindleStack.Disc(id: s.id, name: "disc-\(i)", count: max(1, model.library.count(of: s.id)), active: i == 0)
        }
        let covers = Array(model.library.index.recentlyAdded(limit: 3))
        return render(ShelfCard(stats: stats, discs: discs, covers: covers.map { ($0.id, $0.title, model.artworkImage(albumKey: $0.id)) }))
    }

    static func nowPlaying(model: AppModel, track: Track) -> UIImage {
        let p = model.player
        let progress = p.duration > 0 ? p.currentTime / p.duration : 0
        return render(NowPlayingCard(track: track, artwork: model.artworkImage(albumKey: track.albumKey), progress: progress))
    }

    /// Lines of text a card would show; used by tests to prove no server details leak.
    static func shelfText(_ stats: ShelfStats) -> [String] {
        [String(localized: "My shelf", bundle: .l10n),
         Format.number(stats.songs), String(localized: "songs", bundle: .l10n),
         Format.number(stats.albums), String(localized: "albums", bundle: .l10n),
         Format.number(stats.sources), String(localized: "sources", bundle: .l10n)]
    }
}

private struct CardFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Spacer(minLength: 0)
            HStack {
                Text(verbatim: "SPINDLE").font(.custom("Anton-Regular", size: 22)).tracking(1.5).foregroundStyle(Color(hex: 0xECEAE3))
                Spacer()
                Text("NAS music player").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x9A9890))
            }
        }
        .padding(24)
        .background(Color(hex: 0x121315))
    }
}

private struct ShelfCard: View {
    let stats: ShareCards.ShelfStats
    let discs: [SpindleStack.Disc]
    let covers: [(String, String, UIImage?)]

    var body: some View {
        CardFrame {
            Text("My shelf").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x9A9890))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: Format.number(stats.songs)).font(.custom("Anton-Regular", size: 64)).foregroundStyle(Color(hex: 0xD9CF4A))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("songs").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0xECEAE3))
                    HStack(spacing: 14) {
                        stat(stats.albums, "albums")
                        stat(stats.sources, "sources")
                    }
                    .padding(.top, 6)
                }
                Spacer()
                SpindleStack(discs: discs).frame(width: 130, height: 150)
            }
            .padding(.top, 6)
            HStack(spacing: -18) {
                ForEach(Array(covers.enumerated()), id: \.offset) { _, c in
                    VinylView(albumKey: c.0, title: c.1, artwork: c.2, size: 96)
                }
            }
            .padding(.top, 22)
        }
    }

    private func stat(_ n: Int, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: Format.number(n)).font(.custom("Anton-Regular", size: 24)).foregroundStyle(Color(hex: 0xECEAE3))
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x9A9890))
        }
    }
}

private struct NowPlayingCard: View {
    let track: Track
    let artwork: UIImage?
    let progress: Double

    var body: some View {
        CardFrame {
            Text("Listening now").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x9A9890))
            ZStack {
                Circle().stroke(Color(hex: 0x2E3034), lineWidth: 3)
                Circle().trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(Color(hex: 0xD9CF4A), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                VinylView(albumKey: track.albumKey, title: track.album, artwork: artwork, size: 228)
            }
            .frame(width: 250, height: 250)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            Text(verbatim: track.title).font(.system(size: 24, weight: .heavy)).foregroundStyle(Color(hex: 0xECEAE3))
                .lineLimit(2).padding(.top, 18)
            Text(verbatim: track.artist).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0xD9CF4A)).lineLimit(1)
        }
    }
}

/// Share sheet with a preview, the system share panel and "Save to Photos".
struct ShareSheet: View {
    let item: ShareItem
    @Environment(\.dismiss) private var dismiss
    @State private var saved: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.s3) {
                Image(uiImage: item.image)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                    .padding(.horizontal, Theme.s4)
                    .accessibilityIdentifier("share-preview")
                    .accessibilityLabel(Text(verbatim: item.title))
                ShareLink(item: Image(uiImage: item.image), preview: SharePreview(item.title, image: Image(uiImage: item.image))) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.s3)
                Button { save() } label: { Label("Save to Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.horizontal, Theme.s3)
                if let saved { Text(verbatim: saved).font(.footnote).foregroundStyle(Theme.sub).multilineTextAlignment(.center) }
            }
            .padding(.vertical, Theme.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func save() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            Task { @MainActor in
                guard status == .authorized || status == .limited else {
                    saved = String(localized: "Spindle can’t save to Photos. Allow it in Settings › Privacy › Photos, or use Share instead.", bundle: .l10n)
                    return
                }
                UIImageWriteToSavedPhotosAlbum(item.image, nil, nil, nil)
                Haptics.success()
                saved = String(localized: "Saved to Photos.", bundle: .l10n)
            }
        }
    }
}
