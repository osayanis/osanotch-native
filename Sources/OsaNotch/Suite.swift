import AppKit
import Combine

// La suite Osa parle d'une appli à l'autre par notifications distribuées (même session,
// pas de serveur). Même protocole recopié dans OsaWallpaper (Suite.swift) :
//   com.osalabs.suite.hello      « je viens d'arriver » → les autres renvoient leur état
//   com.osalabs.suite.wallpaper  OsaWallpaper : volume / brightness (Bool) = ses pastilles s'en chargent
//   com.osalabs.suite.notch      OsaNotch : bottom (points sous le haut de l'écran à encoche), display
// Et le protocole de Huis clos (appli de Kinam, voir son README « L'avis dans l'encoche ») :
//   fr.kinam.HuisClos.nonLus   Huis clos → nombre (Int) de messages non lus, à chaque changement,
//                              même verrouillé ; jamais le nom ni le texte
//   fr.kinam.HuisClos.demande  notch → Huis clos : « redis-moi où on en est » (au lancement)
//   fr.kinam.HuisClos.poke     Huis clos → un poke reçu (façon TeamSpeak), « de » = nom de la
//                              conversation chez l'autre (peut être vide) ; même verrouillé
enum Suite {
    static let hello = Notification.Name("com.osalabs.suite.hello")
    static let wallpaper = Notification.Name("com.osalabs.suite.wallpaper")
    static let notch = Notification.Name("com.osalabs.suite.notch")
    static let huisClosUnread = Notification.Name("fr.kinam.HuisClos.nonLus")
    static let huisClosAsk = Notification.Name("fr.kinam.HuisClos.demande")
    static let huisClosPoke = Notification.Name("fr.kinam.HuisClos.poke")
    static let huisClosID = "fr.kinam.HuisClos"
    static let wallpaperID = "com.osalabs.osawallpaper"

    static func post(_ name: Notification.Name, _ info: [String: Any] = [:]) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
    }
}

/// Ce que les autres applis de la suite prennent en charge, vu depuis le notch.
final class SuiteLink: ObservableObject {
    /// OsaWallpaper affiche ses propres pastilles son / luminosité : le notch s'efface.
    @Published private(set) var wallpaperVolume = false
    @Published private(set) var wallpaperBrightness = false
    /// Nombre de messages non lus annoncé par Huis clos (0 = tout est lu, ou appli quittée).
    var onHuisClos: ((Int) -> Void)?
    /// Un poke envoyé depuis Huis clos : le nom de qui le fait (ou vide).
    var onHuisClosPoke: ((String) -> Void)?

    private var lastBottom: CGFloat = -1
    private var display: CGDirectDisplayID = 0
    private var tokens: [NSObjectProtocol] = []

    func start(display: CGDirectDisplayID) {
        self.display = display
        let dc = DistributedNotificationCenter.default()
        tokens.append(dc.addObserver(forName: Suite.wallpaper, object: nil, queue: .main) { [weak self] n in
            self?.wallpaperVolume = n.userInfo?["volume"] as? Bool ?? false
            self?.wallpaperBrightness = n.userInfo?["brightness"] as? Bool ?? false
        })
        tokens.append(dc.addObserver(forName: Suite.hello, object: nil, queue: .main) { [weak self] _ in
            self?.announce(force: true)
        })
        tokens.append(dc.addObserver(forName: Suite.huisClosUnread, object: nil, queue: .main) { [weak self] n in
            guard let count = (n.userInfo?["nombre"] as? NSNumber)?.intValue else { return }
            self?.onHuisClos?(max(0, count))
        })
        tokens.append(dc.addObserver(forName: Suite.huisClosPoke, object: nil, queue: .main) { [weak self] n in
            self?.onHuisClosPoke?((n.userInfo?["de"] as? String) ?? "")
        })
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            switch (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier {
            case Suite.wallpaperID?:
                // OsaWallpaper quitté (ou planté) sans prévenir : le notch reprend la main.
                self?.wallpaperVolume = false
                self?.wallpaperBrightness = false
            case Suite.huisClosID?:
                // Huis clos quitté (Cmd + Q) : il ne compte plus rien et n'annonce pas 0.
                self?.onHuisClos?(0)
            default: break
            }
        })
        Suite.post(Suite.hello, ["app": "osanotch"])
        // Huis clos déjà lancé redonne son compte (il ne répond rien s'il ne sait encore rien).
        Suite.post(Suite.huisClosAsk)
    }

    /// Bas du notch visible, en points depuis le haut de l'écran : OsaWallpaper place ses
    /// pastilles juste en dessous. N'envoie que les changements.
    func update(bottom: CGFloat) {
        guard abs(bottom - lastBottom) > 0.5 else { return }
        lastBottom = bottom
        announce(force: true)
    }

    private func announce(force: Bool) {
        guard lastBottom >= 0 else { return }
        Suite.post(Suite.notch, ["bottom": Double(lastBottom), "display": Int(display)])
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
