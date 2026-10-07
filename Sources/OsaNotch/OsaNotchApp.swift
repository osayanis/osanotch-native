import SwiftUI
import AppKit
import Combine

// Modèle partagé : position du curseur (global), état déployé, données système.
final class AppModel: ObservableObject {
    @Published var cursor: CGPoint = .zero      // coords écran, origine bas-gauche (NSEvent)
    @Published var expanded: Bool = false
    @Published var data = SystemData()
}

// Dimensions
enum Island {
    static let collapsedW: CGFloat = 210
    static let collapsedH: CGFloat = 38
    static let expandedW: CGFloat = 400
    static let expandedH: CGFloat = 430
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var panel: NSPanel!
    var cancellables = Set<AnyCancellable>()
    var cursorTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Instance unique : si un autre OsaNotch tourne déjà, on quitte.
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.osalabs.osanotch")
            .filter { $0 != me }
        if !others.isEmpty { NSApp.terminate(nil); return }

        NSApp.setActivationPolicy(.accessory) // pas d'icône dans le Dock

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let f = screen.frame

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Island.collapsedW, height: Island.collapsedH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false

        let root = IslandView(model: model, data: model.data)
        let host = NSHostingView(rootView: root)
        host.layer?.backgroundColor = .clear
        panel.contentView = host

        positionPanel(expanded: false, screen: screen)
        panel.orderFrontRegardless()

        // Resize animé selon l'état déployé
        model.$expanded
            .removeDuplicates()
            .sink { [weak self] exp in self?.animatePanel(expanded: exp) }
            .store(in: &cancellables)

        // Suivi du curseur global (pour les yeux du perso)
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.model.cursor = NSEvent.mouseLocation
        }

        model.data.start()
        _ = f
    }

    func positionPanel(expanded: Bool, screen: NSScreen) {
        let w = expanded ? Island.expandedW : Island.collapsedW
        let h = expanded ? Island.expandedH : Island.collapsedH
        let sf = screen.frame
        let x = sf.midX - w / 2
        let y = sf.maxY - h // haut de la fenêtre aligné sur le haut de l'écran
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    func animatePanel(expanded: Bool) {
        guard let screen = NSScreen.main else { return }
        let w = expanded ? Island.expandedW : Island.collapsedW
        let h = expanded ? Island.expandedH : Island.collapsedH
        let sf = screen.frame
        let target = NSRect(x: sf.midX - w / 2, y: sf.maxY - h, width: w, height: h)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }
}
