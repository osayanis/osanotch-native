import AppKit
import SQLite3

// Notifications de Messages et Mail : lues dans la base du Centre de notifications de macOS
// (celle qu'affiche macOS lui-même : expéditeur, aperçu, conversation). Il faut l'« Accès
// complet au disque ». Pas de sondage permanent : on surveille le journal de la base (WAL),
// qui grossit à chaque notification, et une relecture lente sert seulement de filet.
final class NotificationFeed: ObservableObject {
    /// Applis suivies (identifiants en minuscules, comme dans la base).
    static let apps: [String: OsaNotif.Source] = ["com.apple.mobilesms": .messages, "com.apple.mail": .mail]
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    @Published private(set) var needsAccess = false
    var onNotif: ((OsaNotif) -> Void)?

    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2")
    private let q = DispatchQueue(label: "osa.notifs", qos: .utility)
    private var db: OpaquePointer?
    private var lastID: Int64 = -1
    private var watcher: DispatchSourceFileSystemObject?
    private var fallback: Timer?
    private var pollQueued = false

    func start() {
        q.async { self.connect() }
        // Filet de sécurité (journal remplacé pendant un « checkpoint », accès accordé entre-temps…)
        fallback = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.q.async { self?.db == nil ? self?.connect() : self?.poll() }
        }
        fallback?.tolerance = 5
    }

    // MARK: Base

    private func connect() {
        let path = dir.appendingPathComponent("db").path
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let id = Self.maxID(handle) else {
            sqlite3_close(handle)
            setAccess(false)
            return
        }
        sqlite3_busy_timeout(handle, 250)
        db = handle
        lastID = id                       // seulement ce qui arrive à partir de maintenant
        setAccess(true)
        watch()
    }

    private func setAccess(_ ok: Bool) {
        DispatchQueue.main.async { if self.needsAccess == ok { self.needsAccess = !ok } }
    }

    private static func maxID(_ db: OpaquePointer?) -> Int64? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : nil
    }

    /// Surveille le journal WAL (écrit à chaque notification) ; à défaut la base elle-même.
    private func watch() {
        watcher?.cancel()
        let wal = dir.appendingPathComponent("db-wal").path
        let target = FileManager.default.fileExists(atPath: wal) ? wal : dir.appendingPathComponent("db").path
        let fd = open(target, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: q)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if !src.data.isDisjoint(with: [.delete, .rename]) {
                // Journal recréé : on se rebranche sur le nouveau fichier
                self.q.asyncAfter(deadline: .now() + 0.3) { self.watch(); self.poll() }
            } else {
                self.queuePoll()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    /// Plusieurs écritures arrivent en rafale pour une seule notification : une seule lecture.
    private func queuePoll() {
        guard !pollQueued else { return }
        pollQueued = true
        q.asyncAfter(deadline: .now() + 0.15) { self.pollQueued = false; self.poll() }
    }

    private func poll() {
        guard let db else { return }
        let sql = """
            SELECT r.rec_id, a.identifier, r.data FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id
            """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            // Accès retiré, base remplacée… : on repart de zéro au prochain passage du filet
            sqlite3_close(db); self.db = nil; watcher?.cancel(); watcher = nil
            return
        }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, lastID)
        var found: [OsaNotif] = []
        while sqlite3_step(st) == SQLITE_ROW {
            lastID = max(lastID, sqlite3_column_int64(st, 0))
            guard let raw = sqlite3_column_text(st, 1) else { continue }
            let app = String(cString: raw).lowercased()
            guard let source = Self.apps[app],
                  let bytes = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(st, 2)))
            if let n = Self.parse(data, source: source) { found.append(n) }
        }
        guard !found.isEmpty else { return }
        DispatchQueue.main.async { found.forEach { self.onNotif?($0) } }
    }

    /// Contenu d'une notification : plist binaire, clé « req » (titl, subt, body).
    static func parse(_ data: Data, source: OsaNotif.Source) -> OsaNotif? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let req = plist["req"] as? [String: Any] else { return nil }
        let title = (req["titl"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = (req["subt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (req["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !body.isEmpty else { return nil }
        switch source {
        case .mail:
            // Mail : titre = expéditeur, sous-titre = objet, corps = début du message
            return OsaNotif(source: .mail, title: title.isEmpty ? "Mail" : title,
                            body: subtitle.isEmpty ? body : subtitle)
        default:
            // Messages : titre = expéditeur (ou groupe), corps = texte
            return OsaNotif(source: source, title: title.isEmpty ? "Messages" : title,
                            body: subtitle.isEmpty || subtitle == title ? body : "\(subtitle) : \(body)")
        }
    }
}

/// Icônes des applis, lues une fois.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(_ bundleID: String) -> NSImage? {
        if let i = cache[bundleID] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = i
        return i
    }
}
