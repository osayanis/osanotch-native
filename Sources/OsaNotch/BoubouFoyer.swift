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
    struct Recette: Codable, Equatable { var id: String; var nom: String?; var emoji: String?; var ingredients: [String: Int]?; var effets: [String: Int]?; var soigne: Bool? }
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

/// Une petite scène jouée à la place du portrait après un geste (courses, bain, cuisine…).
/// La vue est `BoubouSceneView(nom:debut:etat:)` ; la durée de chaque scène est ici.
struct BoubouScene: Equatable {
    var nom: String
    var debut: Date
    static let durees: [String: Double] = ["courses": 4, "bain": 4, "cuisiner": 4, "nourrir": 3,
                                           "planter": 2.6, "arroser": 2.4, "recolter": 2.8]
}

/// Gerbe de particules (cœurs, gouttes, étincelles) : `n` change → une nouvelle gerbe part.
struct BoubouEclat: Equatable { var emoji = "✨"; var n = 0 }

// MARK: Client

@MainActor
final class BoubouFoyer: ObservableObject {
    static let shared = BoubouFoyer()

    @Published private(set) var etat: BoubouEtat?
    @Published private(set) var jeu: BoubouJeu?
    /// Petite phrase sous les actions (« Panier : 🥚🥛 », erreur du serveur…), effacée toute seule.
    @Published private(set) var flash: String?
    @Published private(set) var flashErreur = false
    /// Incrémenté à chaque geste (dès le clic) : Boubou fait un petit bond.
    @Published private(set) var bond = 0
    /// Scène en cours dans l'en-tête (nil = le portrait).
    @Published private(set) var scene: BoubouScene?
    /// Particules qui partent de Boubou à chaque geste.
    @Published private(set) var eclat = BoubouEclat()
    /// Des gestes partent ou attendent la réponse du serveur.
    var occupe: Bool { !attente.isEmpty }
    /// Décalage horloge serveur − horloge locale (pour la pousse du potager).
    private(set) var decalage: TimeInterval = 0

    /// Bannière notch (branché par AppModel) : titre, texte.
    var onNotice: ((String, String) -> Void)?

    private let bridge = FriendBridge.shared
    private var timer: Timer?
    private var flashWork: DispatchWorkItem?
    private var sinks = Set<AnyCancellable>()

    // Mise à jour optimiste : `confirme` = dernier état du serveur ; `etat` = `confirme` + les gestes
    // pas encore confirmés, prédits localement. Les gestes partent un par un, dans l'ordre des clics.
    private struct Geste { let id: Int; let type: String; let extra: [String: Any] }
    private var confirme: BoubouEtat?
    @Published private var attente: [Geste] = []
    private var prochainId = 0
    private var file: Task<Void, Never>?
    /// Horloge serveur du dernier état reçu : une réponse plus ancienne (relecture lente) est ignorée.
    private var dernierServeur: Double = 0
    private var derniereLecture = Date.distantPast
    private var sceneWork: DispatchWorkItem?

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
        // Le dernier état connu : l'onglet n'est jamais vide, même avant la première réponse.
        if let d = UserDefaults.standard.data(forKey: "OsaBoubouEtat"), let e = try? JSONDecoder().decode(BoubouEtat.self, from: d) {
            confirme = e; etat = e
        }
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
        guard actif else { etat = nil; confirme = nil; attente = []; return }
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
        if let m = etat.maintenant {
            guard m >= dernierServeur else { return }
            dernierServeur = m
            decalage = m / 1000 - Date().timeIntervalSince1970
        }
        confirme = etat
        UserDefaults.standard.set(d, forKey: "OsaBoubouEtat")
        recalculer()
        annoncer(etat)
    }

    /// `etat` = dernier état du serveur + gestes en attente (prédits). Animé : jauges et chiffres glissent.
    private func recalculer() {
        guard var e = confirme else { return }
        for g in attente { e = predire(e, g.type, g.extra) }
        if e != etat { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { etat = e } }
    }

    func relire() async {
        guard actif else { return }
        derniereLecture = Date()
        if jeu == nil { await chargerJeu() }
        guard let rep = await requete("api/foyer") else { return }
        appliquer(rep)
    }

    /// Ouverture de l'encoche : relit l'état s'il date de plus de 20 s (sans attendre, l'ancien reste affiché).
    func relireSiVieux() {
        guard actif, Date().timeIntervalSince(derniereLecture) > 20 else { return }
        Task { await relire() }
    }

    /// Un geste de Yanis. `extra` : champs du geste (plat, case, ingredients…).
    /// L'écran change tout de suite (prédiction), le serveur confirme ensuite ; en cas d'échec, on revient en arrière.
    func geste(_ type: String, _ extra: [String: Any] = [:]) {
        guard actif else { return }
        prochainId += 1
        let g = Geste(id: prochainId, type: type, extra: extra)
        attente.append(g)
        recalculer()
        if type != "lu" {
            bond += 1
            eclat = BoubouEclat(emoji: Self.emojiEclat[type] ?? "✨", n: eclat.n + 1)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            jouerScene(type)
        }
        let precedent = file
        file = Task { [weak self] in
            await precedent?.value
            await self?.envoyer(g)
        }
    }

    private func envoyer(_ g: Geste) async {
        var corps = g.extra; corps["qui"] = "yanis"; corps["type"] = g.type
        let rep = await requete("api/foyer/action", corps: corps)
        attente.removeAll { $0.id == g.id }
        guard let rep else {
            recalculer()
            if scene?.nom == g.type { arreterScene() }
            return montrer("Pas de connexion au foyer", erreur: true)
        }
        appliquer(rep)
        recalculer()
        if rep["ok"] as? Bool == true {
            guard g.type != "lu" else { return }
            bridge.sendBoubouMaj(quoi: g.type)
            let r = rep["resultat"] as? [String: Any] ?? [:]
            if r["niveau"] != nil { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
            montrer(phrase(g.type, r), erreur: false)
        } else {
            if scene?.nom == g.type { arreterScene() }
            let e = rep["erreur"] as? String ?? "Raté"
            montrer(e == "foyer" ? "Le foyer ne répond pas" : e, erreur: true)
        }
    }

    private static let emojiEclat = ["calin": "❤️", "bain": "🫧", "nourrir": "✨", "courses": "🥕", "cuisiner": "✨",
                                     "planter": "🌱", "arroser": "💧", "recolter": "🌟", "dodo": "💤", "reveil": "☀️", "habiller": "✨"]

    private func jouerScene(_ type: String) {
        guard let duree = BoubouScene.durees[type] else { return }
        let s = BoubouScene(nom: type, debut: Date())
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { scene = s }
        sceneWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.scene == s else { return }
            self.arreterScene()
        }
        sceneWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + duree, execute: w)
    }

    private func arreterScene() {
        sceneWork?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { scene = nil }
    }

    // MARK: Prédiction locale (simple : le serveur a toujours le dernier mot)

    private func predire(_ e0: BoubouEtat, _ type: String, _ x: [String: Any]) -> BoubouEtat {
        var e = e0
        let j = jeu
        func stat(_ k: String, _ d: Int) {
            var s = e.stats ?? BoubouEtat.Stats()
            func borne(_ v: Int?) -> Int { max(0, min(100, (v ?? 50) + d)) }
            switch k {
            case "ventre": s.ventre = borne(s.ventre)
            case "calins": s.calins = borne(s.calins)
            case "toilette": s.toilette = borne(s.toilette)
            case "energie": s.energie = borne(s.energie)
            default: break
            }
            e.stats = s
        }
        func retire(_ dict: inout [String: Int]?, _ k: String, _ n: Int = 1) {
            var d = dict ?? [:]
            d[k] = max(0, (d[k] ?? 0) - n)
            if d[k] == 0 { d[k] = nil }
            dict = d
        }
        switch type {
        case "calin": stat("calins", 12)
        case "bain": stat("toilette", 100)
        case "jouer": stat("calins", 8); stat("energie", -6)
        case "nourrir":
            if let p = x["plat"] as? String {
                retire(&e.frigo, p)
                for (k, v) in j?.plat(p)?.effets ?? ["ventre": 35] { stat(k, v) }
                if j?.plat(p)?.soigne == true { e.malade = false }
            } else if let i = x["ingredient"] as? String {
                retire(&e.inventaire, i)
                for (k, v) in j?.cru?[i] ?? ["ventre": 5] { stat(k, v) }
            }
        case "dodo": e.dort = true; e.humeur = "dort"
        case "reveil": e.dort = false; if e.humeur == "dort" { e.humeur = "calme" }
        case "courses": e.coursesFaites = true
        case "habiller": e.accessoire = x["accessoire"] as? String
        case "cuisiner": for i in x["ingredients"] as? [String] ?? [] { retire(&e.inventaire, i) }
        case "planter", "arroser", "recolter":
            guard let i = x["case"] as? Int, var cases = e.potager, i >= 0, i < cases.count else { break }
            let maintenant = (Date().timeIntervalSince1970 + decalage) * 1000
            if type == "planter", let p = x["plante"] as? String {
                let h = j?.plantes?[p]?.heures ?? 1
                cases[i] = BoubouEtat.Case(plante: p, plantee: maintenant, arrosee: false, par: "yanis", prete: false, fin: maintenant + h * 3_600_000)
            } else if type == "arroser", var c = cases[i] {
                c.arrosee = true
                if let debut = c.plantee, let fin = c.fin, fin > maintenant { c.fin = maintenant + (fin - maintenant) * 0.65; _ = debut }
                cases[i] = c
            } else if type == "recolter", let c = cases[i], let p = c.plante {
                var inv = e.inventaire ?? [:]
                inv[p, default: 0] += j?.plantes?[p]?.recolte ?? 1
                e.inventaire = inv
                cases[i] = nil
            }
            e.potager = cases
        case "lu": e.mots = e.mots?.map { var m = $0; m.lu = true; return m }
        default: break
        }
        return e
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
                f.etat = v; f.confirme = v
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
            ("scene-courses", BoubouPanneau(rubrique: .soins, apercu: true, sceneApercu: BoubouScene(nom: "courses", debut: Date()))),
        ]
        for (nom, vue) in scenes {
            let r = ImageRenderer(content: vue.frame(width: 480, height: 352 - 40).background(Color.black).environment(\.colorScheme, .dark))
            r.scale = 2
            if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: dossier.appendingPathComponent("\(nom).png"))
            }
        }
    }

    /// `OSA_BOUBOU_API=http://127.0.0.1:… OsaNotch essai-boubou` : gestes rapides contre un serveur local,
    /// vérifie la prédiction immédiate, la file, la confirmation et le retour arrière. Jamais contre la prod.
    static func essai() async -> Bool {
        guard let api = ProcessInfo.processInfo.environment["OSA_BOUBOU_API"], api.contains("127.0.0.1") else {
            print("OSA_BOUBOU_API doit pointer vers un serveur local"); return false
        }
        let f = BoubouFoyer.shared
        f.demarrer()
        for _ in 0..<50 where f.confirme == nil { try? await Task.sleep(for: .milliseconds(100)) }
        guard let e0 = f.etat else { print("✗ pas d'état"); return false }
        var ok = true
        func verifie(_ titre: String, _ cond: Bool) { print("\(cond ? "✓" : "✗") \(titre)"); if !cond { ok = false } }
        let c0 = e0.stats?.calins ?? 0, t0 = e0.stats?.toilette ?? 0
        let horloge = Date()
        f.geste("calin"); f.geste("calin"); f.geste("bain"); f.geste("planter", ["case": 5, "plante": "carotte"])
        let immediat = Date().timeIntervalSince(horloge) * 1000
        verifie(String(format: "4 gestes envoyés sans attendre (%.1f ms)", immediat), immediat < 50)
        verifie("câlins prédits tout de suite (\(c0) → \(f.etat?.stats?.calins ?? -1))", (f.etat?.stats?.calins ?? 0) == min(100, c0 + 24))
        verifie("toilette prédite à 100 (\(t0) → \(f.etat?.stats?.toilette ?? -1))", f.etat?.stats?.toilette == 100)
        verifie("case 5 plantée tout de suite", f.etat?.potager?[5]?.plante == "carotte")
        verifie("scène lancée (\(f.scene?.nom ?? "-"))", f.scene?.nom == "planter")
        verifie("occupé pendant l'envoi", f.occupe)
        await f.file?.value
        verifie("file vidée", !f.occupe)
        verifie("état = celui du serveur après confirmation", f.etat == f.confirme)
        verifie("case 5 confirmée par le serveur", f.confirme?.potager?[5]?.plante == "carotte")
        // Échec : récolter une case pas mûre → retour en arrière + message
        let avant = f.etat
        f.geste("recolter", ["case": 5])
        verifie("récolte prédite (case vidée)", f.etat?.potager?[5] == nil)
        await f.file?.value
        verifie("retour en arrière après refus (case de nouveau plantée)", f.etat?.potager?[5]?.plante == "carotte" && f.etat?.potager == avant?.potager)
        verifie("message d'erreur affiché (\(f.flash ?? "-"))", f.flashErreur && f.flash != nil)
        return ok
    }

    /// Clés UserDefaults propres à l'onglet (pour tout effacer après un test).
    static let cles = ["OsaMochiFoyer", "OsaBoubouJeu", "OsaBoubouEtat", "OsaBoubouMotsVus", "OsaBoubouMalade", "OsaBoubouNiveau"]
}
