import SwiftUI
import WebKit

// Pilote le vrai moteur OsaCast web (page osanotch-cast-bridge.html) via WKWebView.
// → interopérable avec osacast.osalabs.fr. Fini le PeerJS inventé.
final class CastBridge: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    enum Phase: Equatable { case idle, loading, waiting, connecting, connected, live, reconnecting, error }
    @Published var phase: Phase = .loading
    @Published var code: String = ""
    /// Pourquoi la diffusion n'a pas démarré (affiché dans la boîte Diffuser).
    @Published var errorText: String?

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

    // La page-pont gère tout : capture, session, et reconnexion après une coupure (même code).
    /// Diffuser : WebKit refuse la capture d'écran à une page qui n'a pas le focus (erreur muette,
    /// pas de salon). On donne donc le focus à la page, on attend qu'il y soit arrivé, puis on capture.
    func host() {
        errorText = nil
        set(.waiting)
        // Sans « Enregistrement de l'écran », WebKit échoue sans rien montrer : macOS demande ici.
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        run { self.focusThenCapture(tries: 60) }
    }

    private func focusThenCapture(tries: Int) {
        if let w = webView.window {
            w.makeKeyAndOrderFront(nil)
            if w.firstResponder !== webView { w.makeFirstResponder(webView) }
        }
        webView.evaluateJavaScript("document.hasFocus() && !!(navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia)") { [weak self] r, _ in
            guard let self else { return }
            if (r as? Bool) == true || tries <= 0 {
                self.webView.evaluateJavaScript("osaCast.host()", completionHandler: nil)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focusThenCapture(tries: tries - 1) }
            }
        }
    }
    func join(_ code: String) { set(.connecting); run { self.webView.evaluateJavaScript("osaCast.join(\(Self.js(code)))", completionHandler: nil) } }
    func stop() { webView.evaluateJavaScript("osaCast.stop()", completionHandler: nil); DispatchQueue.main.async { self.code = ""; self.errorText = nil }; set(.idle); load() }
    // Relance la lecture après un repli/dépli du notch (le WebView détaché peut mettre la vidéo en pause)
    func resume() { webView.evaluateJavaScript("(function(){var v=document.getElementById('v'); if(v){v.muted=true; v.play().catch(function(){});}})()", completionHandler: nil) }

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
                case "reconnecting": self.phase = .reconnecting
                default: break
                }
            case "error":
                self.phase = .error
                let msg = d["msg"] as? String ?? "erreur"
                if msg.contains("capture") {
                    self.errorText = CGPreflightScreenCaptureAccess()
                        ? "Capture refusée (\(d["detail"] as? String ?? msg))"
                        : "Autorise OsaNotch dans Réglages › Confidentialité › Enregistrement de l'écran"
                } else { self.errorText = msg }
            default: break
            }
        }
    }

    static func js(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s])
        return String(String(data: d, encoding: .utf8)!.dropFirst().dropLast())
    }
}
