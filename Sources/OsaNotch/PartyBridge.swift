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

    private func load() { ready = false; webView.load(URLRequest(url: URL(string: "https://osaparty.osalabs.fr/osanotch-party-bridge.html")!)) }

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
        DispatchQueue.main.async { self.code = ""; self.members = 0; self.mode = ""; self.phase = .idle }
        lastSent = ""
    }

    private func broadcastState() {
        guard ready, phase == .hosting || phase == .connected || phase == .joining, let m = data?.music else { return }
        let payload: [String: Any] = ["state": m.playing ? "playing" : "paused", "track": m.title, "artist": m.artist]
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
                // Ordre venu du web → piloter Apple Music local.
                switch d["state"] as? String {
                case "playing": SystemData.controlMusic("play")
                case "paused":  SystemData.controlMusic("pause")
                case "skip":    SystemData.controlMusic("next track")
                default: break
                }
            case "error": self.phase = .error
            default: break
            }
        }
    }

    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {}

    static func js(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s])
        return String(String(data: d, encoding: .utf8)!.dropFirst().dropLast())
    }
}
