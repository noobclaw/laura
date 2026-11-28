import SwiftUI
import UniformTypeIdentifiers

struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var choosing = false
    @State private var importing = false
    @State private var addingWebDAV = false

    var body: some View {
        List {
            Section {
                ForEach(model.library.sources) { s in
                    NavigationLink { SourceDetailView(sourceID: s.id) } label: { SourceRow(source: s) }
                        .listRowBackground(Theme.surface)
                }
            } footer: {
                if !model.pro.isPro {
                    Text("Free: one server or folder, plus the demo shelf. Pro: as many as you like.")
                }
            }
            Section {
                Button {
                    if model.requestAddSource() { choosing = true }
                } label: {
                    Label("Add a Source", systemImage: "plus.circle.fill").font(.headline).foregroundStyle(Theme.accent)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("add-source")
                .listRowBackground(Theme.surface)
                if !model.library.sources.contains(where: { $0.kind == .demo }) {
                    Button { model.restoreDemo() } label: { Label("Bring back the demo shelf", systemImage: "music.quarternote.3") }
                        .listRowBackground(Theme.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(Text("Sources"))
        .navigationDestination(isPresented: $addingWebDAV) { AddWebDAVView() }
        .confirmationDialog(String(localized: "Add a Source", bundle: .l10n), isPresented: $choosing, titleVisibility: .visible) {
            Button("WebDAV server (Synology, QNAP, Nextcloud…)") { addingWebDAV = true }
            Button("Folder in Files (iCloud, this iPhone, SMB)") { importing = true }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.addFolder(url) }
        }
        .miniPlayerInset()
    }
}

struct SourceRow: View {
    @Environment(AppModel.self) private var model
    let source: SourceConfig

    var body: some View {
        HStack(spacing: Theme.s3) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.kind == .demo ? String(localized: "Demo shelf", bundle: .l10n) : source.name)
                    .font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                stateLine
            }
        }
        .frame(minHeight: 52)
    }

    private var icon: String {
        switch source.kind {
        case .demo: return "music.quarternote.3"
        case .webdav: return "externaldrive.connected.to.line.below"
        case .folder: return "folder"
        }
    }

    @ViewBuilder private var stateLine: some View {
        switch model.library.scanStates[source.id] ?? .idle {
        case .scanning(let n): Text("Scanning… \(n) found").font(.caption).foregroundStyle(Theme.sub)
        case .enriching(let d, let t): Text("Reading tags \(d)/\(t)").font(.caption).foregroundStyle(Theme.sub)
        case .failed(let m): Text(m).font(.caption).foregroundStyle(Theme.signal).lineLimit(2)
        case .idle: Text("\(model.library.count(of: source.id)) songs").font(.caption).foregroundStyle(Theme.sub)
        }
    }
}

struct SourceDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let sourceID: UUID
    @State private var confirmRemove = false
    @State private var freed: String?

    var body: some View {
        if let s = model.library.sources.first(where: { $0.id == sourceID }) {
            List {
                Section {
                    SourceRow(source: s)
                    if let a = s.address { LabeledContent("Address") { Text(verbatim: a).font(Theme.mono).lineLimit(1) } }
                    if let u = s.username, !u.isEmpty { LabeledContent("User") { Text(verbatim: u) } }
                    if let d = s.lastScan { LabeledContent("Last scan") { Text(d, style: .relative) } }
                    Button { model.scan(s) } label: { Label("Scan again", systemImage: "arrow.clockwise") }
                        .disabled(model.library.scanStates[s.id]?.isBusy == true)
                }
                .listRowBackground(Theme.surface)
                Section {
                    let count = model.library.offline.keys.filter { model.library.tracks[$0]?.sourceID == s.id }.count
                    LabeledContent("Downloaded songs") { Text(verbatim: String(count)).font(Theme.mono) }
                    LabeledContent("Space used") { Text(verbatim: Format.bytes(model.library.offlineBytes(of: s.id))).font(Theme.mono) }
                    Button { freed = Format.bytes(model.library.clearOffline(of: s.id)) } label: {
                        Label("Remove downloads", systemImage: "trash")
                    }
                    .disabled(count == 0)
                } header: { Text("Offline").sectionLabel() } footer: {
                    if let freed { Text("Freed \(freed).") }
                }
                .listRowBackground(Theme.surface)
                Section {
                    NavigationLink { FolderBrowser(sourceID: s.id, prefix: "") } label: { Label("Browse folders", systemImage: "folder") }
                }
                .listRowBackground(Theme.surface)
                Section {
                    Button(role: .destructive) { confirmRemove = true } label: { Label("Remove source", systemImage: "minus.circle") }
                        .accessibilityIdentifier("source-remove")
                } footer: {
                    Text("Removing a source only removes it from Spindle. Nothing on your server or in Files is deleted.")
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Text(verbatim: s.kind == .demo ? String(localized: "Demo shelf", bundle: .l10n) : s.name))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(String(localized: "Remove this source?", bundle: .l10n), isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove source and its downloads", role: .destructive) { model.removeSource(s); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            Text("This source was removed.").foregroundStyle(Theme.sub)
        }
    }
}

/// Folder view built from the songs' paths (no extra server requests).
struct FolderBrowser: View {
    @Environment(AppModel.self) private var model
    let sourceID: UUID
    let prefix: String

    var body: some View {
        let all = model.library.tracks(of: sourceID).filter { prefix.isEmpty || $0.path.hasPrefix(prefix + "/") }
        let rest = all.map { prefix.isEmpty ? $0.path : String($0.path.dropFirst(prefix.count + 1)) }
        let folders = Array(Set(rest.compactMap { $0.contains("/") ? String($0.split(separator: "/")[0]) : nil }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let files = all.filter { t in
            let r = prefix.isEmpty ? t.path : String(t.path.dropFirst(prefix.count + 1))
            return !r.contains("/")
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        List {
            ForEach(folders, id: \.self) { f in
                NavigationLink { FolderBrowser(sourceID: sourceID, prefix: prefix.isEmpty ? f : prefix + "/" + f) } label: {
                    Label { Text(verbatim: f) } icon: { Image(systemName: "folder.fill").foregroundStyle(Theme.accent) }
                }
                .listRowBackground(Theme.surface)
            }
            ForEach(Array(files.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t, number: nil, subtitle: (t.path as NSString).lastPathComponent) { model.player.play(files, startAt: i) }
                    .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: prefix.isEmpty ? "/" : (prefix as NSString).lastPathComponent))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddWebDAVView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var user = ""
    @State private var password = ""
    @State private var testing = false
    @State private var result: String?
    @State private var resultOK = false

    private var url: URL? { WebDAVAddress.normalize(address) }

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $address, prompt: Text(verbatim: "http://192.168.1.20:5005/music"))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("webdav-address")
                TextField("User name", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.username)
                SecureField("Password", text: $password).textContentType(.password)
                TextField("Name (optional)", text: $name)
            } footer: {
                Text("On Synology: install WebDAV Server in Package Center, then use port 5005 (http) or 5006 (https) and the shared folder with your music. Tip: create a read-only user for Spindle.")
            }
            Section {
                Button {
                    test()
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(url == nil || testing)
                if let result {
                    Label { Text(verbatim: result) } icon: {
                        Image(systemName: resultOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(resultOK ? Theme.accent : Theme.signal)
                    }
                    .font(.subheadline)
                }
                if !address.isEmpty && url == nil {
                    Text(SourceError.badAddress.errorDescription ?? "").font(.caption).foregroundStyle(Theme.signal)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(Text("WebDAV server"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let url, model.requestAddSource() else { return }
                    model.addWebDAV(name: name, address: url, username: user, password: password)
                    Haptics.success()
                    dismiss()
                }
                .disabled(url == nil)
                .accessibilityIdentifier("webdav-save")
            }
        }
    }

    private func test() {
        guard let url else { return }
        testing = true
        result = nil
        Task {
            let r = await AppModel.testConnection(address: url, username: user, password: password)
            testing = false
            switch r {
            case .success(let (folders, files)):
                resultOK = true
                result = String(localized: "Connected. Found \(folders) folders and \(files) songs at the top level.", bundle: .l10n)
            case .failure(let e):
                resultOK = false
                result = e.errorDescription
            }
        }
    }
}
