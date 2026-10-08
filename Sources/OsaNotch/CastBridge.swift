import SwiftUI
import WebKit

// Pilote le vrai moteur OsaCast web (page osanotch-cast-bridge.html) via WKWebView.
// → interopérable avec osacast.osalabs.fr. Fini le PeerJS inventé.
final class CastBridge: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    enum Phase: Equatable { case idle, loading, waiting, connecting, connected, live, error }
    @Published var phase: Phase = .loading
    @Published var code: String = ""

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
        ucc.add(self, name: "osaCast")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        load()
    }

    private func load() { ready = false; webView.load(URLRequest(url: URL(string: "https://osacast.osalabs.fr/osanotch-cast-bridge.html")!)) }

    func host() { set(.waiting); run { self.webView.evaluateJavaScript("osaCast.host()", completionHandler: nil) } }
    func join(_ code: String) { set(.connecting); run { self.webView.evaluateJavaScript("osaCast.join(\(Self.js(code)))", completionHandler: nil) } }
    func stop() { webView.evaluateJavaScript("osaCast.stop()", completionHandler: nil); DispatchQueue.main.async { self.code = "" }; set(.idle); load() }

    private func run(_ b: @escaping () -> Void) { if ready { b() } else { pending = b } }
    private func set(_ p: Phase) { DispatchQueue.main.async { self.phase = p } }

    // Autorise la capture écran (getDisplayMedia) dans le WebView
    func webView(_ w: WKWebView, requestMediaCapturePermissionFor o: WKSecurityOrigin, initiatedByFrame f: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.grant) }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let t = d["type"] as? String else { return }
        DispatchQueue.main.async {
            switch t {
            case "ready": self.ready = true; self.pending?(); self.pending = nil; if self.phase == .loading { self.phase = .idle }
            case "code": if let c = d["code"] as? String { self.code = c; self.phase = .waiting }
            case "status":
                switch d["phase"] as? String {
                case "waiting": self.phase = .waiting
                case "connecting": self.phase = .connecting
                case "connected": self.phase = .connected
                case "live": self.phase = .live
                default: break
                }
            case "error": self.phase = .error
            default: break
            }
        }
    }

    static func js(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s])
        return String(String(data: d, encoding: .utf8)!.dropFirst().dropLast())
    }
}
