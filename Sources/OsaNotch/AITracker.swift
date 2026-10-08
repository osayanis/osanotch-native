import Foundation
import AppKit
import ApplicationServices

class AITracker: ObservableObject {
    @Published var isGenerating: Bool = false
    @Published var currentAI: String? = nil
    
    private var timer: Timer?
    private var wasGenerating: Bool = false
    
    var onFinish: ((String) -> Void)?
    
    private var isChecking = false
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isChecking else { return }
            self.isChecking = true
            DispatchQueue.global(qos: .utility).async {
                self.checkActiveAIs()
            }
        }
    }
    
    private func checkActiveAIs() {
        guard AXIsProcessTrusted() else { return }
        
        let browsers = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"]
        let terminals = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"]
        let aiApps: [String: String] = [
            "com.google.antigravity": "Antigravity",
            "com.google.GeminiMacOS": "Gemini",
            "com.openai.chat": "ChatGPT",
            "com.anthropic.claudefordesktop": "Claude",
        ]
        
        var newlyGeneratingAI: String? = nil
        
        for app in NSWorkspace.shared.runningApplications {
            let bundleId = app.bundleIdentifier ?? ""
            let isBrowser = browsers.contains(bundleId)
            let isTerminal = terminals.contains(bundleId)
            
            if !isBrowser && !isTerminal && aiApps[bundleId] == nil { continue }
            
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var mainWindow: CFTypeRef?
            AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &mainWindow)
            
            guard let window = mainWindow as! AXUIElement? else { continue }
            
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? ""
            
            var detectingAI: String? = nil
            
            if let name = aiApps[bundleId] {
                detectingAI = name
            } else if isBrowser {
                if title.contains("Claude") { detectingAI = "Claude" }
                else if title.contains("Gemini") { detectingAI = "Gemini" }
                else if title.contains("ChatGPT") { detectingAI = "ChatGPT" }
            } else if isTerminal {
                if title.localizedCaseInsensitiveContains("claude") { detectingAI = "Claude Code" }
                else if title.localizedCaseInsensitiveContains("antigravity") { detectingAI = "Antigravity" }
                else if title.localizedCaseInsensitiveContains("codex") { detectingAI = "Codex" }
                
                if detectingAI == nil {
                    var foundAI: String? = nil
                    scanAXTree(element: window, depth: 0, maxDepth: 22) { _, _, _, val in
                        guard let text = val?.lowercased() else { return false }
                        if text.contains("claude") || text.contains("claude code") { foundAI = "Claude Code"; return true }
                        if text.contains("antigravity") { foundAI = "Antigravity"; return true }
                        return false
                    }
                    detectingAI = foundAI
                }
            }
            
            if let ai = detectingAI, scanForGenerating(window) {
                newlyGeneratingAI = ai
                break // We found one generating, no need to check others
            }
        }

        DispatchQueue.main.async {
            self.currentAI = newlyGeneratingAI ?? self.currentAI
            let isGen = newlyGeneratingAI != nil
            self.isGenerating = isGen
            
            if self.wasGenerating && !isGen, let finishedAI = self.currentAI {
                // L'IA vient de finir !
                self.onFinish?("\(finishedAI) a fini de générer.")
                self.currentAI = nil
            }
            self.wasGenerating = isGen
            self.isChecking = false
        }
    }
    
    // Indices textuels d'une génération en cours (bouton Stop, spinner, "interrupt"…).
    private static let genKeywords = [
        "stop generating", "stop response", "stop streaming", "génération en cours",
        "generating", "thinking", "esc to interrupt", "interrupt", "cancel generation",
        "arrêter la génération", "répond", "is working", "running…", "en cours d'exécution",
        "claude is thinking", "agent is thinking", "running task", "[thought]", "tool call"
    ]

    private func scanForGenerating(_ axWindow: AXUIElement) -> Bool {
        var isGen = false
        scanAXTree(element: axWindow, depth: 0, maxDepth: 22) { role, title, desc, val in
            var textParts: [String] = []
            if let t = title, !t.isEmpty { textParts.append(t) }
            if let d = desc, !d.isEmpty { textParts.append(d) }
            if let v = val, !v.isEmpty {
                // Seulement la fin du texte pour éviter de scanner tout l'historique d'un terminal
                let suffix = String(v.suffix(1000))
                textParts.append(suffix)
            }
            let text = textParts.joined(separator: " ").lowercased()
            if text.isEmpty { return false }
            
            if Self.genKeywords.contains(where: { text.contains($0) }) { isGen = true; return true }
            return false
        }
        return isGen
    }

    private func scanAXTree(element: AXUIElement, depth: Int = 0, maxDepth: Int = 22, block: (String, String?, String?, String?) -> Bool) {
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
        
        var valRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valRef)
        let val = valRef as? String
        
        if block(role, title, desc, val) { return }
        
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement] {
            for child in children {
                scanAXTree(element: child, depth: depth + 1, maxDepth: maxDepth, block: block)
            }
        }
    }
}
