import SwiftUI
import AppKit
import Combine

enum AppView { case home, notes, drop, cast }

final class AppModel: ObservableObject {
    @Published var cursor: CGPoint = .zero
    @Published var expanded: Bool = false
    @Published var view: AppView = .home
    @Published var data = SystemData()
    @Published var screenW: CGFloat = 1440
}

enum Island {
    static let collapsedH: CGFloat = 34
    static let winH: CGFloat = 560
    static func collapsedW(_ playing: Bool) -> CGFloat { playing ? 300 : 186 }
    static func homeH() -> CGFloat { 140 }
    static func viewH(_ v: AppView) -> CGFloat {
        switch v { case .home: return homeH(); case .notes: return 300; case .drop: return 520; case .cast: return 540 }
    }
    static func shapeSize(expanded: Bool, view: AppView, playing: Bool, full: CGFloat) -> CGSize {
        if !expanded { return CGSize(width: collapsedW(playing), height: collapsedH) }
        return CGSize(width: full, height: viewH(view))   // pleine largeur → englobe tout
    }
}

final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
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
        model.screenW = sf.width
        let frame = NSRect(x: sf.minX, y: sf.maxY - Island.winH, width: sf.width, height: Island.winH)

        panel = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())) // AU-DESSUS de la barre de menus
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: IslandView(model: model, data: model.data))
        host.frame = NSRect(x: 0, y: 0, width: sf.width, height: Island.winH)
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
            let homeRect = CGRect(x: sf.minX, y: sf.maxY - Island.homeH(), width: sf.width, height: Island.homeH())
            if !homeRect.insetBy(dx: 0, dy: -8).contains(p) { model.expanded = false }
        }

        let shape = Island.shapeSize(expanded: model.expanded, view: model.view, playing: playing, full: sf.width)
        let shapeRect = CGRect(x: sf.midX - shape.width / 2, y: sf.maxY - shape.height, width: shape.width, height: shape.height)
        panel.ignoresMouseEvents = !shapeRect.contains(p)

        if model.expanded && model.view == .notes && !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
    }
}
