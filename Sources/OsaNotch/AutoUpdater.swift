import SwiftUI
import AppKit

/// Mises à jour d'OsaNotch depuis les releases GitHub d'osayanis/osanotch-native (dépôt public).
/// La release « latest » doit contenir OsaNotch.zip (publish.sh l'y met).
final class AutoUpdater: ObservableObject {
    static let shared = AutoUpdater()

    @Published var updateAvailable: String? = nil
    @Published var isUpdating: Bool = false

    private let releasesURL = URL(string: "https://api.github.com/repos/osayanis/osanotch-native/releases/latest")!
    private let assetName = "OsaNotch.zip"
    private var downloadUrl: URL? = nil
    private var timer: Timer?

    // Version actuelle (définie dans le code ; bumpée par publish.sh)
    private let currentVersion = "1.0.9"

    /// Au lancement, puis toutes les 6 heures : OsaNotch tourne souvent des jours sans être relancé.
    /// (L'API GitHub sans compte autorise 60 requêtes par heure : on en est loin.)
    func start() {
        if handOffToNewerCopy() { return }
        checkForUpdates()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func checkForUpdates() {
        var req = URLRequest(url: releasesURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("OsaNotch Updater", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { $0["name"] as? String == self.assetName }),
                  let urlStr = asset["browser_download_url"] as? String,
                  let assetUrl = URL(string: urlStr) else { return }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            // Seulement une version plus récente : jamais de retour en arrière
            guard Self.isNewer(latest, than: self.currentVersion) else { return }
            DispatchQueue.main.async {
                // Déjà installée ailleurs (OsaHUB met à jour /Applications pendant qu'une vieille
                // copie tourne) : on passe la main à cette copie au lieu de proposer la mise à jour.
                if self.handOffToNewerCopy(atLeast: latest) { return }
                self.updateAvailable = latest
                self.downloadUrl = assetUrl
            }
        }.resume()
    }

    /// Copies rangées dans Applications (là où OsaHUB installe et met à jour).
    private var installedCopies: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(fileURLWithPath: "/Applications/OsaNotch.app"), home.appendingPathComponent("Applications/OsaNotch.app")]
    }

    /// Si une autre copie d'OsaNotch, plus récente que celle-ci, est installée (par OsaHUB par exemple),
    /// on l'ouvre et on quitte : sinon une vieille copie (de développement, ou relancée par macOS)
    /// redemande une mise à jour déjà faite. `atLeast` : version minimale attendue de cette copie.
    @discardableResult
    func handOffToNewerCopy(atLeast minimum: String? = nil) -> Bool {
        let me = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        for url in installedCopies where url.resolvingSymlinksInPath().standardizedFileURL.path != me {
            // Info.plist lu sur le disque (Bundle(url:) garde l'ancienne version en cache)
            guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  let v = info["CFBundleShortVersionString"] as? String,
                  Self.isNewer(v, than: currentVersion),
                  minimum.map({ !Self.isNewer($0, than: v) }) ?? true else { continue }
            // On quitte d'abord (une seule copie à la fois, et le port de l'API locale doit se libérer),
            // un petit script attend notre fin puis ouvre l'autre copie.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open -g \"$0\"", url.path]
            guard (try? p.run()) != nil else { continue }
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return true
        }
        return false
    }

    /// "1.0.10" > "1.0.9" : comparaison nombre par nombre.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func installUpdate() {
        guard let url = downloadUrl, !isUpdating else { return }
        isUpdating = true

        let destZip = URL(fileURLWithPath: "/tmp/OsaNotch_update.zip")
        let destFolder = URL(fileURLWithPath: "/tmp/OsaNotch_update_extracted")
        let fail = { DispatchQueue.main.async { self.isUpdating = false } }

        // Téléchargement (GitHub redirige vers son stockage : URLSession suit tout seul)
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, _ in
            guard let localURL, (response as? HTTPURLResponse)?.statusCode == 200 else { return fail() }

            let fm = FileManager.default
            try? fm.removeItem(at: destZip)
            try? fm.removeItem(at: destFolder)
            guard (try? fm.copyItem(at: localURL, to: destZip)) != nil,
                  (try? fm.createDirectory(at: destFolder, withIntermediateDirectories: true)) != nil else { return fail() }

            // Décompression avec ditto (garde attributs et signature, comme le zip a été fait)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-x", "-k", destZip.path, destFolder.path]
            guard (try? proc.run()) != nil else { return fail() }
            proc.waitUntilExit()

            // On ne remplace l'appli que si le zip contient bien OsaNotch (même identifiant) :
            // avant, une décompression ratée supprimait l'appli sans rien remettre.
            let newApp = destFolder.appendingPathComponent("OsaNotch.app")
            guard proc.terminationStatus == 0,
                  let newId = Bundle(url: newApp)?.bundleIdentifier,
                  newId == Bundle.main.bundleIdentifier else { return fail() }

            // Script de remplacement
            let currentAppPath = Bundle.main.bundlePath
            let scriptPath = "/tmp/install_osanotch.sh"
            let script = """
            #!/bin/bash
            sleep 1
            rm -rf "\(currentAppPath)"
            ditto "\(newApp.path)" "\(currentAppPath)"
            rm -rf "\(destFolder.path)" "\(destZip.path)"
            open "\(currentAppPath)"
            """

            guard (try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)) != nil else { return fail() }
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            // Lancer le script de remplacement en arrière-plan et quitter
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: "/bin/bash")
            p2.arguments = [scriptPath]
            guard (try? p2.run()) != nil else { return fail() }

            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
        task.resume()
    }
}
