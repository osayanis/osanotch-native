import AppKit
import Combine

// Historique du presse-papier : garde les 20 derniers textes copiés.
// Cliquer un élément le recopie dans le presse-papier.
final class ClipboardManager: ObservableObject {
    @Published var items: [String] = []

    private var lastChange: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxItems = 20
    private let key = "osa.clipboard.history"
    // Les gestionnaires de mots de passe marquent leurs copies comme "concealed" → on les ignore.
    private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init() {
        items = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func start() {
        lastChange = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        let types = pb.types ?? []
        if types.contains(concealed) || types.contains(transient) { return }  // mot de passe / éphémère
        guard let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        add(s)
    }

    private func add(_ s: String) {
        DispatchQueue.main.async {
            self.items.removeAll { $0 == s }
            self.items.insert(s, at: 0)
            if self.items.count > self.maxItems { self.items = Array(self.items.prefix(self.maxItems)) }
            UserDefaults.standard.set(self.items, forKey: self.key)
        }
    }

    // Recopie un élément dans le presse-papier et le remonte en tête.
    func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastChange = pb.changeCount     // ne pas le re-capturer comme une nouvelle copie
        add(s)
    }

    func remove(_ s: String) {
        items.removeAll { $0 == s }
        UserDefaults.standard.set(items, forKey: key)
    }

    func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
