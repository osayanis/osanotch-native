import SwiftUI
import AppKit
import Combine
import SkyLightWindow
import AVFoundation
import EventKit

enum AppView { case home, drop, cast, party, dashboard, choice, notification, onboarding }

struct OsaNotif: Identifiable, Equatable {
    enum Source { case ai, messages, mail, huisClos, huisClosPoke, disk }
    let id = UUID()
    let source: Source
    let title: String
    let body: String
    var date = Date()
    var count = 1                    // regroupées : plusieurs messages du même expéditeur
    var disk: DiskKind? = nil        // disque branché : son type (logo)
    var url: URL? = nil              // disque branché : ouvert dans le Finder au clic
    var diskGone = false             // disque éjecté ou retiré (petit symbole « éjecter »)

    /// Appli d'origine : icône, et ouverture au clic.
    var bundleID: String? {
        switch source {
        case .ai, .disk: return nil
        case .messages: return "com.apple.MobileSMS"
        case .mail: return "com.apple.mail"
        case .huisClos, .huisClosPoke: return "fr.kinam.HuisClos"
        }
    }
    var text: String { body.isEmpty ? title : body }
    /// Nom de l'appli d'origine, discret à droite de la bannière.
    var sourceName: String {
        switch source {
        case .ai: return "OsaNotch"
        case .messages: return "Messages"
        case .mail: return "Mail"
        case .huisClos, .huisClosPoke: return "Huis clos"
        case .disk: return "Disques"
        }
    }
}

final class AppModel: ObservableObject {
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
    @Published var showNotifBanner: Bool = false {
        didSet {
            guard oldValue != showNotifBanner else { return }
            leaveTimer?.invalidate()
            if showNotifBanner { bannerLeaving = false; return }
            // Le temps que l'île se rétracte dans l'encoche (ressort de sortie ~0,34 s)
            bannerLeaving = true
            leaveTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.bannerLeaving = false
            }
        }
    }
    @Published var bannerLeaving = false
    private var leaveTimer: Timer?
    /// Messages non lus dans Huis clos : pastille sur le notch replié jusqu'à la lecture.
    @Published var huisClosUnread = 0
    /// Nombre de non lus déjà « vus » (notification effacée) : la pastille ne revient que s'il augmente.
    @Published var huisClosSeen = 0
    var huisClosBadge: Int { huisClosUnread > huisClosSeen ? huisClosUnread : 0 }
    @Published var dropHover: Bool = false
    @Published var isDragging: Bool = false
    private var bannerTimer: Timer?
    private var bannerSource: OsaNotif.Source?
    
    let aiTracker = AITracker()
    let feed = NotificationFeed()
    let disks = DiskWatcher()
    let suite = SuiteLink()
    private var suiteSinks = Set<AnyCancellable>()
    let clipboard = ClipboardManager()
    // Ponts persistants : survivent au repli du notch → le stream OsaCast reste vivant
    let dropBridge = DropBridge()
    let castBridge = CastBridge()
    let friendBridge = FriendBridge.shared
    private var _partyBridge: PartyBridge?
    var partyBridgeIfCreated: PartyBridge? { _partyBridge }
    var partyBridge: PartyBridge {
        if let p = _partyBridge { return p }
        let p = PartyBridge(data: data); _partyBridge = p; return p
    }

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
        // Messages et Mail (Centre de notifications) ; Huis clos annonce lui-même son nombre de non lus
        feed.onNotif = { [weak self] n in self?.push(n) }
        // Clé USB, disque dur, SSD, carte SD branchés
        disks.onDisk = { [weak self] n in self?.push(n) }
        disks.onGone = { [weak self] url in self?.notifications.removeAll { $0.url == url } }
        disks.start()
        // Amis : demande reçue, acceptée, invitation OsaCast / OsaParty → bannière
        friendBridge.onNotice = { [weak self] text in self?.push(OsaNotif(source: .ai, title: "Amis", body: text)) }
        feed.start()
        suite.onHuisClos = { [weak self] count in self?.setHuisClos(count) }
        suite.onHuisClosPoke = { [weak self] de in self?.pokeHuisClos(de) }
        // OsaWallpaper s'occupe du son / de la luminosité : le notch n'affiche plus les siens.
        suite.$wallpaperVolume.removeDuplicates().sink { [weak self] on in self?.sysObs.deferVolume = on }.store(in: &suiteSinks)
        suite.$wallpaperBrightness.removeDuplicates().sink { [weak self] on in self?.sysObs.deferBrightness = on }.store(in: &suiteSinks)
        feed.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &suiteSinks)
        clipboard.start()
        
        AutoUpdater.shared.start()
    }

    /// Assistant IA (Claude Code, API locale) : texte seul.
    func pushNotif(_ text: String) {
        push(OsaNotif(source: .ai, title: "Assistant IA", body: text))
    }

    // Fait apparaître une notification en bannière (sans survol), puis la stocke.
    func push(_ n: OsaNotif) {
        var n = n
        // Rafale du même expéditeur : une seule ligne « +2 », pas trois bannières.
        if n.source != .disk, let first = notifications.first, first.source == n.source, first.title == n.title,
           n.date.timeIntervalSince(first.date) < 90 {
            n.count = first.count + 1
            notifications[0] = n
        } else {
            notifications.insert(n, at: 0)
            if notifications.count > 12 { notifications.removeLast(notifications.count - 12) }
        }
        notification = n.text
        // Déjà dans l'appli d'origine (on lit la conversation) : rangée sans bannière.
        if let id = n.bundleID, NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == id.lowercased() { return }
        // Notch ouvert sur un outil (OsaDrop, OsaCast…) : on ne coupe pas ce qu'on fait.
        // Notch ouvert : la notification va dans la liste, sans changer d'écran
        if expanded { return }
        view = .notification
        bannerSource = n.source
        showNotifBanner = true
        bannerTimer?.invalidate()
        bannerTimer = Timer.scheduledTimer(withTimeInterval: n.source == .ai ? 4.5 : 6, repeats: false) { [weak self] _ in
            self?.showNotifBanner = false
        }
    }

    /// Huis clos n'envoie que son nombre de messages non lus (ni nom, ni texte) : bannière quand il
    /// augmente, une seule ligne tenue à jour dans la liste, et pastille jusqu'à ce que tout soit lu.
    func setHuisClos(_ count: Int) {
        let old = huisClosUnread
        guard count != old else { return }
        huisClosUnread = count
        if count < huisClosSeen { huisClosSeen = count }     // lus dans Huis clos
        let body = count == 1 ? "1 nouveau message" : "\(count) nouveaux messages"
        guard count > 0 else {
            notifications.removeAll { $0.source == .huisClos }
            // Lu entre-temps (dans Huis clos) : la bannière en cours n'a plus lieu d'être
            if showNotifBanner && bannerSource == .huisClos { showNotifBanner = false }
            return
        }
        if count > old {
            notifications.removeAll { $0.source == .huisClos }
            push(OsaNotif(source: .huisClos, title: "Huis clos", body: body))
        } else if let i = notifications.firstIndex(where: { $0.source == .huisClos }) {
            // Une partie lue : on corrige le nombre, sans bannière
            let n = notifications[i]
            notifications[i] = OsaNotif(source: .huisClos, title: n.title, body: body, date: n.date)
        }
    }

    /// Un poke depuis Huis clos (façon TeamSpeak) : bannière tout de suite, même si la personne est
    /// dans Huis clos, et un petit son. Titre à part pour ne pas être regroupé avec les non lus.
    func pokeHuisClos(_ de: String) {
        // N'importe quelle appli peut poster cette notification : nom borné
        let qui = String(de.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        NSSound(named: "Ping")?.play()
        // Source à part : le compteur des non lus (setHuisClos) ne touche pas aux pokes
        let n = OsaNotif(source: .huisClosPoke, title: "Poke", body: "\(qui.isEmpty ? "Quelqu'un" : qui) te poke 👋")
        notifications.removeAll { $0.source == .huisClosPoke }
        notifications.insert(n, at: 0)
        if notifications.count > 12 { notifications.removeLast(notifications.count - 12) }
        notification = n.text
        // Notch ouvert sur un outil (OsaDrop, OsaCast…) : le son et la liste, sans couper ce qu'on fait
        // Notch ouvert : la notification va dans la liste, sans changer d'écran
        if expanded { return }
        view = .notification
        bannerSource = n.source
        showNotifBanner = true
        bannerTimer?.invalidate()
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.showNotifBanner = false
        }
    }

    /// Efface une notification de la liste (et sa bannière si elle est affichée).
    func dismiss(_ n: OsaNotif) {
        if notifications.first?.id == n.id && showNotifBanner { showNotifBanner = false }
        notifications.removeAll { $0.id == n.id }
        // Effacer la ligne Huis clos efface aussi la pastille, jusqu'au prochain message
        if n.source == .huisClos { huisClosSeen = huisClosUnread }
    }

    /// Efface toutes les notifications, pastille Huis clos comprise (elle revient au prochain message).
    func clearNotifications() {
        showNotifBanner = false
        bannerTimer?.invalidate()
        notifications.removeAll()
        huisClosSeen = huisClosUnread
    }

    /// Clic sur une notification : ouvre l'appli d'origine.
    func open(_ n: OsaNotif) {
        if let url = n.url {
            NSWorkspace.shared.open(url)
            showNotifBanner = false
            return
        }
        guard let id = n.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        showNotifBanner = false
    }

    /// Le notch visible : n'affecte une valeur publiée que si elle change (chaque affectation
    /// redessine toute la vue, même avec la même valeur).
    func set<T: Equatable>(_ kp: ReferenceWritableKeyPath<AppModel, T>, _ v: T) {
        if self[keyPath: kp] != v { self[keyPath: kp] = v }
    }

    var hudActive: Bool { sysObs.showVolumeHUD || sysObs.showBrightnessHUD }
    var playing: Bool { data.music?.playing ?? false }
    /// Accueil pendant la lecture : le lecteur (par défaut) ou l'accueil complet (amis, notifications).
    /// Repasse sur le lecteur à chaque nouvelle lecture.
    @Published var showPlayer = true
    var homePlayer: Bool { playing && showPlayer }

    var shape: CGSize {
        var s = Island.shapeSize(expanded: expanded, view: view, playing: playing, badge: huisClosBadge > 0, hud: hudActive, notifBanner: showNotifBanner, notchW: notchW, notchH: notchH, vh: viewHeight, sw: screenW, theater: theater, theaterSize: theaterSize, player: homePlayer)
        // Bandeau « mise à jour disponible » de l'accueil : sa propre ligne en plus.
        if expanded && view == .home && !homePlayer && AutoUpdater.shared.updateAvailable != nil { s.height += 30 }
        return s
    }
    /// L'île est-elle dessinée (sinon seule l'encoche physique se voit) ?
    var islandVisible: Bool { expanded || hudActive || playing || huisClosBadge > 0 || showNotifBanner || dropHover }
}

enum Island {
    static let winW: CGFloat = 600
    static let winH: CGFloat = 460
    /// Bannière de notification sous l'encoche.
    static let bannerW: CGFloat = 380
    static let bannerH: CGFloat = 58
    static func shapeSize(expanded: Bool, view: AppView, playing: Bool, badge: Bool = false, hud: Bool, notifBanner: Bool, notchW: CGFloat, notchH: CGFloat, vh: CGFloat, sw: CGFloat, theater: Bool = false, theaterSize: CGSize = .zero, player: Bool? = nil) -> CGSize {
        let player = player ?? playing
        if theater && view == .cast { return theaterSize }
        if !expanded {
            // Bannière de notification : descend sous l'encoche, visible sans survol.
            // Avec le son / la luminosité en même temps, la barre se range dessous.
            if view == .notification && notifBanner { return CGSize(width: bannerW, height: notchH + bannerH + (hud ? 28 : 0)) }
            // Le HUD volume/luminosité descend SOUS l'encoche physique → visible, plus large.
            if hud { return CGSize(width: notchW, height: notchH + 30) }
            // Musique et / ou pastille Huis clos : de part et d'autre de l'encoche physique.
            return CGSize(width: playing || badge ? notchW + 56 : notchW, height: notchH)
        }
        _ = sw
        switch view {
        // Tous les onglets de la barre (home, dashboard, drop, cast, party) : même largeur, 480.
        // Raccourcis Party / Drop / Cast retirés (déjà dans la barre d'onglets) : accueil plus bas.
        case .home:         return player ? CGSize(width: 480, height: 168) : CGSize(width: 480, height: 160)
        case .drop:         return CGSize(width: 480, height: 210)
        case .cast:         return CGSize(width: 480, height: vh)
        case .party:        return CGSize(width: 480, height: vh)
        case .dashboard:    return CGSize(width: 480, height: 272)
        case .choice:       return CGSize(width: 380, height: 160)
        case .notification: return player ? CGSize(width: 480, height: 168) : CGSize(width: 480, height: 160)
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
        if !others.isEmpty {
            // Une seule copie à la fois. Si celle qui tourne est plus ancienne (copie de développement,
            // ou vieille version relancée par macOS), c'est elle qui laisse la place.
            let mine = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let older = others.allSatisfy { app in
                guard let url = app.bundleURL,
                      let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                      let v = info["CFBundleShortVersionString"] as? String else { return false }
                return AutoUpdater.isNewer(mine, than: v)
            }
            guard older else { NSApp.terminate(nil); return }
            others.forEach { $0.terminate() }
            let limit = Date().addingTimeInterval(3)
            while others.contains(where: { !$0.isTerminated }) && Date() < limit {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }
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
            self.model.set(\.isDragging, false)
            let p = NSEvent.mouseLocation
            guard let sf = (self.panel.screen ?? NSScreen.main)?.frame else { return e }

            let pb = NSPasteboard(name: .drag)
            let cc = pb.changeCount
            // Chaque glisser n'est traité qu'UNE fois. On le "consomme" dès le premier
            // relâchement, où qu'il ait lieu → un déplacement dossier→dossier ne peut plus
            // être récupéré par un clic ultérieur sur le notch.
            guard cc != lastProcessedDragCount else { return e }
            lastProcessedDragCount = cc

            let shape = self.model.shape
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
            self?.model.set(\.isDragging, pb.types?.contains(.fileURL) ?? false)
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

        model.suite.start(display: screen.displayID)
        // Sans « Accès complet au disque », pas de Messages ni de Mail : on le dit une fois.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.model.feed.needsAccess, self.model.view != .onboarding else { return }
            self.model.push(OsaNotif(source: .ai, title: "Messages et Mail", body: "Autorise l'accès complet au disque (clic sur la liste)"))
        }

        // Captures de test : OSANOTCH_DEMO=music (lecteur) ou music-home (accueil pendant la lecture),
        // encoche ouverte et figée, sans toucher à la souris ni lancer de son.
        // OSANOTCH_DEMO=disk:/Volumes/<nom> : annonce ce volume comme s'il venait d'être branché
        // OSANOTCH_DEMO=diskimages : les images disque comptent comme des disques (tests du retrait)
        if SystemData.demo == "diskimages" { DiskWatcher.allowImages = true }
        if let demo = SystemData.demo, demo.hasPrefix("disk:") {
            let url = URL(fileURLWithPath: String(demo.dropFirst(5)))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.model.disks.announce(url) }
        }
        if let demo = SystemData.demo, demo.hasPrefix("music") {
            model.data.music = MusicInfo(playing: true, title: "Titre de test", artist: "Artiste", source: "Music",
                                         artworkURL: nil, position: 62, duration: 214)
            model.data.positionSampledAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.model.showPlayer = demo == "music"
                self?.model.view = .home
                self?.model.expanded = true
            }
        }
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
        if SystemData.demo != nil { return }
        let p = NSEvent.mouseLocation
        guard let sf = (panel.screen ?? NSScreen.main)?.frame else { return }
        defer { model.suite.update(bottom: model.islandVisible ? model.shape.height : model.notchH) }

        // Mode cinéma OsaCast : le notch reste grand ouvert, on ignore le survol.
        if model.theater {
            model.set(\.expanded, true)
            model.set(\.dropHover, false)
            return
        }

        let trigW: CGFloat = 300, trigH: CGFloat = 44
        let trigger = CGRect(x: sf.midX - trigW / 2, y: sf.maxY - trigH, width: trigW, height: trigH)

        let shape = model.shape
        let shapeRect = CGRect(x: sf.midX - shape.width / 2, y: sf.maxY - shape.height, width: shape.width, height: shape.height)

        // Cas spécial notifications : la bannière reste visible sans survol ;
        // au survol on déploie l'écran (mascotte à gauche + liste à droite).
        if model.view == .notification {
            let over = shapeRect.insetBy(dx: -16, dy: -16).contains(p)
            if over {
                // Au survol : le menu classique (accueil), pas un écran à part
                model.set(\.view, .home)
                model.set(\.expanded, true)
            } else if model.expanded {
                // L'utilisateur a consulté puis quitté → retour accueil.
                model.set(\.expanded, false)
                model.set(\.view, .home)
            } else if !model.showNotifBanner {
                // Bannière expirée et pas de survol → retour accueil.
                model.set(\.view, .home)
            }
            model.set(\.dropHover, false)
            return
        }

        if !model.expanded {
            if trigger.contains(p) { model.set(\.expanded, true) }
        } else if !shapeRect.insetBy(dx: -16, dy: -16).contains(p) {
            model.set(\.expanded, false)
        }

        // Gérer le survol visuel du Drag & Drop
        model.set(\.dropHover, model.isDragging && shapeRect.contains(p))
    }
}
