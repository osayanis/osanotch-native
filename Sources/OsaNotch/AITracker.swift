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
    
    private var noGenTicks = 0

    private func checkActiveAIs() {
        guard AXIsProcessTrusted() else { return }
        
        let browsers = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"]
        let terminals = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u7i", "com.cursor.mac"]
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
            
            if let ai = detectingAI, detectGenerating(window) {
                newlyGeneratingAI = ai
                break // une IA en génération suffit
            }
        }

        DispatchQueue.main.async {
            let isGen = newlyGeneratingAI != nil
            
            if isGen {
                self.noGenTicks = 0
                self.currentAI = newlyGeneratingAI
                self.isGenerating = true
                self.wasGenerating = true
            } else {
                self.noGenTicks += 1
                // Il faut 3 ticks (3×2 s = 6 s) sans génération pour valider la fin.
                if self.wasGenerating && self.noGenTicks >= 3 {
                    if let finishedAI = self.currentAI {
                        self.onFinish?("\(finishedAI) a terminé ✅")
                    }
                    self.currentAI = nil
                    self.isGenerating = false
                    self.wasGenerating = false
                }
            }
            self.isChecking = false
        }
    }
    
    // Signaux SPÉCIFIQUES d'une génération en cours — présents uniquement pendant que
    // l'IA travaille (pas dans la barre d'état inactive type "⏵⏵ auto mode on").
    private static let genSignals = [
        "esc to interrupt",            // Claude Code (en train de générer)
        "stop generating", "stop responding", "stop response", "stop streaming", // web Claude/ChatGPT/Gemini
        "arrêter la génération", "génération en cours",
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", // spinners braille CLI
        "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"
    ]

    // L'IA est-elle en train de générer ? (true dès qu'un signal est trouvé)
    private func detectGenerating(_ axWindow: AXUIElement) -> Bool {
        var gen = false
        scanAXTree(element: axWindow, depth: 0, maxDepth: 22) { _, title, desc, val in
            var parts: [String] = []
            if let t = title, !t.isEmpty { parts.append(t) }
            if let d = desc, !d.isEmpty { parts.append(d) }
            if let v = val, !v.isEmpty { parts.append(String(v.suffix(1200))) }
            let text = parts.joined(separator: "\n").lowercased()
            if text.isEmpty { return false }
            if Self.genSignals.contains(where: { text.contains($0) }) { gen = true; return true }
            return false
        }
        return gen
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
