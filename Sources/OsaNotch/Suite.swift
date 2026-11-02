import AppKit
import Combine

// La suite Osa parle d'une appli à l'autre par notifications distribuées (même session,
// pas de serveur). Même protocole recopié dans OsaWallpaper (Suite.swift) :
//   com.osalabs.suite.hello      « je viens d'arriver » → les autres renvoient leur état
//   com.osalabs.suite.wallpaper  OsaWallpaper : volume / brightness (Bool) = ses pastilles s'en chargent
//   com.osalabs.suite.notch      OsaNotch : bottom (points sous le haut de l'écran à encoche), display
//   fr.kinam.HuisClos.messageRecu  Huis clos : conversation (nom seul, jamais le texte)
enum Suite {
    static let hello = Notification.Name("com.osalabs.suite.hello")
    static let wallpaper = Notification.Name("com.osalabs.suite.wallpaper")
    static let notch = Notification.Name("com.osalabs.suite.notch")
    static let huisClos = Notification.Name("fr.kinam.HuisClos.messageRecu")
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
    var onHuisClos: ((String) -> Void)?

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
        tokens.append(dc.addObserver(forName: Suite.huisClos, object: nil, queue: .main) { [weak self] n in
            guard let name = n.userInfo?["conversation"] as? String, !name.isEmpty else { return }
            self?.onHuisClos?(name)
        })
        // OsaWallpaper quitté (ou planté) sans prévenir : le notch reprend la main.
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Suite.wallpaperID else { return }
            self?.wallpaperVolume = false
            self?.wallpaperBrightness = false
        })
        Suite.post(Suite.hello, ["app": "osanotch"])
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
