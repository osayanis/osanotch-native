import SwiftUI
import AppKit
import Combine

final class AppModel: ObservableObject {
    @Published var cursor: CGPoint = .zero
    @Published var expanded: Bool = false
    @Published var data = SystemData()
}

enum Island {
    static let collapsedW: CGFloat = 200
    static let collapsedH: CGFloat = 34
    static let expandedW: CGFloat = 380
    static let expandedH: CGFloat = 338
}

// Panneau qui refuse le clamp AppKit sous la barre de menus → colle au sommet.
final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
}

// Laisse passer les clics hors de la forme visible (le reste de la fenêtre est transparent).
final class HitThroughView: NSView {
    var activeRect: CGRect = .zero
    override func hitTest(_ point: NSPoint) -> NSView? {
        activeRect.contains(point) ? super.hitTest(point) : nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var panel: IslandPanel!
    var container: HitThroughView!
    var cancellables = Set<AnyCancellable>()
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
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false

        container = HitThroughView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        let host = NSHostingView(rootView: IslandView(model: model, data: model.data))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.layer?.backgroundColor = .clear
        container.addSubview(host)
        panel.contentView = container

        updateHitRect(expanded: false)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        model.$expanded.removeDuplicates()
            .sink { [weak self] exp in self?.updateHitRect(expanded: exp) }
            .store(in: &cancellables)

        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.model.cursor = NSEvent.mouseLocation
        }
        model.data.start()
    }

    // Rectangle cliquable = la forme visible (coords vue, origine bas-gauche, forme en HAUT)
    func updateHitRect(expanded: Bool) {
        let W = Island.expandedW, H = Island.expandedH
        if expanded {
            container.activeRect = CGRect(x: 0, y: 0, width: W, height: H)
        } else {
            let w = Island.collapsedW, h = Island.collapsedH
            container.activeRect = CGRect(x: (W - w) / 2, y: H - h, width: w, height: h)
        }
    }
}
