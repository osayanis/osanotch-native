import SwiftUI
import AppKit
import Combine

enum AppView { case home, notes, drop, cast }

final class AppModel: ObservableObject {
    @Published var cursor: CGPoint = .zero
    @Published var expanded: Bool = false
    @Published var view: AppView = .home
    @Published var data = SystemData()
}

enum Island {
    static let collapsedH: CGFloat = 34
    // Fenêtre fixe = la plus grande vue possible (transparente + clic-through autour).
    static let winW: CGFloat = 820
    static let winH: CGFloat = 560

    static func collapsedW(_ playing: Bool) -> CGFloat { playing ? 300 : 186 }

    static func shapeSize(expanded: Bool, view: AppView, playing: Bool) -> CGSize {
        if !expanded { return CGSize(width: collapsedW(playing), height: collapsedH) }
        switch view {
        case .home:  return CGSize(width: 480, height: 210)
        case .notes: return CGSize(width: 440, height: 320)
        case .drop:  return CGSize(width: 660, height: 470)
        case .cast:  return CGSize(width: 800, height: 520)
        }
    }
    static func homeRect(_ sf: CGRect) -> CGRect {
        CGRect(x: sf.midX - 240, y: sf.maxY - 210, width: 480, height: 210)
    }
}

final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }   // pour le bloc-note / champs
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
        let frame = NSRect(x: sf.midX - Island.winW / 2, y: sf.maxY - Island.winH, width: Island.winW, height: Island.winH)

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
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: IslandView(model: model, data: model.data))
        host.frame = NSRect(x: 0, y: 0, width: Island.winW, height: Island.winH)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        model.data.start()
    }

    func tick() {
        let p = NSEvent.mouseLocation
        model.cursor = p
        guard let sf = (panel.screen ?? NSScreen.main)?.frame else { return }
        let playing = model.data.music?.playing ?? false

        let trigW: CGFloat = 300, trigH: CGFloat = 44
        let trigger = CGRect(x: sf.midX - trigW / 2, y: sf.maxY - trigH, width: trigW, height: trigH)

        if !model.expanded {
            if trigger.contains(p) { model.expanded = true }
        } else if model.view == .home {
            if !Island.homeRect(sf).insetBy(dx: -8, dy: -8).contains(p) { model.expanded = false }
        }
        // (les vues drop/cast/notes restent ouvertes jusqu'au bouton retour)

        let shape = Island.shapeSize(expanded: model.expanded, view: model.view, playing: playing)
        let shapeRect = CGRect(x: sf.midX - shape.width / 2, y: sf.maxY - shape.height, width: shape.width, height: shape.height)
        panel.ignoresMouseEvents = !shapeRect.contains(p)

        // Une vue ouverte peut avoir besoin du focus (bloc-note)
        if model.expanded && model.view == .notes && !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
    }
}
