import SwiftUI
import AppKit
import Combine
import SkyLightWindow
import AVFoundation
import EventKit

enum AppView { case home, notes, drop, cast, dashboard, choice, notification, onboarding }

final class AppModel: ObservableObject {
    @Published var cursor: CGPoint = .zero
    @Published var expanded: Bool = false
    @Published var view: AppView = .home
    @Published var data = SystemData()
    @Published var sysObs = SystemObserver()
    @Published var notchW: CGFloat = 180
    @Published var notchH: CGFloat = 32
    @Published var viewHeight: CGFloat = 260
    @Published var screenW: CGFloat = 1440
    @Published var droppedURL: URL? = nil
    @Published var notification: String? = nil
    @Published var dropHover: Bool = false
    @Published var isDragging: Bool = false
    
    let aiTracker = AITracker()
    // Ponts persistants : survivent au repli du notch → le stream OsaCast reste vivant
    let dropBridge = DropBridge()
    let castBridge = CastBridge()

    init() {
        let ax = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        let cam = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let cal = EKEventStore.authorizationStatus(for: .event) == .fullAccess || EKEventStore.authorizationStatus(for: .event) == .authorized
        
        if !ax || !screen || !cam || !cal {
            self.view = .onboarding
        }
        aiTracker.onFinish = { [weak self] msg in
            self?.notification = msg
            self?.view = .notification
            self?.expanded = true
        }
        aiTracker.start()
    }
}

enum Island {
    static let winW: CGFloat = 600
    static let winH: CGFloat = 460
    static func shapeSize(expanded: Bool, view: AppView, playing: Bool, hud: Bool, notchW: CGFloat, notchH: CGFloat, vh: CGFloat, sw: CGFloat) -> CGSize {
        if !expanded {
            // Le HUD volume/luminosité descend SOUS l'encoche physique → visible, plus large.
            if hud { return CGSize(width: notchW + 190, height: notchH + 30) }
            return CGSize(width: playing ? notchW + 120 : notchW, height: notchH)
        }
        _ = sw
        switch view {
        case .home:         return CGSize(width: 480, height: 185)
        case .notes:        return CGSize(width: 440, height: 320)
        case .drop:         return CGSize(width: 480, height: 210)
        case .cast:         return CGSize(width: 520, height: vh)
        case .dashboard:    return CGSize(width: 480, height: 240)
        case .choice:       return CGSize(width: 380, height: 160)
        case .notification: return CGSize(width: 320, height: 80)
        case .onboarding:   return CGSize(width: 480, height: 480)
        }
    }
    static func homeRect(_ sf: CGRect) -> CGRect { CGRect(x: sf.midX - 240, y: sf.maxY - 185, width: 480, height: 185) }
}

final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
}

// Accepte le 1er clic : les boutons réagissent immédiatement même si le panneau n'est pas actif.
final class KeyHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var panel: IslandPanel!
    var cursorTimer: Timer?
    var cancellables = Set<AnyCancellable>()
    let localServer = LocalServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.osalabs.osanotch").filter { $0 != me }
        if !others.isEmpty { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)

        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.frame
        model.screenW = sf.width
        // Taille réelle de l'encoche physique (comme coucou)
        if screen.safeAreaInsets.top > 0 {
            model.notchH = screen.safeAreaInsets.top
            model.notchW = sf.width - (screen.auxiliaryTopLeftArea?.width ?? 0) - (screen.auxiliaryTopRightArea?.width ?? 0)
        }
        let frame = NSRect(x: sf.midX - Island.winW / 2, y: sf.maxY - Island.winH, width: Island.winW, height: Island.winH)

        panel = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // L'élévation absolue maximale
        panel.level = NSWindow.Level(rawValue: 2147483631)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.registerForDraggedTypes([.fileURL])
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        // Laisse SwiftUI gérer le click-through grâce à .clear

        let host = KeyHostingView(rootView: IslandView(model: model, data: model.data))
        host.frame = NSRect(x: 0, y: 0, width: Island.winW, height: Island.winH)
        host.autoresizingMask = [.width, .height]
        host.registerForDraggedTypes([.fileURL])
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        // Magie noire de macOS avec SkyLightWindow
        SkyLightOperator.shared.delegateWindow(panel)

        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        model.data.start()

        // ÉCHAPPATOIRE : ESC referme toujours tout (jamais de blocage possible).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.closeAll(); return nil }
            return e
        }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.closeAll() }
        }
        
        // HACK ABSOLU : Capter le drop mondialement car le CGS Space bloque le D&D natif
        var lastProcessedDragCount = NSPasteboard(name: .drag).changeCount
        
        let dropHandler: (NSEvent) -> NSEvent? = { [weak self] e in
            self?.model.isDragging = false
            guard let self = self else { return e }
            let p = NSEvent.mouseLocation
            guard let sf = (self.panel.screen ?? NSScreen.main)?.frame else { return e }
            let shape = Island.shapeSize(expanded: self.model.expanded, view: self.model.view, playing: self.model.data.music?.playing ?? false, hud: self.model.sysObs.showVolumeHUD || self.model.sysObs.showBrightnessHUD, notchW: self.model.notchW, notchH: self.model.notchH, vh: self.model.viewHeight, sw: self.model.screenW)
            let shapeRect = CGRect(x: sf.midX - shape.width / 2, y: sf.maxY - shape.height, width: shape.width, height: shape.height)
            
            if shapeRect.contains(p) {
                let pb = NSPasteboard(name: .drag)
                if pb.changeCount != lastProcessedDragCount {
                    lastProcessedDragCount = pb.changeCount
                    if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first {
                        DispatchQueue.main.async {
                            self.model.droppedURL = url
                            self.model.view = .drop
                            self.model.expanded = true
                        }
                    }
                }
            }
            return e
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { e in _ = dropHandler(e) }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { e in dropHandler(e) }
        
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            let pb = NSPasteboard(name: .drag)
            self?.model.isDragging = pb.types?.contains(.fileURL) ?? false
        }

        // Donner le focus clavier UNE SEULE FOIS à l'ouverture d'une vue à saisie.
        model.$view.removeDuplicates().sink { [weak self] v in
            guard let self else { return }
            if v == .drop || v == .cast || v == .notes {
                self.panel.makeKeyAndOrderFront(nil)
            }
        }.store(in: &cancellables)

        localServer.onNotify = { [weak self] msg in
            self?.model.notification = msg
            self?.model.view = .notification
            self?.model.expanded = true
            // Cacher la notification après 3 secondes
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self?.model.view == .notification { self?.closeAll() }
            }
        }
        localServer.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.sysObs.restoreNativeOSD()   // ne jamais laisser l'OSD natif figé
    }

    func closeAll() {
        model.view = .home
        model.expanded = false
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    func tick() {
        let p = NSEvent.mouseLocation
        model.cursor = p
        guard let sf = (panel.screen ?? NSScreen.main)?.frame else { return }
        let playing = model.data.music?.playing ?? false

        let trigW: CGFloat = 300, trigH: CGFloat = 44
        let trigger = CGRect(x: sf.midX - trigW / 2, y: sf.maxY - trigH, width: trigW, height: trigH)

        let shape = Island.shapeSize(expanded: model.expanded, view: model.view, playing: playing, hud: model.sysObs.showVolumeHUD || model.sysObs.showBrightnessHUD, notchW: model.notchW, notchH: model.notchH, vh: model.viewHeight, sw: model.screenW)
        let shapeRect = CGRect(x: sf.midX - shape.width / 2, y: sf.maxY - shape.height, width: shape.width, height: shape.height)

        if !model.expanded {
            if trigger.contains(p) { model.expanded = true }
        } else {
            if !shapeRect.insetBy(dx: -16, dy: -16).contains(p) { 
                model.expanded = false 
            }
        }
        
        // Gérer le survol visuel du Drag & Drop
        model.dropHover = model.isDragging && shapeRect.contains(p)
    }
}
