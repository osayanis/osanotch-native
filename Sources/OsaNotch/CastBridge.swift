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

    func host() {
        set(.waiting)
        let js = """
        osaCast.host = async function() {
            role = "host";
            try {
                window.localStream = await navigator.mediaDevices.getDisplayMedia({ video: true });
            } catch (e) {
                window.webkit.messageHandlers.osaCast.postMessage({ type: "error", msg: "capture écran refusée" });
                return;
            }
            newSocket();
            socket.on("connect", () => socket.emit("createRoom"));
            socket.on("roomCreated", (id) => { roomId = id; window.webkit.messageHandlers.osaCast.postMessage({ type: "code", code: id, phase: "waiting" }); });
            socket.on("ready", async () => {
                try {
                    commonPC();
                    window.localStream.getTracks().forEach((t) => pc.addTrack(t, window.localStream));
                    const offer = await pc.createOffer(); await pc.setLocalDescription(offer);
                    socket.emit("offer", { roomId, offer });
                    window.webkit.messageHandlers.osaCast.postMessage({ type: "status", phase: "live" });
                } catch (e) { window.webkit.messageHandlers.osaCast.postMessage({ type: "error", msg: "erreur webrtc" }); }
            });
            socket.on("answer", async (a) => { try { await pc.setRemoteDescription(a); } catch (e) {} });
            socket.on("ice-candidate", async (c) => { try { await pc.addIceCandidate(c); } catch (e) {} });
        };
        osaCast.host();
        """
        run { self.webView.evaluateJavaScript(js, completionHandler: nil) }
    }
    func join(_ code: String) { set(.connecting); run { self.webView.evaluateJavaScript("osaCast.join(\(Self.js(code)))", completionHandler: nil) } }
    func stop() { webView.evaluateJavaScript("osaCast.stop()", completionHandler: nil); DispatchQueue.main.async { self.code = "" }; set(.idle); load() }
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
