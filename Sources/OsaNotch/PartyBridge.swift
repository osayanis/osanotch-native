import SwiftUI
import WebKit
import Combine

// Pont OsaParty : le notch DEVIENT le "Mac bridge" de listen-party.
// Il rejoint un salon socket.io (osaparty.osalabs.fr), diffuse l'état d'Apple Music
// (bridge-state) et applique les ordres du web (web-action) via AppleScript.
// Interopérable avec osaparty web — les autres n'ont pas besoin du notch.
final class PartyBridge: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum Phase: Equatable { case idle, loading, hosting, joining, connected, error }
    @Published var phase: Phase = .loading
    @Published var code: String = ""
    @Published var members: Int = 0
    @Published var mode: String = ""   // "host" | "guest"
    
    /// Ce que joue l'hôte (vu depuis un notch invité).
    struct RemoteMusic: Equatable {
        var title: String; var artist: String; var playing: Bool
        var position: Double = 0; var duration: Double = 0; var sampledAt = Date()
        /// Position estimée maintenant (l'hôte n'envoie qu'à chaque changement).
        func livePosition(_ now: Date = Date()) -> Double {
            let p = position + (playing ? now.timeIntervalSince(sampledAt) : 0)
            return duration > 0 ? min(p, duration) : p
        }
    }
    @Published var remoteMusic: RemoteMusic?
    @Published var remoteArtwork: NSImage?
    /// Lecture chez l'invité : il n'y a pas de flux audio (Apple Music est protégé), chaque Mac joue
    /// le morceau depuis sa propre bibliothèque Apple Music, calé sur l'hôte.
    enum LocalPlayback: Equatable { case idle, synced, missing, unavailable }
    @Published var playback: LocalPlayback = .idle
    @Published var storeURL: URL?
    private var remoteKey = ""
    private let syncQ = DispatchQueue(label: "osa.party.sync", qos: .userInitiated)
    private var syncBusy = false

    let webView: WKWebView
    private var ready = false
    private var pending: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private weak var data: SystemData?
    private var lastSent = ""

    init(data: SystemData) {
        self.data = data
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        cfg.userContentController = ucc
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        ucc.add(self, name: "osaParty")
        webView.navigationDelegate = self
        load()

        // Diffuse l'état de lecture local au salon dès qu'il change.
        data.$music
            .combineLatest(data.$artwork)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in self?.broadcastState() }
            .store(in: &cancellables)
    }

    // La page-pont relaie elle-même l'état du salon (message "remote-state").
    private func load() {
        ready = false
        webView.load(URLRequest(url: URL(string: "https://osaparty.osalabs.fr/osanotch-party-bridge.html")!))
    }

    // Même format que osaparty web : code numérique à 6 chiffres.
    static func gen() -> String { String(Int.random(in: 100000...999999)) }

    func host() {
        let c = Self.gen()
        DispatchQueue.main.async { self.code = c; self.mode = "host"; self.phase = .hosting }
        run { self.webView.evaluateJavaScript("osaParty.join(\(Self.js(c)))", completionHandler: nil) }
    }
    func join(_ c: String) {
        DispatchQueue.main.async { self.code = c; self.mode = "guest"; self.phase = .joining }
        run { self.webView.evaluateJavaScript("osaParty.join(\(Self.js(c)))", completionHandler: nil) }
    }
    func leave() {
        webView.evaluateJavaScript("osaParty.leave()", completionHandler: nil)
        DispatchQueue.main.async {
            self.code = ""; self.members = 0; self.mode = ""; self.phase = .idle
            self.remoteMusic = nil; self.remoteArtwork = nil; self.playback = .idle; self.storeURL = nil; self.remoteKey = ""
        }
        lastSent = ""
    }

    /// Invité : lecture / pause / suivant pour tout le salon (l'hôte l'applique, comme depuis le web).
    func action(_ state: String) {
        webView.evaluateJavaScript("osaParty.action && osaParty.action(\(Self.js(state)))", completionHandler: nil)
    }

    private func broadcastState() {
        // Seul l'hôte diffuse : un invité qui envoyait aussi sa musique écrasait celle de l'hôte.
        guard ready, mode == "host", phase == .hosting || phase == .connected, let m = data?.music else { return }
        // Position (arrondie à la seconde) + durée → barre de progression et paroles synchronisées côté web.
        var payload: [String: Any] = ["state": m.playing ? "playing" : "paused", "track": m.title, "artist": m.artist,
                                      "position": m.position.rounded()]
        if m.duration > 0 { payload["duration"] = m.duration.rounded() }
        guard let json = try? JSONSerialization.data(withJSONObject: payload), let s = String(data: json, encoding: .utf8) else { return }
        if s == lastSent { return }
        lastSent = s
        webView.evaluateJavaScript("osaParty.setState(\(s))", completionHandler: nil)
    }

    private func run(_ b: @escaping () -> Void) { if ready { b() } else { pending = b } }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let t = d["type"] as? String else { return }
        DispatchQueue.main.async {
            switch t {
            case "ready":
                self.ready = true; self.pending?(); self.pending = nil
                if self.phase == .loading { self.phase = .idle }
            case "joined":
                self.phase = .connected
                self.broadcastState()
            case "members":
                if let n = d["count"] as? Int { self.members = n }
            case "action":
                // Ordre venu du web → piloter Apple Music local (l'hôte seulement : l'invité suit l'état diffusé).
                guard self.mode == "host" else { break }
                switch d["state"] as? String {
                case "playing": SystemData.controlMusic("play")
                case "paused":  SystemData.controlMusic("pause")
                case "skip":    SystemData.controlMusic("next track")
                default: break
                }
            case "error": self.phase = .error
            case "remote-state":
                guard self.mode == "guest", let p = d["payload"] as? [String: Any],
                      let t = p["track"] as? String, let a = p["artist"] as? String, let st = p["state"] as? String else { break }
                let rm = RemoteMusic(title: t, artist: a, playing: st == "playing",
                                     position: (p["position"] as? NSNumber)?.doubleValue ?? 0,
                                     duration: (p["duration"] as? NSNumber)?.doubleValue ?? 0)
                self.remoteMusic = rm
                self.follow(rm)
            default: break
            }
        }
    }

    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {}

    // MARK: Invité : jouer le même morceau que l'hôte, au même endroit

    private func follow(_ rm: RemoteMusic) {
        let key = "\(rm.artist)|\(rm.title)"
        if key != remoteKey {
            remoteKey = key
            remoteArtwork = nil; storeURL = nil
            fetchRemoteInfo(rm, key: key)
            playLocally(rm, key: key)
            return
        }
        guard playback == .synced, !syncBusy, let local = data?.music, local.title == rm.title else { return }
        // Même morceau : on suit lecture / pause, et on recale si l'écart dépasse 4 s.
        let localPos = local.position + (local.playing ? Date().timeIntervalSince(data?.positionSampledAt ?? Date()) : 0)
        let target = rm.livePosition() + 0.4
        var lines: [String] = []
        if rm.playing != local.playing { lines.append(rm.playing ? "play" : "pause") }
        if abs(localPos - target) > 4 { lines.append("set player position to \(Self.num(target))") }
        guard !lines.isEmpty else { return }
        runMusic(lines.joined(separator: "\n")) { _ in }
    }

    /// Cherche le morceau dans la bibliothèque Apple Music de l'invité et le lance à la position de l'hôte.
    private func playLocally(_ rm: RemoteMusic, key: String) {
        guard SystemData.hasMusic else { playback = .unavailable; return }
        let t = Self.osaString(rm.title), a = Self.osaString(rm.artist)
        let script = """
            set r to (every track of library playlist 1 whose name is \(t) and artist contains \(a))
            if (count of r) = 0 then set r to (every track of library playlist 1 whose name is \(t))
            if (count of r) = 0 then return "missing"
            play item 1 of r
            set player position to \(Self.num(rm.livePosition() + 1))
            \(rm.playing ? "" : "pause")
            return "ok"
            """
        runMusic(script, force: true) { [weak self] out in
            guard let self, self.remoteKey == key else { return }
            self.playback = out == "ok" ? .synced : .missing
        }
    }

    private func runMusic(_ body: String, force: Bool = false, done: @escaping (String?) -> Void) {
        if syncBusy && !force { return }
        syncBusy = true
        let script = "tell application \"Music\"\n\(body)\nend tell"
        syncQ.async { [weak self] in
            let out = SystemData.runOsa(script, timeout: 8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { self?.syncBusy = false; done(out) }
        }
    }

    /// Pochette (et lien Apple Music) du morceau de l'hôte, via la recherche iTunes.
    private func fetchRemoteInfo(_ rm: RemoteMusic, key: String) {
        let q = "\(rm.artist) \(rm.title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(q)&entity=song&limit=1&country=fr") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first else { return }
            let store = (first["trackViewUrl"] as? String).flatMap(URL.init(string:))
            var img: NSImage?
            if let art = first["artworkUrl100"] as? String,
               let big = URL(string: art.replacingOccurrences(of: "100x100bb", with: "400x400bb")) {
                img = NSImage(contentsOf: big)
            }
            DispatchQueue.main.async {
                guard let self, self.remoteKey == key else { return }
                self.remoteArtwork = img; self.storeURL = store
            }
        }.resume()
    }

    /// Ouvre le morceau de l'hôte dans Apple Music (pour l'ajouter à sa bibliothèque).
    func openInMusic() {
        guard let u = storeURL else { return }
        var c = URLComponents(url: u, resolvingAgainstBaseURL: false)
        c?.scheme = "music"
        NSWorkspace.shared.open(c?.url ?? u)
    }

    static func osaString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    /// AppleScript attend un point décimal, quelle que soit la langue du Mac.
    static func num(_ d: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), max(0, d)) }

    static func js(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s])
        return String(String(data: d, encoding: .utf8)!.dropFirst().dropLast())
    }
}
