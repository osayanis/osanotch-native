import SwiftUI
import AppKit
import Combine

// Le foyer de Boubou : Boubou qu'on élève à deux. Jeanne dans l'app Boubou, Yanis ici.
// Toute la logique est sur le serveur (boubou.osalabs.fr, voir boubou-site/docs/foyer.md) :
// on relit l'état, on envoie des gestes, et on affiche. N'existe que si un Boubou avec un secret
// de foyer s'est présenté (FriendBridge.mochiFoyer) : rien ne change pour les autres utilisateurs.

// MARK: Modèles (tolérants : tout champ absent reste nil)

struct BoubouEtat: Decodable, Equatable {
    struct Stats: Decodable, Equatable { var ventre: Int?; var calins: Int?; var toilette: Int?; var energie: Int? }
    struct Suivant: Decodable, Equatable { var nom: String?; var xp: Int? }
    struct Niveau: Decodable, Equatable { var n: Int?; var nom: String?; var xp: Int?; var suivant: Suivant? }
    struct Case: Decodable, Equatable { var plante: String?; var plantee: Double?; var arrosee: Bool?; var par: String?; var prete: Bool?; var fin: Double? }
    struct Evenement: Decodable, Equatable, Hashable { var quand: Double?; var qui: String?; var emoji: String?; var texte: String?; var type: String?; var detail: String? }
    struct Mot: Decodable, Equatable, Identifiable { var id: String; var quand: Double?; var texte: String?; var lu: Bool? }

    var stats: Stats?
    var humeur: String?
    var malade: Bool?
    var dort: Bool?
    var xp: Int?
    var niveau: Niveau?
    var etoiles: Int?
    var inventaire: [String: Int]?
    var frigo: [String: Int]?
    var potager: [Case?]?
    var recettes: [String]?
    var accessoire: String?
    var accessoires: [String]?
    var coursesFaites: Bool?
    var journal: [Evenement]?
    var mots: [Mot]?
    var maintenant: Double?
}

struct BoubouJeu: Codable, Equatable {
    struct Ingredient: Codable, Equatable { var nom: String?; var emoji: String?; var un: String?; var prix: Int?; var potager: Bool?; var rare: Bool? }
    struct Plante: Codable, Equatable { var heures: Double?; var recolte: Int? }
    struct Recette: Codable, Equatable { var id: String; var nom: String?; var emoji: String?; var ingredients: [String: Int]?; var soigne: Bool? }
    struct Niveau: Codable, Equatable { var n: Int?; var nom: String?; var xp: Int?; var cadeau: String? }
    struct Accessoire: Codable, Equatable { var nom: String?; var emoji: String?; var niveau: Int? }

    var ingredients: [String: Ingredient]?
    var plantes: [String: Plante]?
    var recettes: [Recette]?
    var mystere: Recette?
    var cru: [String: [String: Int]]?
    var niveaux: [Niveau]?
    var accessoires: [String: Accessoire]?

    func emoji(_ id: String) -> String { ingredients?[id]?.emoji ?? plat(id)?.emoji ?? "•" }
    func nom(_ id: String) -> String { ingredients?[id]?.nom ?? plat(id)?.nom ?? id }
    func plat(_ id: String) -> Recette? { id == "mystere" ? mystere : recettes?.first { $0.id == id } }
    /// Ordre d'affichage stable des plantes (comme le serveur : de la plus rapide à la plus lente).
    var plantesTriees: [(String, Plante)] { (plantes ?? [:]).sorted { ($0.value.heures ?? 0) < ($1.value.heures ?? 0) } }
}

// MARK: Client

@MainActor
final class BoubouFoyer: ObservableObject {
    static let shared = BoubouFoyer()

    @Published private(set) var etat: BoubouEtat?
    @Published private(set) var jeu: BoubouJeu?
    /// Petite phrase sous les actions (« Panier : 🥚🥛 », erreur du serveur…), effacée toute seule.
    @Published private(set) var flash: String?
    @Published private(set) var flashErreur = false
    @Published private(set) var occupe = false
    /// Incrémenté à chaque geste réussi : Boubou fait un petit bond.
    @Published private(set) var bond = 0
    /// Décalage horloge serveur − horloge locale (pour la pousse du potager).
    private(set) var decalage: TimeInterval = 0

    /// Bannière notch (branché par AppModel) : titre, texte.
    var onNotice: ((String, String) -> Void)?

    private let bridge = FriendBridge.shared
    private var timer: Timer?
    private var flashWork: DispatchWorkItem?
    private var sinks = Set<AnyCancellable>()

    private static var base: URL {
        let env = ProcessInfo.processInfo.environment["OSA_BOUBOU_API"].flatMap { URL(string: $0) }
        return env ?? URL(string: "https://boubou.osalabs.fr")!
    }

    /// Un Boubou avec foyer est appairé : l'onglet existe.
    var actif: Bool { bridge.mochi != nil && bridge.mochiFoyer != nil }
    var nomJeanne: String { bridge.mochi?.name ?? "Jeanne" }
    var motsNonLus: Int { etat?.mots?.filter { $0.lu != true }.count ?? 0 }

    private init() {
        if let d = UserDefaults.standard.data(forKey: "OsaBoubouJeu"), let j = try? JSONDecoder().decode(BoubouJeu.self, from: d) { jeu = j }
        bridge.onBoubouMaj = { [weak self] _ in Task { @MainActor in await self?.relire() } }
        // Appairage (ou secret) qui arrive / change : on démarre ou on arrête.
        bridge.$mochiFoyer.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.demarrer() }
        }.store(in: &sinks)
        bridge.$mochi.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }.store(in: &sinks)
    }

    func demarrer() {
        timer?.invalidate(); timer = nil
        guard actif else { etat = nil; return }
        Task { await chargerJeu(); await relire() }
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.relire() }
        }
    }

    // MARK: Réseau

    private func requete(_ chemin: String, corps: [String: Any]? = nil) async -> [String: Any]? {
        guard let secret = bridge.mochiFoyer else { return nil }
        var r = URLRequest(url: Self.base.appendingPathComponent(chemin))
        r.timeoutInterval = 12
        r.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let corps {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: corps)
        }
        guard let (d, _) = try? await URLSession.shared.data(for: r) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private func chargerJeu() async {
        var r = URLRequest(url: Self.base.appendingPathComponent("api/foyer/jeu"))
        r.timeoutInterval = 12
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let j = try? JSONDecoder().decode(BoubouJeu.self, from: d) else { return }
        jeu = j
        UserDefaults.standard.set(d, forKey: "OsaBoubouJeu")
    }

    private func appliquer(_ rep: [String: Any]) {
        guard let e = rep["etat"], let d = try? JSONSerialization.data(withJSONObject: e),
              let etat = try? JSONDecoder().decode(BoubouEtat.self, from: d) else { return }
        if let m = etat.maintenant { decalage = m / 1000 - Date().timeIntervalSince1970 }
        if self.etat != etat { self.etat = etat }
        annoncer(etat)
    }

    func relire() async {
        guard actif else { return }
        if jeu == nil { await chargerJeu() }
        guard let rep = await requete("api/foyer") else { return }
        appliquer(rep)
    }

    /// Un geste de Yanis. `extra` : champs du geste (plat, case, ingredients…).
    func geste(_ type: String, _ extra: [String: Any] = [:]) {
        guard actif, !occupe else { return }
        occupe = true
        Task {
            var corps = extra; corps["qui"] = "yanis"; corps["type"] = type
            let rep = await requete("api/foyer/action", corps: corps)
            occupe = false
            guard let rep else { return montrer("Pas de connexion au foyer", erreur: true) }
            appliquer(rep)
            if rep["ok"] as? Bool == true {
                if type != "lu" {
                    bond += 1
                    bridge.sendBoubouMaj(quoi: type)
                    montrer(phrase(type, rep["resultat"] as? [String: Any] ?? [:]), erreur: false)
                }
            } else {
                let e = rep["erreur"] as? String ?? "Raté"
                montrer(e == "foyer" ? "Le foyer ne répond pas" : e, erreur: true)
            }
        }
    }

    func marquerLus() {
        guard motsNonLus > 0 else { return }
        geste("lu", ["tout": true])
    }

    private func montrer(_ texte: String?, erreur: Bool) {
        guard let texte, !texte.isEmpty else { return }
        flashWork?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { flash = texte; flashErreur = erreur }
        let w = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.25)) { self?.flash = nil } }
        flashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (erreur ? 3 : 3.5), execute: w)
    }

    /// Phrase de retour selon ce que le serveur a renvoyé.
    private func phrase(_ type: String, _ r: [String: Any]) -> String? {
        let j = jeu
        func liste(_ any: Any?) -> String {
            guard let d = any as? [String: Any] else { return "" }
            return d.compactMap { k, v -> String? in
                guard let n = v as? Int else { return nil }
                return String(repeating: j?.emoji(k) ?? "•", count: max(1, min(n, 6)))
            }.sorted().joined(separator: " ")
        }
        if let niv = r["niveau"] as? [String: Any], let nom = niv["nom"] as? String { return "🎓 Boubou passe \(nom) !" }
        switch type {
        case "courses": return "🛒 Panier : \(liste(r["panier"]))"
        case "cuisiner":
            guard let id = r["plat"] as? String else { return nil }
            if id == "mystere" { return "❓ Un plat mystère… on verra bien" }
            let p = j?.plat(id)
            return "\(p?.emoji ?? "🍽️") \(p?.nom ?? id)\(r["nouvelle"] as? Bool == true ? " · nouvelle recette ✨" : "")"
        case "recolter": return "Récolte : \(liste(r["recolte"]))"
        case "nourrir":
            if r["gueri"] as? Bool == true { return "💚 Guéri ! Merci docteur" }
            if let d = r["mystere"] as? Int { return d >= 0 ? "Miam… étonnamment bon 😋" : "Hmm… c'était spécial 😅" }
            return "Miam ! 😋"
        case "calin": return "🤗 Câlin donné"
        case "bain": return "🛁 Tout propre !"
        case "planter": return "🌱 C'est planté"
        case "arroser": return "💧 Ça poussera plus vite"
        case "dodo": return "💤 Bonne nuit Boubou"
        case "reveil": return "☀️ Debout !"
        case "habiller": return "✨ Trop beau"
        default: return nil
        }
    }

    // MARK: Bannières (avec retenue : mots de Jeanne, rhume, niveau)

    private func annoncer(_ e: BoubouEtat) {
        let ud = UserDefaults.standard
        // Mots de Jeanne jamais montrés en bannière
        var vus = Set(ud.stringArray(forKey: "OsaBoubouMotsVus") ?? [])
        let nouveaux = (e.mots ?? []).filter { $0.lu != true && !vus.contains($0.id) }
        // Du plus ancien au plus récent (la bannière garde le dernier, « +N » pour les autres)
        for m in nouveaux.reversed().suffix(5) {
            onNotice?("💌 \(nomJeanne)", m.texte ?? "")
        }
        if !nouveaux.isEmpty {
            nouveaux.forEach { vus.insert($0.id) }
            // On ne garde que les ids encore présents côté serveur (+ les nouveaux)
            let presents = Set((e.mots ?? []).map(\.id))
            ud.set(Array(vus.intersection(presents)), forKey: "OsaBoubouMotsVus")
        }
        // Rhume
        let malade = e.malade == true
        if ud.object(forKey: "OsaBoubouMalade") != nil, malade, !ud.bool(forKey: "OsaBoubouMalade") {
            onNotice?("Boubou", "Boubou a attrapé un rhume 🤧 Une soupe ou une tisane ?")
        }
        ud.set(malade, forKey: "OsaBoubouMalade")
        // Niveau
        if let n = e.niveau?.n {
            let avant = ud.integer(forKey: "OsaBoubouNiveau")
            if avant > 0, n > avant { onNotice?("Boubou", "🎓 Boubou passe \(e.niveau?.nom ?? "au niveau suivant") !") }
            ud.set(n, forKey: "OsaBoubouNiveau")
        }
    }

    /// `OsaNotch apercu-boubou <etat.json> <jeu.json> <dossier>` : l'onglet rendu hors écran, sans réseau.
    static func apercu(etat: Data, jeu: Data, dossier: URL) {
        let f = BoubouFoyer.shared
        f.timer?.invalidate()
        if let j = try? JSONDecoder().decode(BoubouJeu.self, from: jeu) { f.jeu = j }
        if let obj = (try? JSONSerialization.jsonObject(with: etat)) as? [String: Any] {
            let e = obj["etat"] ?? obj
            if let d = try? JSONSerialization.data(withJSONObject: e), let v = try? JSONDecoder().decode(BoubouEtat.self, from: d) {
                f.etat = v
                if let m = v.maintenant { f.decalage = m / 1000 - Date().timeIntervalSince1970 }
            }
        }
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let scenes: [(String, BoubouPanneau)] = [
            ("soins", BoubouPanneau(rubrique: .soins, apercu: true)),
            ("nourrir", BoubouPanneau(rubrique: .soins, choix: .nourrir, apercu: true)),
            ("habiller", BoubouPanneau(rubrique: .soins, choix: .habiller, apercu: true)),
            ("cuisine", BoubouPanneau(rubrique: .cuisine, marmite: ["farine", "oeuf"], apercu: true)),
            ("potager", BoubouPanneau(rubrique: .potager, choix: .planter(1), apercu: true)),
            ("journal", BoubouPanneau(rubrique: .journal, apercu: true)),
        ]
        for (nom, vue) in scenes {
            let r = ImageRenderer(content: vue.frame(width: 480, height: 352 - 40).background(Color.black).environment(\.colorScheme, .dark))
            r.scale = 2
            if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: dossier.appendingPathComponent("\(nom).png"))
            }
        }
    }

    /// Clés UserDefaults propres à l'onglet (pour tout effacer après un test).
    static let cles = ["OsaMochiFoyer", "OsaBoubouJeu", "OsaBoubouMotsVus", "OsaBoubouMalade", "OsaBoubouNiveau"]
}
