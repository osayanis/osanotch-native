import WebKit
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "handler")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), configuration: cfg)
        webView.loadHTMLString("<html><body><h1>Test</h1></body></html>", baseURL: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("Evaluating JS...")
            self.webView.evaluateJavaScript("""
                navigator.mediaDevices.getDisplayMedia({video:true})
                .then(s => window.webkit.messageHandlers.handler.postMessage('OK'))
                .catch(e => window.webkit.messageHandlers.handler.postMessage('ERR: ' + e.message));
            """, completionHandler: nil)
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Message: \(message.body)")
        NSApp.terminate(nil)
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
