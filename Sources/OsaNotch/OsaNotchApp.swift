import SwiftUI
import AppKit
import Combine
import SkyLightWindow
import AVFoundation
import EventKit

enum AppView { case home, drop, cast, party, dashboard, choice, notification, onboarding }

struct OsaNotif: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
}

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
    // Mode cinéma OsaCast : agrandit le notch sur une grande partie de l'écran
    @Published var theater: Bool = false
    @Published var theaterSize: CGSize = CGSize(width: 1100, height: 640)
    // Presse-papier de fichiers (plusieurs fichiers, persistés)
    let shelf = FileShelf()
    private var shelfSink: AnyCancellable?
    // Compat : « le » fichier courant = la sélection du presse-papier, sinon le plus récent.
    var droppedURL: URL? {
        get { shelf.selected ?? shelf.items.first }
        set {
            if let u = newValue { shelf.add([u]) }
            else if let cur = droppedURL { shelf.remove(cur) }
        }
    }
    @Published var notification: String? = nil
    @Published var notifications: [OsaNotif] = []
    @Published var showNotifBanner: Bool = false
    @Published var dropHover: Bool = false
    @Published var isDragging: Bool = false
    private var bannerTimer: Timer?
    
    let aiTracker = AITracker()
    let clipboard = ClipboardManager()
    // Ponts persistants : survivent au repli du notch → le stream OsaCast reste vivant
    let dropBridge = DropBridge()
    let castBridge = CastBridge()
    let friendBridge = FriendBridge.shared
    lazy var partyBridge = PartyBridge(data: data)

    init() {
        let ax = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        let cam = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let cal = EKEventStore.authorizationStatus(for: .event) == .fullAccess || EKEventStore.authorizationStatus(for: .event) == .authorized
        
        if !ax || !screen || !cam || !cal {
            self.view = .onboarding
        }
        // Toute vue qui observe le modèle se rafraîchit quand le presse-papier change.
        shelfSink = shelf.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        aiTracker.onFinish = { [weak self] msg in self?.pushNotif(msg) }
        aiTracker.start()
        clipboard.start()
        
        AutoUpdater.shared.checkForUpdates()
    }

    // Fait apparaître une notification en bannière (sans survol), puis la stocke.
    func pushNotif(_ text: String) {
        notification = text
        notifications.insert(OsaNotif(text: text, date: Date()), at: 0)
        if notifications.count > 8 { notifications.removeLast(notifications.count - 8) }
        view = .notification
        showNotifBanner = true
        bannerTimer?.invalidate()
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            self?.showNotifBanner = false
        }
    }
}

enum Island {
    static let winW: CGFloat = 600
    static let winH: CGFloat = 460
    static func shapeSize(expanded: Bool, view: AppView, playing: Bool, hud: Bool, notifBanner: Bool, notchW: CGFloat, notchH: CGFloat, vh: CGFloat, sw: CGFloat, theater: Bool = false, theaterSize: CGSize = .zero) -> CGSize {
        if theater && view == .cast { return theaterSize }
        if !expanded {
            // Bannière de notification : descend sous l'encoche, visible sans survol.
            if view == .notification && notifBanner { return CGSize(width: 360, height: notchH + 52) }
            // Le HUD volume/luminosité descend SOUS l'encoche physique → visible, plus large.
            if hud { return CGSize(width: notchW, height: notchH + 30) }
            return CGSize(width: playing ? notchW + 56 : notchW, height: notchH)
        }
        _ = sw
        switch view {
        case .home:         return playing ? CGSize(width: 480, height: 168) : CGSize(width: 480, height: 185)
        case .drop:         return CGSize(width: 480, height: 210)
        case .cast:         return CGSize(width: 520, height: vh)
        case .party:        return CGSize(width: 500, height: vh)
        case .dashboard:    return CGSize(width: 480, height: 272)
        case .choice:       return CGSize(width: 380, height: 160)
        case .notification: return CGSize(width: 470, height: 176)
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
        // Taille du mode cinéma : grande partie de l'écran, centrée sous la barre de menu.
        model.theaterSize = CGSize(width: min(sf.width * 0.84, 1280), height: sf.height * 0.76)
        // Le panneau est fixe et assez grand pour contenir le mode cinéma : on ne le
        // redimensionne JAMAIS (un panneau délégué à SkyLight se repositionne mal).
        // Seul le CONTENU grandit/rétrécit ; le notch, aligné en haut-centre, ne bouge pas.
        let panelW = model.theaterSize.width + 40
        let panelH = model.theaterSize.height + 20
        let frame = NSRect(x: sf.midX - panelW / 2, y: sf.maxY - panelH, width: panelW, height: panelH)

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

        let host = KeyHostingView(rootView: IslandView(model: model, data: model.data, castBridge: model.castBridge))
        host.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
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
            guard let self = self else { return e }
            self.model.isDragging = false
            let p = NSEvent.mouseLocation
            guard let sf = (self.panel.screen ?? NSScreen.main)?.frame else { return e }

            let pb = NSPasteboard(name: .drag)
            let cc = pb.changeCount
            // Chaque glisser n'est traité qu'UNE fois. On le "consomme" dès le premier
            // relâchement, où qu'il ait lieu → un déplacement dossier→dossier ne peut plus
            // être récupéré par un clic ultérieur sur le notch.
            guard cc != lastProcessedDragCount else { return e }
            lastProcessedDragCount = cc

            let shape = Island.shapeSize(expanded: self.model.expanded, view: self.model.view, playing: self.model.data.music?.playing ?? false, hud: self.model.sysObs.showVolumeHUD || self.model.sysObs.showBrightnessHUD, notifBanner: self.model.showNotifBanner, notchW: self.model.notchW, notchH: self.model.notchH, vh: self.model.viewHeight, sw: self.model.screenW, theater: self.model.theater, theaterSize: self.model.theaterSize)
            let shapeRect = CGRect(x: sf.midX - shape.width / 2, y: sf.maxY - shape.height, width: shape.width, height: shape.height)

            // On n'ajoute le fichier QUE si le glisser se termine réellement sur le notch.
            guard shapeRect.contains(p),
                  pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
                  let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty else { return e }
            DispatchQueue.main.async {
                self.model.shelf.add(urls)   // tous les fichiers glissés, pas seulement le 1er
                self.model.view = .drop
                self.model.expanded = true
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
            if v == .drop || v == .cast || v == .party {
                self.panel.makeKeyAndOrderFront(nil)
            }
        }.store(in: &cancellables)

        localServer.onNotify = { [weak self] msg in self?.model.pushNotif(msg) }
        localServer.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.sysObs.restoreNativeOSD()   // ne jamais laisser l'OSD natif figé
    }

    func closeAll() {
        model.theater = false
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

        // Mode cinéma OsaCast : le notch reste grand ouvert, on ignore le survol.
        if model.theater {
            model.expanded = true
            model.dropHover = false
            return
        }

        let trigW: CGFloat = 300, trigH: CGFloat = 44
        let trigger = CGRect(x: sf.midX - trigW / 2, y: sf.maxY - trigH, width: trigW, height: trigH)

        let shape = Island.shapeSize(expanded: model.expanded, view: model.view, playing: playing, hud: model.sysObs.showVolumeHUD || model.sysObs.showBrightnessHUD, notifBanner: model.showNotifBanner, notchW: model.notchW, notchH: model.notchH, vh: model.viewHeight, sw: model.screenW, theater: model.theater, theaterSize: model.theaterSize)
        let shapeRect = CGRect(x: sf.midX - shape.width / 2, y: sf.maxY - shape.height, width: shape.width, height: shape.height)

        // Cas spécial notifications : la bannière reste visible sans survol ;
        // au survol on déploie l'écran (mascotte à gauche + liste à droite).
        if model.view == .notification {
            let over = shapeRect.insetBy(dx: -16, dy: -16).contains(p)
            if over {
                model.expanded = true
            } else if model.expanded {
                // L'utilisateur a consulté puis quitté → retour accueil.
                model.expanded = false
                model.view = .home
            } else if !model.showNotifBanner {
                // Bannière expirée et pas de survol → retour accueil.
                model.view = .home
            }
            model.dropHover = false
            return
        }

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
