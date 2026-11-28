import Foundation

struct WebDAVEntry: Equatable {
    /// Path relative to the base URL, decoded, without leading/trailing "/".
    var relativePath: String
    var isCollection: Bool
    var size: Int64?
    var modified: Date?
}

/// Errors shown to the user: each one says what went wrong and what to try.
enum SourceError: Error, Equatable, LocalizedError {
    case badAddress
    case unauthorized
    case forbidden
    case notFound
    case notWebDAV
    case timeout
    case untrustedCertificate
    case offline
    case localNetworkDenied
    case folderUnavailable
    case server(Int)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .badAddress: return String(localized: "This address doesn’t look right. Try something like http://192.168.1.20:5005/music", bundle: .l10n)
        case .unauthorized: return String(localized: "The server rejected the user name or password.", bundle: .l10n)
        case .forbidden: return String(localized: "This account can’t read that folder. Check its permissions on the NAS.", bundle: .l10n)
        case .notFound: return String(localized: "That folder doesn’t exist on the server. Check the path after the port.", bundle: .l10n)
        case .notWebDAV: return String(localized: "This address isn’t a WebDAV server. On Synology, turn on WebDAV Server and use its port (5005, or 5006 for HTTPS).", bundle: .l10n)
        case .timeout: return String(localized: "The server didn’t answer. Check that your iPhone and the NAS are on the same network.", bundle: .l10n)
        case .untrustedCertificate: return String(localized: "The server’s security certificate isn’t trusted. Use http on your home network, or install the certificate on this iPhone.", bundle: .l10n)
        case .offline: return String(localized: "You’re offline. Downloaded songs still play.", bundle: .l10n)
        case .localNetworkDenied: return String(localized: "Spindle isn’t allowed to reach your home network. Turn on Local Network for Spindle in Settings.", bundle: .l10n)
        case .folderUnavailable: return String(localized: "This folder can’t be opened anymore. Remove the source and choose the folder again.", bundle: .l10n)
        case .server(let code): return String(localized: "The server answered with an error (\(code)). Try again in a moment.", bundle: .l10n)
        case .other(let message): return message
        }
    }

    static func from(status: Int) -> SourceError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 405, 501: return .notWebDAV
        default: return .server(status)
        }
    }

    static func from(_ error: Error) -> SourceError {
        if let e = error as? SourceError { return e }
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return .other(ns.localizedDescription) }
        switch ns.code {
        case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost: return .timeout
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed: return .offline
        case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid, NSURLErrorSecureConnectionFailed:
            return .untrustedCertificate
        case NSURLErrorBadURL, NSURLErrorUnsupportedURL: return .badAddress
        default:
            // The local-network prompt was declined: iOS reports it as "not connected" with this extra key.
            if let reason = ns.userInfo["_NSURLErrorNWPathKey"] as? String, reason.contains("local network") { return .localNetworkDenied }
            return .other(ns.localizedDescription)
        }
    }
}

enum WebDAVAddress {
    /// `nas.local:5005/music` -> `http://nas.local:5005/music/`. Returns nil for addresses that can't work.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        if !s.hasSuffix("/") { s += "/" }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty, host.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

/// Parses a PROPFIND multistatus reply.
final class PropfindParser: NSObject, XMLParserDelegate {
    private struct Raw { var href = ""; var collection = false; var length: Int64?; var modified: String? }
    private var items: [Raw] = []
    private var current: Raw?
    private var text = ""

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    /// `base` is the source root, `request` the folder that was listed (excluded from the result).
    static func parse(_ data: Data, base: URL, request: URL) -> [WebDAVEntry] {
        let p = PropfindParser()
        let xml = XMLParser(data: data)
        xml.shouldProcessNamespaces = true
        xml.delegate = p
        xml.parse()
        let basePath = PropfindParser.cleanPath(base.path)
        let requestPath = PropfindParser.cleanPath(request.path)
        var out: [WebDAVEntry] = []
        for raw in p.items {
            let trimmed = raw.href.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed, relativeTo: request)?.absoluteURL
                    ?? URL(string: trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "", relativeTo: request)?.absoluteURL
            else { continue }
            let path = PropfindParser.cleanPath(url.path)
            if path == requestPath { continue }
            var rel = path
            if !basePath.isEmpty, rel.hasPrefix(basePath) { rel = String(rel.dropFirst(basePath.count)) }
            rel = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !rel.isEmpty else { continue }
            let name = (rel as NSString).lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("@") || name == "#recycle" { continue }   // dot files, Synology @eaDir, recycle bin
            out.append(WebDAVEntry(relativePath: rel, isCollection: raw.collection || trimmed.hasSuffix("/"),
                                   size: raw.length, modified: raw.modified.flatMap { dateFormatter.date(from: $0) }))
        }
        return out
    }

    /// URL.path is already percent-decoded; drop the trailing slash.
    static func cleanPath(_ p: String) -> String {
        var s = p
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s == "/" ? "" : s
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "response": current = Raw()
        case "collection": current?.collection = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href": if current?.href.isEmpty == true { current?.href = value }
        case "getcontentlength": current?.length = Int64(value)
        case "getlastmodified": current?.modified = value
        case "response":
            if let c = current { items.append(c) }
            current = nil
        default: break
        }
        text = ""
    }
}

/// Minimal WebDAV client: lists folders recursively and hands out authenticated file URLs.
final class WebDAVClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let base: URL
    private let credential: URLCredential?
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    init(base: URL, username: String?, password: String?) {
        self.base = base
        if let username, !username.isEmpty {
            // .permanent lets AVPlayer answer the same challenge when it streams a file.
            credential = URLCredential(user: username, password: password ?? "", persistence: .permanent)
        } else {
            credential = nil
        }
    }

    func url(for relativePath: String) -> URL {
        var u = base
        for part in relativePath.split(separator: "/") { u.append(path: String(part), directoryHint: .notDirectory) }
        return u
    }

    func list(_ folder: URL) async throws -> [WebDAVEntry] {
        var req = URLRequest(url: folder)
        req.httpMethod = "PROPFIND"
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>
        """.utf8)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) } catch { throw SourceError.from(error) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 207 || status == 200 { return PropfindParser.parse(data, base: base, request: folder) }
        throw SourceError.from(status: status) ?? .server(status)
    }

    /// Breadth-first walk. `progress` gets the running count of music files.
    func walk(maxFolders: Int = 20_000, progress: @escaping @Sendable (Int) -> Void) async throws -> [WebDAVEntry] {
        var queue: [URL] = [base]
        var files: [WebDAVEntry] = []
        var visited = 0
        while !queue.isEmpty && visited < maxFolders {
            try Task.checkCancellation()
            let folder = queue.removeFirst()
            visited += 1
            let entries: [WebDAVEntry]
            do { entries = try await list(folder) } catch {
                if folder == base { throw error } else { continue }   // one unreadable subfolder shouldn't stop the scan
            }
            for e in entries {
                if e.isCollection {
                    var sub = base
                    for p in e.relativePath.split(separator: "/") { sub.append(path: String(p), directoryHint: .isDirectory) }
                    queue.append(sub)
                } else if AudioFormats.isAudio(e.relativePath) {
                    files.append(e)
                }
            }
            progress(files.count)
        }
        return files
    }

    /// Counts the top-level folders and music files: used by "Test connection".
    func probe() async throws -> (folders: Int, files: Int) {
        let entries = try await list(base)
        return (entries.filter(\.isCollection).count, entries.filter { !$0.isCollection && AudioFormats.isAudio($0.relativePath) }.count)
    }

    func download(_ relativePath: String, to destination: URL) async throws {
        let (tmp, response): (URL, URLResponse)
        do { (tmp, response) = try await session.download(from: url(for: relativePath)) } catch { throw SourceError.from(error) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let e = SourceError.from(status: status) { throw e }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest
                || method == NSURLAuthenticationMethodDefault else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let credential, challenge.previousFailureCount == 0 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // Register for the exact protection space so AVPlayer's own requests authenticate too.
        URLCredentialStorage.shared.setDefaultCredential(credential, for: challenge.protectionSpace)
        completionHandler(.useCredential, credential)
    }
}
