import SwiftUI
import AppKit

final class AutoUpdater: ObservableObject {
    static let shared = AutoUpdater()
    
    @Published var updateAvailable: String? = nil
    @Published var isUpdating: Bool = false
    
    private let repo = "osayanis/osanotch-native"
    private var downloadUrl: URL? = nil
    
    // Version actuelle (définie dans le code pour simplifier, ou via Info.plist)
    private let currentVersion = "1.0.0"
    
    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("OsaNotch Updater", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let assetUrlStr = asset["browser_download_url"] as? String,
                  let assetUrl = URL(string: assetUrlStr) else { return }
            
            let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
            if latestVersion != self.currentVersion {
                DispatchQueue.main.async {
                    self.updateAvailable = latestVersion
                    self.downloadUrl = assetUrl
                }
            }
        }.resume()
    }
    
    func installUpdate() {
        guard let url = downloadUrl, !isUpdating else { return }
        isUpdating = true
        
        let destZip = URL(fileURLWithPath: "/tmp/OsaNotch_update.zip")
        let destFolder = URL(fileURLWithPath: "/tmp/OsaNotch_update_extracted")
        
        // Téléchargement
        let task = URLSession.shared.downloadTask(with: url) { localURL, _, error in
            guard let localURL = localURL else {
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }
            
            try? FileManager.default.removeItem(at: destZip)
            try? FileManager.default.removeItem(at: destFolder)
            try? FileManager.default.copyItem(at: localURL, to: destZip)
            try? FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
            
            // Unzip
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-q", "-o", destZip.path, "-d", destFolder.path]
            try? proc.run()
            proc.waitUntilExit()
            
            // Script de remplacement
            let currentAppPath = Bundle.main.bundlePath
            let scriptPath = "/tmp/install_osanotch.sh"
            let script = """
            #!/bin/bash
            sleep 1
            rm -rf "\(currentAppPath)"
            cp -R "\(destFolder.path)/OsaNotch.app" "\(currentAppPath)"
            rm -rf "\(destFolder.path)" "\(destZip.path)"
            open "\(currentAppPath)"
            """
            
            try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
            
            // Lancer le script de remplacement en arrière-plan et quitter
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: "/bin/bash")
            p2.arguments = [scriptPath]
            try? p2.run()
            
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
        task.resume()
    }
}
