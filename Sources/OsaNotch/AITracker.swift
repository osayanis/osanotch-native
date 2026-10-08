import Foundation
import AppKit
import ApplicationServices

class AITracker: ObservableObject {
    @Published var isGenerating: Bool = false
    @Published var currentAI: String? = nil
    
    private var timer: Timer?
    private var wasGenerating: Bool = false
    
    var onFinish: ((String) -> Void)?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkActiveAIs()
        }
    }
    
    private func checkActiveAIs() {
        guard AXIsProcessTrusted() else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        let bundleId = app.bundleIdentifier ?? ""
        let isBrowser = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"].contains(bundleId)
        let isTerminal = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"].contains(bundleId)
        // Applications IA de bureau (Antigravity, Gemini, ChatGPT, etc.)
        let aiApps: [String: String] = [
            "com.google.antigravity": "Antigravity",
            "com.google.GeminiMacOS": "Gemini",
            "com.openai.chat": "ChatGPT",
            "com.anthropic.claudefordesktop": "Claude",
        ]

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard let window = focusedWindow else { return }
        let axWindow = window as! AXUIElement

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""

        var detectingAI: String? = nil
        var generating = false

        if let name = aiApps[bundleId] {
            detectingAI = name
            generating = scanForGenerating(axWindow)
        } else if isBrowser {
            if title.contains("Claude") { detectingAI = "Claude" }
            else if title.contains("Gemini") { detectingAI = "Gemini" }
            else if title.contains("ChatGPT") { detectingAI = "ChatGPT" }
            if detectingAI != nil { generating = scanForGenerating(axWindow) }
        } else if isTerminal {
            if title.localizedCaseInsensitiveContains("claude") { detectingAI = "Claude Code" }
            else if title.localizedCaseInsensitiveContains("antigravity") { detectingAI = "Antigravity" }
            else if title.localizedCaseInsensitiveContains("codex") { detectingAI = "Codex" }
            if detectingAI != nil { generating = scanForGenerating(axWindow) }
        }

        DispatchQueue.main.async {
            self.currentAI = detectingAI
            self.isGenerating = generating
            
            if self.wasGenerating && !generating && detectingAI != nil {
                // L'IA vient de finir !
                self.onFinish?("\(detectingAI!) a fini de générer.")
            }
            self.wasGenerating = generating
        }
    }
    
    // Indices textuels d'une génération en cours (bouton Stop, spinner, "interrupt"…).
    private static let genKeywords = [
        "stop generating", "stop response", "stop streaming", "génération en cours",
        "generating", "thinking", "esc to interrupt", "interrupt", "cancel generation",
        "arrêter la génération", "répond", "is working", "running…", "en cours d'exécution",
    ]

    private func scanForGenerating(_ axWindow: AXUIElement) -> Bool {
        var isGen = false
        scanAXTree(element: axWindow, depth: 0, maxDepth: 22) { role, title, desc in
            let text = [title, desc].compactMap { $0 }.joined(separator: " ").lowercased()
            if text.isEmpty { return false }
            if Self.genKeywords.contains(where: { text.contains($0) }) { isGen = true; return true }
            return false
        }
        return isGen
    }

    private func scanAXTree(element: AXUIElement, depth: Int = 0, maxDepth: Int = 22, block: (String, String?, String?) -> Bool) {
        if depth > maxDepth { return }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""
        
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String
        
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        let desc = descRef as? String
        
        if block(role, title, desc) { return }
        
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement] {
            for child in children {
                scanAXTree(element: child, depth: depth + 1, maxDepth: maxDepth, block: block)
            }
        }
    }
}
