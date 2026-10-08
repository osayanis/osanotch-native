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
        let isBrowser = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser"].contains(bundleId)
        let isTerminal = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"].contains(bundleId)
        
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
        
        if isBrowser {
            if title.contains("Claude") { detectingAI = "Claude" }
            else if title.contains("Gemini") { detectingAI = "Gemini" }
            else if title.contains("ChatGPT") { detectingAI = "ChatGPT" }
            
            // Si on est sur une IA, on cherche un bouton "Stop generating" ou équivalent (via un scan rapide ou heuristique)
            // Pour des raisons de perfs, on simule la détection via le titre (souvent "(Generating) Claude" ou similaire selon l'extension)
            // Dans une vraie implémentation, on scannerait les AXButton.
            generating = checkBrowserGenerating(axWindow)
        } else if isTerminal {
            if title.contains("claude-code") || title.contains("claude") { detectingAI = "Claude Code" }
            else if title.contains("antigravity") { detectingAI = "Antigravity" }
            else if title.contains("codex") { detectingAI = "Codex" }
            
            // Dans le terminal, la génération est souvent bloquante ou affiche un spinner.
            generating = checkTerminalGenerating(axWindow)
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
    
    private func checkBrowserGenerating(_ axWindow: AXUIElement) -> Bool {
        // Logique de scan d'accessibilité simplifiée
        var isGen = false
        scanAXTree(element: axWindow) { role, title, desc in
            let text = [title, desc].compactMap { $0 }.joined(separator: " ").lowercased()
            if text.contains("stop generating") || text.contains("arrête") || text.contains("generating") {
                isGen = true
                return true // stop scan
            }
            return false
        }
        return isGen
    }
    
    private func checkTerminalGenerating(_ axWindow: AXUIElement) -> Bool {
        // Heuristique terminal : s'il n'y a pas de prompt actif, ça tourne
        return false // à affiner
    }
    
    private func scanAXTree(element: AXUIElement, block: (String, String?, String?) -> Bool) {
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
                scanAXTree(element: child, block: block)
            }
        }
    }
}
