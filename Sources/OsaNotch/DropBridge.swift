import SwiftUI
import WebKit

// Pilote le pont WebRTC (page osanotch-bridge.html) via un WKWebView caché.
// Réutilise le moteur OsaDrop web → interopérable avec le site et internet.
final class DropBridge: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum Phase: Equatable { case idle, loading, waiting, connecting, connected, transferring(Double), done(String), failed }
    @Published var phase: Phase = .loading

    let webView: WKWebView
    private var ready = false
    private var pending: (() -> Void)?

    override init() {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        cfg.userContentController = ucc
        cfg.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        ucc.add(self, name: "osa")
        webView.navigationDelegate = self
        load()
    }

    private func load() {
        ready = false
        webView.load(URLRequest(url: URL(string: "https://osadrop.osalabs.fr/osanotch-bridge.html")!))
    }

    func send(fileURL: URL, code: String) {
        guard let data = try? Data(contentsOf: fileURL) else { set(.failed); return }
        let b64 = data.base64EncodedString()
        set(.waiting)
        run { self.webView.evaluateJavaScript("osaBridge.send(\(Self.js(b64)),\(Self.js(fileURL.lastPathComponent)),\(Self.js(code)))", completionHandler: nil) }
    }
    func receive(code: String) {
        set(.waiting)
        run { self.webView.evaluateJavaScript("osaBridge.receive(\(Self.js(code)))", completionHandler: nil) }
    }
    func reset() { set(.idle); load() }   // recharge la page = état propre pour la prochaine fois

    private func run(_ block: @escaping () -> Void) { if ready { block() } else { pending = block } }
    private func set(_ p: Phase) { DispatchQueue.main.async { self.phase = p } }

    func webView(_ w: WKWebView, didFinish nav: WKNavigation!) { /* ready arrive via message "ready" */ }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let t = d["type"] as? String else { return }
        DispatchQueue.main.async {
            switch t {
            case "ready": self.ready = true; self.pending?(); self.pending = nil; if self.phase == .loading { self.phase = .idle }
            case "status":
                switch d["phase"] as? String {
                case "waiting": self.phase = .waiting
                case "connecting": self.phase = .connecting
                case "connected": self.phase = .connected
                case "sent": self.phase = .done("Envoyé ✓")
                default: break
                }
            case "progress": self.phase = .transferring(d["p"] as? Double ?? 0)
            case "received":
                if let name = d["name"] as? String, let b64 = d["b64"] as? String, let data = Data(base64Encoded: b64) {
                    let dest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
                    try? data.write(to: dest)
                    self.phase = .done("Reçu dans Téléchargements ✓")
                } else { self.phase = .failed }
            case "error": self.phase = .failed
            default: break
            }
        }
    }

    static func js(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s])
        return String(String(data: d, encoding: .utf8)!.dropFirst().dropLast()) // JSON-encode puis retire les crochets
    }
}

// Hôte invisible : garde le WebView dans la hiérarchie pour qu'il tourne vraiment.
struct HiddenWeb: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ v: WKWebView, context: Context) {}
}
