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
    private var currentTask: String? = nil

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
        var newlyFoundTask: String? = nil
        
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
                if name == "Antigravity" {
                    if let agyTask = getAntigravityTask() {
                        newlyGeneratingAI = "Antigravity"
                        newlyFoundTask = agyTask
                        break
                    }
                }
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
            
            if let ai = detectingAI, let task = scanForGenerating(window) {
                newlyGeneratingAI = ai
                newlyFoundTask = task
                break // We found one generating, no need to check others
            }
        }

        DispatchQueue.main.async {
            let isGen = newlyGeneratingAI != nil
            
            if isGen {
                self.noGenTicks = 0
                self.currentAI = newlyGeneratingAI
                self.isGenerating = true
                self.wasGenerating = true
                
                // Si la tâche a changé et qu'elle est pertinente
                if let task = newlyFoundTask, task != self.currentTask {
                    self.currentTask = task
                    let cleanName = newlyGeneratingAI ?? "L'IA"
                    self.onFinish?("\(cleanName) : \(task)")
                }
            } else {
                self.noGenTicks += 1
                // Il faut 3 ticks (3x2s = 6s) sans génération pour valider la fin
                if self.wasGenerating && self.noGenTicks >= 3 {
                    if let finishedAI = self.currentAI {
                        self.onFinish?("\(finishedAI) a fini de générer.")
                    }
                    self.currentAI = nil
                    self.currentTask = nil
                    self.isGenerating = false
                    self.wasGenerating = false
                }
            }
            self.isChecking = false
        }
    }
    
    // Indices textuels d'une génération en cours (bouton Stop, spinner, "interrupt"…).
    private static let genKeywords = [
        "stop generating", "stop response", "stop streaming", "génération en cours",
        "generating", "thinking", "esc to interrupt", "interrupt", "cancel generation",
        "arrêter la génération", "répond", "is working", "running…", "en cours d'exécution",
        "claude is thinking", "agent is thinking", "running task", "[thought]", "tool call",
        "tool is running", "task id",
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", // Spinners CLI
        "analyzing", "searching", "checking", "reading", "patching", "creating", "building", // Antigravity toolActions
        "call:" // Antigravity tool call syntax
    ]

        private func getAntigravityTask() -> String? {
        let fm = FileManager.default
        let brainURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/brain")
        guard let enumerator = fm.enumerator(at: brainURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        
        var latestFile: URL?
        var latestDate = Date.distantPast
        
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "transcript.jsonl" {
                if let attr = try? fm.attributesOfItem(atPath: fileURL.path),
                   let modDate = attr[.modificationDate] as? Date {
                    if modDate > latestDate {
                        latestDate = modDate
                        latestFile = fileURL
                    }
                }
            }
        }
        
        guard let file = latestFile, let data = try? Data(contentsOf: file) else { return nil }
        let str = String(decoding: data, as: UTF8.self)
        let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines.reversed().prefix(20) {
            if let range = line.range(of: "\"toolAction\":\"\\\"") {
                let rest = line[range.upperBound...]
                if let endRange = rest.range(of: "\\\"\"") {
                    var action = String(rest[..<endRange.lowerBound])
                    if action.count > 40 { action = String(action.prefix(37)) + "..." }
                    return "※ " + action
                }
            } else if let range = line.range(of: "\"toolAction\":\"") {
                let rest = line[range.upperBound...]
                if let endRange = rest.range(of: "\"") {
                    var action = String(rest[..<endRange.lowerBound])
                    if action.count > 40 { action = String(action.prefix(37)) + "..." }
                    return "※ " + action
                }
            }
        }
        return nil
    }

    private func scanForGenerating(_ axWindow: AXUIElement) -> String? {
        var foundTask: String? = nil
        scanAXTree(element: axWindow, depth: 0, maxDepth: 22) { role, title, desc, val in
            var textParts: [String] = []
            if let t = title, !t.isEmpty { textParts.append(t) }
            if let d = desc, !d.isEmpty { textParts.append(d) }
            if let v = val, !v.isEmpty {
                let suffix = String(v.suffix(1000))
                textParts.append(suffix)
            }
            let text = textParts.joined(separator: "\n")
            if text.isEmpty { return false }
            
            let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for line in lines.reversed() {
                let lowerLine = line.lowercased()
                if Self.genKeywords.contains(where: { lowerLine.contains($0) }) {
                    var clean = line
                    if clean.count > 40 { clean = String(clean.prefix(37)) + "..." }
                    foundTask = clean
                    return true // stop scanning
                }
            }
            return false
        }
        return foundTask
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
