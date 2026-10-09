import SwiftUI
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

// Presse-papier de fichiers (« étagère ») : garde plusieurs fichiers déposés sur le notch,
// persistés entre deux lancements. Chaque fichier peut être re-glissé ailleurs, ouvert,
// copié ou partagé (AirDrop / OsaDrop).
final class FileShelf: ObservableObject {
    @Published private(set) var items: [URL] = []
    @Published var selected: URL?
    @Published var dragging: URL?   // fichier en cours de glisser (pour l'animation)

    private let key = "fileShelf.paths"
    private let maxItems = 30
    private let thumbs = NSCache<NSURL, NSImage>()

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // AirDrop envoie la sélection, sinon tout le presse-papier.
    var shareSet: [URL] { selected.map { [$0] } ?? items }

    // Ajoute en tête (sans doublon). Un fichier seul est sélectionné d'office → prêt pour OsaDrop.
    func add(_ urls: [URL]) {
        let fresh = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !fresh.isEmpty else { return }
        var list = items
        for u in fresh.reversed() {
            list.removeAll { $0 == u }
            list.insert(u, at: 0)
        }
        items = Array(list.prefix(maxItems))
        selected = fresh.count == 1 ? fresh[0] : nil
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        if selected == url { selected = nil }
        if dragging == url { dragging = nil }
        save()
    }

    func clear() { items = []; selected = nil; save() }

    func toggleSelect(_ url: URL) { selected = (selected == url) ? nil : url }

    // Retire les fichiers qui n'existent plus (déplacés ou supprimés depuis).
    func prune() {
        let kept = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard kept != items else { return }
        items = kept
        if let s = selected, !kept.contains(s) { selected = nil }
        save()
    }

    private func save() { UserDefaults.standard.set(items.map(\.path), forKey: key) }

    // Miniature Quick Look (aperçu réel pour images/PDF…), icône Finder en attendant.
    func thumbnail(for url: URL, size: CGSize, _ done: @escaping (NSImage) -> Void) {
        if let img = thumbs.object(forKey: url as NSURL) { done(img); return }
        done(NSWorkspace.shared.icon(forFile: url.path))
        let req = QLThumbnailGenerator.Request(fileAt: url, size: size,
                                               scale: NSScreen.main?.backingScaleFactor ?? 2,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let rep else { return }
            let img = rep.nsImage
            DispatchQueue.main.async {
                self?.thumbs.setObject(img, forKey: url as NSURL)
                done(img)
            }
        }
    }

    // Glisser vers l'extérieur : le fichier ne quitte le presse-papier que si une destination
    // accepte réellement le dépôt (glisser annulé → le gestionnaire n'est pas appelé, il reste).
    func dragProvider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        let typeID = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
        provider.suggestedName = url.lastPathComponent
        provider.registerFileRepresentation(forTypeIdentifier: typeID, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { self.remove(url) }
            }
            return nil
        }
        return provider
    }

    // Début de glisser : retour haptique, puis on surveille le relâchement du bouton
    // (AppKit ne signale pas l'annulation à SwiftUI) pour libérer l'emplacement fantôme.
    func beginDrag(_ url: URL) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragging = url }
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            t.invalidate()
            // Laisse le temps au dépôt d'être accepté (→ retrait animé) avant de « revenir ».
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard let self, self.dragging == url else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { self.dragging = nil }
            }
        }
    }

    static func airdrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let svc = NSSharingService(named: .sendViaAirDrop) ?? NSSharingService(named: NSSharingService.Name("com.apple.share.AirDrop.send"))
        svc?.perform(withItems: urls)
    }

    static func copyToPasteboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }
}
