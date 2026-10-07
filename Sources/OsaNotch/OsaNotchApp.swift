import SwiftUI
import AppKit
import Combine

final class AppModel: ObservableObject {
    @Published var cursor: CGPoint = .zero
    @Published var expanded: Bool = false
    @Published var data = SystemData()
}

enum Island {
    static let collapsedW: CGFloat = 210
    static let collapsedH: CGFloat = 34
    static let expandedW: CGFloat = 380
    static let expandedH: CGFloat = 338
}

// Panneau qui refuse le clamp AppKit sous la barre de menus → colle au sommet.
final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var panel: IslandPanel!
    var cursorTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.osalabs.osanotch").filter { $0 != me }
        if !others.isEmpty { NSApp.terminate(nil); return }

        NSApp.setActivationPolicy(.accessory)

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.frame
        let W = Island.expandedW, H = Island.expandedH
        let frame = NSRect(x: sf.midX - W / 2, y: sf.maxY - H, width: W, height: H)

        panel = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.ignoresMouseEvents = true // clic-through par défaut ; activé seulement sur la forme

        let host = NSHostingView(rootView: IslandView(model: model, data: model.data))
        host.frame = NSRect(x: 0, y: 0, width: W, height: H)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        // Moniteur global du curseur : pilote ouverture/fermeture + clic-through.
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        model.data.start()
    }

    func tick() {
        let p = NSEvent.mouseLocation
        model.cursor = p
        guard let sf = (panel.screen ?? NSScreen.main)?.frame else { return }

        // Zone de déclenchement (repli) : LARGE et pile sur l'encoche → survol facile.
        let trigW: CGFloat = 280, trigH: CGFloat = 42
        let trigger = CGRect(x: sf.midX - trigW / 2, y: sf.maxY - trigH, width: trigW, height: trigH)
        // Forme déployée
        let expRect = CGRect(x: sf.midX - Island.expandedW / 2, y: sf.maxY - Island.expandedH, width: Island.expandedW, height: Island.expandedH)
        // Forme visible actuelle
        let shapeRect = model.expanded ? expRect
            : CGRect(x: sf.midX - Island.collapsedW / 2, y: sf.maxY - Island.collapsedH, width: Island.collapsedW, height: Island.collapsedH)

        if model.expanded {
            if !expRect.insetBy(dx: -6, dy: -6).contains(p) { model.expanded = false }
        } else if trigger.contains(p) {
            model.expanded = true
        }

        // Clic-through partout SAUF sur la forme visible → aucune zone morte.
        panel.ignoresMouseEvents = !shapeRect.contains(p)
    }
}
