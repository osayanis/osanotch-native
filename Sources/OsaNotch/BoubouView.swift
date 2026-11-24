import SwiftUI

/// Onglet « Boubou » : élever Boubou avec Jeanne. Visible seulement si son Boubou est appairé
/// avec un foyer (BoubouFoyer.actif). Aucun moyen de répondre aux mots de Jeanne : c'est voulu.
struct BoubouView: View {
    @ObservedObject var model: AppModel
    var accent: Color

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(model: model, accent: accent, dropHover: false, battery: model.data.battery, lowBat: (model.data.battery?.percent ?? 100) < 20)
            BoubouPanneau()
        }
    }
}

/// Le contenu de l'onglet (sans la barre d'onglets) : rendu aussi hors écran par `OsaNotch apercu-boubou`.
struct BoubouPanneau: View {
    @ObservedObject private var foyer = BoubouFoyer.shared

    enum Rubrique: String, CaseIterable { case soins = "Soins", cuisine = "Cuisine", potager = "Potager", journal = "Journal" }
    enum Choix: Equatable { case nourrir, habiller, planter(Int) }

    @State private var rubrique: Rubrique
    @State private var choix: Choix?
    @State private var marmite: [String]
    /// Une gerbe par bouton (clé = titre) : compteur qui change à chaque clic.
    @State private var tirs: [String: Int] = [:]
    /// Sens du glissement entre rubriques (+1 vers la droite).
    @State private var sens: CGFloat = 1
    private let apercu: Bool
    private let sceneApercu: BoubouScene?

    init(rubrique: Rubrique = .soins, choix: Choix? = nil, marmite: [String] = [], apercu: Bool = false, sceneApercu: BoubouScene? = nil) {
        _rubrique = State(initialValue: rubrique); _choix = State(initialValue: choix); _marmite = State(initialValue: marmite)
        self.apercu = apercu; self.sceneApercu = sceneApercu
    }

    private var glisse: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: 14 * sens)),
                    removal: .opacity.combined(with: .offset(x: -10 * sens)))
    }

    private let rose = Color(red: 1, green: 0.55, blue: 0.65)
    private let vert = Color(red: 0.36, green: 0.72, blue: 0.68)

    var body: some View {
        VStack(spacing: 0) {
            if let e = foyer.etat {
                VStack(spacing: 10) {
                    entete(e)
                    rubriques
                    ZStack(alignment: .bottom) {
                        Group {
                            switch rubrique {
                            case .soins: soins(e)
                            case .cuisine: cuisine(e)
                            case .potager: potager(e)
                            case .journal: journal(e)
                            }
                        }
                        .id(rubrique)
                        .transition(glisse)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        if let f = foyer.flash {
                            Text(f)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(foyer.flashErreur ? Color(red: 1, green: 0.6, blue: 0.55) : .white)
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(Color(white: 0.16)))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
            } else {
                VStack(spacing: 6) {
                    BoubouPortrait(humeur: "calme", dort: false, malade: false, accessoire: nil, size: 56)
                    Text("Boubou arrive…").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if !apercu { Task { await foyer.relire(); foyer.marquerLus() } } }
        .onChange(of: foyer.motsNonLus) { _, n in if n > 0 && !apercu { foyer.marquerLus() } }
        .onChange(of: rubrique) { _, _ in choix = nil }
    }

    // MARK: En-tête : Boubou, niveau, jauges

    func entete(_ e: BoubouEtat) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                if let sc = sceneApercu ?? foyer.scene {
                    BoubouSceneView(nom: sc.nom, debut: sc.debut, etat: e)
                        .id(sc.debut)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    BoubouPortrait(humeur: e.humeur ?? "calme", dort: e.dort == true, malade: e.malade == true,
                                   accessoire: e.accessoire, sale: (e.stats?.toilette ?? 100) < 20, size: 54, hop: foyer.bond)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .frame(width: 84, height: 66)
            .modifier(Gerbe(emoji: foyer.eclat.emoji, declencheur: foyer.eclat.n, taille: 13))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(e.niveau?.nom ?? "P1").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
                    xpBarre(e).frame(width: 92)
                    Spacer(minLength: 0)
                    Text("⭐ \(e.etoiles ?? 0)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.7))
                        .contentTransition(.numericText(value: Double(e.etoiles ?? 0)))
                        .help("Étoiles : Jeanne les gagne en travaillant dans Boubou")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 6) {
                    jauge("🍽️", "Ventre", e.stats?.ventre)
                    jauge("❤️", "Câlins", e.stats?.calins)
                    jauge("🛁", "Toilette", e.stats?.toilette)
                    jauge("⚡", "Énergie", e.stats?.energie)
                }
            }
        }
    }

    func xpBarre(_ e: BoubouEtat) -> some View {
        let bas = Double(e.niveau?.xp ?? 0), haut = Double(e.niveau?.suivant?.xp ?? Int(bas + 1)), xp = Double(e.xp ?? 0)
        let frac = e.niveau?.suivant == nil ? 1 : max(0, min(1, (xp - bas) / max(1, haut - bas)))
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(vert).frame(width: max(4, g.size.width * frac))
            }
        }
        .frame(height: 4)
        .help(e.niveau?.suivant.map { "\(e.xp ?? 0) / \($0.xp ?? 0) XP → \($0.nom ?? "")" } ?? "Niveau maximum")
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: frac)
    }

    func jauge(_ emoji: String, _ nom: String, _ v: Int?) -> some View {
        let val = Double(v ?? 0) / 100
        let couleur: Color = val < 0.2 ? Color(red: 1, green: 0.45, blue: 0.4) : val < 0.4 ? Color(red: 1, green: 0.75, blue: 0.35) : .white.opacity(0.85)
        return HStack(spacing: 6) {
            Text(emoji).font(.system(size: 11))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(couleur).frame(width: max(4, g.size.width * val))
                }
            }
            .frame(height: 5)
            Text("\(v ?? 0)").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText(value: Double(v ?? 0)))
                .foregroundColor(.white.opacity(0.5)).frame(width: 22, alignment: .trailing)
        }
        .help(nom)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: val)
    }

    // MARK: Rubriques

    var rubriques: some View {
        HStack(spacing: 6) {
            ForEach(Rubrique.allCases, id: \.self) { r in
                Button {
                    let a = Rubrique.allCases.firstIndex(of: rubrique) ?? 0, b = Rubrique.allCases.firstIndex(of: r) ?? 0
                    sens = b >= a ? 1 : -1
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { rubrique = r }
                } label: {
                    HStack(spacing: 4) {
                        Text(r.rawValue)
                        if r == .journal && foyer.motsNonLus > 0 { Circle().fill(rose).frame(width: 5, height: 5) }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(rubrique == r ? .black : .white.opacity(0.6))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Capsule().fill(rubrique == r ? Color.white : Color.white.opacity(0.07)))
                    .contentShape(Capsule())
                }
                .buttonStyle(Appui())
            }
            Spacer(minLength: 0)
            // Un geste part : simple point qui respire (rien ne bloque, l'écran a déjà changé)
            Circle().fill(.white.opacity(0.5)).frame(width: 4, height: 4)
                .opacity(foyer.occupe ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: foyer.occupe)
        }
    }

    // MARK: Soins

    func allerA(_ c: Choix?) {
        sens = c == nil ? -1 : 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { choix = c }
    }

    @ViewBuilder func soins(_ e: BoubouEtat) -> some View {
        if choix == .nourrir { nourrir(e).transition(glisse) }
        else if choix == .habiller { habiller(e).transition(glisse) }
        else {
            let dort = e.dort == true
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                tuile("🤗", "Câlin", gerbe: "❤️") { foyer.geste("calin") }
                tuile("🛁", "Bain", gerbe: "🫧", off: dort) { foyer.geste("bain") }
                tuile("🍽️", "Nourrir", plus: true, off: dort) { allerA(.nourrir) }
                tuile("🛒", e.coursesFaites == true ? "Courses faites" : "Faire les courses", cle: "courses", gerbe: "🥕",
                      vedette: e.coursesFaites != true, off: e.coursesFaites == true) { foyer.geste("courses") }
                tuile(dort ? "☀️" : "💤", dort ? "Réveiller" : "Coucher", cle: "dodo", gerbe: dort ? "☀️" : "💤") { foyer.geste(dort ? "reveil" : "dodo") }
                tuile("✨", "Habiller", plus: true) { allerA(.habiller) }
            }
            .transition(glisse)
        }
    }

    func tuile(_ emoji: String, _ titre: String, cle: String? = nil, gerbe: String? = nil, plus: Bool = false, vedette: Bool = false, off: Bool = false,
               _ action: @escaping () -> Void) -> some View {
        Button {
            if gerbe != nil { tirs[cle ?? titre, default: 0] += 1 }
            action()
        } label: {
            HStack(spacing: 7) {
                Text(emoji).font(.system(size: 15))
                Text(titre).font(.system(size: 11.5, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if plus { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).opacity(0.4) }
            }
            .foregroundColor(vedette ? .black : .white)
            .padding(.horizontal, 10).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11).fill(vedette ? vert : Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(vedette ? 0 : 0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(Appui())
        .disabled(off)
        .opacity(off ? 0.4 : 1)
        .modifier(Gerbe(emoji: gerbe ?? "✨", declencheur: tirs[cle ?? titre] ?? 0))
    }

    func retour(_ titre: String) -> some View {
        HStack(spacing: 6) {
            Button { allerA(nil) } label: {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.7))
                    .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.08))).contentShape(Circle())
            }.buttonStyle(Appui())
            Text(titre).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.8))
            Spacer()
        }
    }

    func nourrir(_ e: BoubouEtat) -> some View {
        let j = foyer.jeu
        let plats = (e.frigo ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }
        let crus = (e.inventaire ?? [:]).filter { $0.value > 0 && j?.cru?[$0.key] != nil }.sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 8) {
            retour("Qu'est-ce qu'on lui donne ?")
            if plats.isEmpty && crus.isEmpty {
                Text("Frigo vide : fais les courses ou cuisine un petit plat.").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            Defile(apercu: apercu) {
                Flux(espace: 6) {
                    ForEach(plats, id: \.key) { k, n in
                        puce("\(j?.emoji(k) ?? "🍽️") \(j?.nom(k) ?? k)", n: n, fort: true) { foyer.geste("nourrir", ["plat": k]); allerA(nil) }
                    }
                    ForEach(crus, id: \.key) { k, n in
                        puce("\(j?.emoji(k) ?? "•") \(j?.nom(k) ?? k)", n: n) { foyer.geste("nourrir", ["ingredient": k]); allerA(nil) }
                    }
                }
            }
        }
    }

    func habiller(_ e: BoubouEtat) -> some View {
        let j = foyer.jeu
        let dispo = e.accessoires ?? []
        let tous = (j?.accessoires ?? [:]).sorted { ($0.value.niveau ?? 0) < ($1.value.niveau ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            retour("Garde-robe")
            Flux(espace: 6) {
                puce("Rien", choisi: e.accessoire == nil) { foyer.geste("habiller", ["accessoire": NSNull()]); allerA(nil) }
                ForEach(tous, id: \.key) { k, a in
                    let ok = dispo.contains(k)
                    puce("\(a.emoji ?? "") \(ok ? (a.nom ?? k) : "Niveau \(j?.niveaux?.first { $0.n == a.niveau }?.nom ?? "?")")",
                         choisi: e.accessoire == k, off: !ok) { foyer.geste("habiller", ["accessoire": k]); allerA(nil) }
                }
            }
        }
    }

    func puce(_ texte: String, n: Int? = nil, fort: Bool = false, choisi: Bool = false, off: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(texte).lineLimit(1)
                if let n, n > 1 { Text("×\(n)").foregroundColor(choisi ? .black.opacity(0.5) : .white.opacity(0.45)) }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(choisi ? .black : .white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(choisi ? Color.white : fort ? vert.opacity(0.28) : Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(Appui())
        .disabled(off)
        .opacity(off ? 0.35 : 1)
    }

    // MARK: Cuisine

    func cuisine(_ e: BoubouEtat) -> some View {
        let j = foyer.jeu
        var reste = e.inventaire ?? [:]
        for k in marmite { reste[k, default: 0] -= 1 }
        let dispo = reste.filter { $0.value > 0 && $0.key != "carotte_doree" }.sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("🍲").font(.system(size: 18))
                ForEach(0..<3, id: \.self) { i in
                    let k = i < marmite.count ? marmite[i] : nil
                    Button { if let _ = k { withAnimation(.spring(response: 0.3)) { _ = marmite.remove(at: i) } } } label: {
                        Text(k.map { j?.emoji($0) ?? "•" } ?? "")
                            .font(.system(size: 16))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(k == nil ? 0.05 : 0.12)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: k == nil ? [3, 3] : [])))
                            .contentShape(Circle())
                    }
                    .buttonStyle(Appui())
                    .help(k.map { j?.nom($0) ?? $0 } ?? "Ingrédient")
                }
                Button {
                    tirs["cuisiner", default: 0] += 1
                    foyer.geste("cuisiner", ["ingredients": marmite])
                    withAnimation(.spring(response: 0.3)) { marmite = [] }
                } label: {
                    Text("Cuisiner").font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.black).padding(.horizontal, 14).frame(height: 30)
                        .background(Capsule().fill(vert)).contentShape(Capsule())
                }
                .buttonStyle(Appui())
                .disabled(marmite.count < 2)
                .opacity(marmite.count < 2 ? 0.35 : 1)
                .modifier(Gerbe(emoji: "🔥", declencheur: tirs["cuisiner"] ?? 0))
                Spacer(minLength: 0)
                Text("📖 \(e.recettes?.count ?? 0)/\(j?.recettes?.count ?? 0)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.55))
                    .help(carnet(e))
            }
            if dispo.isEmpty && marmite.isEmpty {
                Text("Rien dans le placard : fais les courses ou récolte le potager.").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            Defile(apercu: apercu) {
                Flux(espace: 6) {
                    ForEach(dispo, id: \.key) { k, n in
                        puce("\(j?.emoji(k) ?? "•") \(j?.nom(k) ?? k)", n: n, off: marmite.count >= 3) {
                            withAnimation(.spring(response: 0.3)) { marmite.append(k) }
                        }
                    }
                }
            }
        }
    }

    /// Bulle d'aide : recettes découvertes.
    func carnet(_ e: BoubouEtat) -> String {
        let j = foyer.jeu
        let noms = (e.recettes ?? []).compactMap { j?.plat($0) }.map { "\($0.emoji ?? "") \($0.nom ?? "")" }
        return noms.isEmpty ? "Aucune recette découverte : mélange 2 ou 3 ingrédients" : noms.joined(separator: "\n")
    }

    // MARK: Potager

    func potager(_ e: BoubouEtat) -> some View {
        let cases = e.potager ?? Array(repeating: nil, count: 6)
        return VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 30)) { tl in
                let maintenant = tl.date.timeIntervalSince1970 + foyer.decalage
                HStack(spacing: 7) {
                    ForEach(Array(cases.enumerated()), id: \.offset) { i, c in
                        parcelle(i, c, maintenant: maintenant)
                    }
                }
            }
            if case .planter(let i) = choix {
                HStack(spacing: 6) {
                    Text("Planter :").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.6))
                    ForEach(foyer.jeu?.plantesTriees ?? [], id: \.0) { k, p in
                        puce("\(foyer.jeu?.emoji(k) ?? "🌱") \(duree(p.heures ?? 0))") { tirs["case\(i)", default: 0] += 1; foyer.geste("planter", ["case": i, "plante": k]); withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { choix = nil } }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    func parcelle(_ i: Int, _ c: BoubouEtat.Case?, maintenant: Double) -> some View {
        let terre = RoundedRectangle(cornerRadius: 12)
        return Group {
            if let c, let plante = c.plante {
                let debut = (c.plantee ?? 0) / 1000, fin = (c.fin ?? 0) / 1000
                let frac = fin > debut ? max(0, min(1, (maintenant - debut) / (fin - debut))) : 1
                let prete = c.prete == true || maintenant >= fin
                Button { if prete { tirs["case\(i)", default: 0] += 1; foyer.geste("recolter", ["case": i]) } } label: {
                    VStack(spacing: 4) {
                        Text(foyer.jeu?.emoji(plante) ?? "🌱")
                            .font(.system(size: prete ? 24 : 12 + 10 * frac))
                            .opacity(prete ? 1 : 0.55 + 0.45 * frac)
                            .modifier(Sautille(on: prete))
                        if prete {
                            Text("Récolter").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(vert)
                        } else {
                            Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(vert).frame(width: g.size.width * frac) } }
                                .padding(.horizontal, 10)
                            HStack(spacing: 3) {
                                Text(duree(max(0, fin - maintenant) / 3600)).font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.5))
                                if c.arrosee == true { Text("💧").font(.system(size: 8)) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 78)
                    .background(terre.fill(prete ? vert.opacity(0.16) : Color(red: 0.32, green: 0.22, blue: 0.16).opacity(0.45)))
                    .overlay(terre.strokeBorder(.white.opacity(0.06)))
                    .overlay(alignment: .topTrailing) {
                        if !prete && c.arrosee != true {
                            Button { tirs["case\(i)", default: 0] += 1; foyer.geste("arroser", ["case": i]) } label: {
                                Text("💧").font(.system(size: 10)).frame(width: 20, height: 20)
                                    .background(Circle().fill(.white.opacity(0.12))).contentShape(Circle())
                            }
                            .buttonStyle(Appui()).padding(4).help("Arroser : pousse plus vite")
                        }
                    }
                    .contentShape(terre)
                }
                .buttonStyle(Appui())
                .modifier(Gerbe(emoji: prete ? "🌟" : "💧", declencheur: tirs["case\(i)"] ?? 0))
                .help(prete ? "Récolter" : "\(foyer.jeu?.nom(plante) ?? plante)\(c.par.map { " · planté par \($0 == "yanis" ? "toi" : "Jeanne")" } ?? "")")
            } else {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { choix = choix == .planter(i) ? nil : .planter(i) } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        Text("Planter").font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(choix == .planter(i) ? 0.9 : 0.4))
                    .frame(maxWidth: .infinity).frame(height: 78)
                    .background(terre.fill(Color(red: 0.32, green: 0.22, blue: 0.16).opacity(choix == .planter(i) ? 0.6 : 0.3)))
                    .overlay(terre.strokeBorder(.white.opacity(choix == .planter(i) ? 0.25 : 0.06), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(terre)
                }
                .buttonStyle(Appui())
            }
        }
    }

    func duree(_ heures: Double) -> String {
        let min = Int((heures * 60).rounded())
        if min < 60 { return "\(max(1, min)) min" }
        let h = min / 60, m = min % 60
        return m == 0 || h >= 3 ? "\(h) h" : "\(h) h \(m)"
    }

    // MARK: Journal + mots de Jeanne

    func journal(_ e: BoubouEtat) -> some View {
        let mots = Array((e.mots ?? []).prefix(6))
        let evts = Array((e.journal ?? []).prefix(8))
        return Defile(apercu: apercu) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(mots) { m in
                    HStack(alignment: .top, spacing: 8) {
                        Text("💌").font(.system(size: 12))
                        Text(m.texte ?? "").font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(ilYa(m.quand)).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(rose.opacity(0.13)))
                }
                ForEach(Array(evts.enumerated()), id: \.offset) { _, ev in
                    HStack(spacing: 8) {
                        Text(ev.emoji ?? "•").font(.system(size: 11)).frame(width: 18)
                        Text(ev.texte ?? "").font(.system(size: 11)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(ilYa(ev.quand)).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 4)
                }
                if mots.isEmpty && evts.isEmpty {
                    Text("Rien encore : la vie de Boubou s'écrira ici.").font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.bottom, 24)
        }
    }

    func ilYa(_ ms: Double?) -> String {
        guard let ms else { return "" }
        let s = Date().timeIntervalSince1970 + foyer.decalage - ms / 1000
        if s < 60 { return "à l'instant" }
        if s < 3600 { return "il y a \(Int(s / 60)) min" }
        if s < 86400 { return "il y a \(Int(s / 3600)) h" }
        return "il y a \(Int(s / 86400)) j"
    }
}

// MARK: Petits outils

/// Défilement vertical (sauf en aperçu hors écran : ImageRenderer ne dessine pas le contenu d'un ScrollView).
struct Defile<Contenu: View>: View {
    var apercu: Bool
    @ViewBuilder var contenu: Contenu
    var body: some View {
        if apercu { contenu.frame(maxWidth: .infinity, alignment: .leading) }
        else { ScrollView(.vertical, showsIndicators: false) { contenu } }
    }
}

/// Appui : léger enfoncement au clic, léger éclaircissement au survol (les boutons répondent tout de suite).
struct Appui: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { AppuiCorps(configuration: configuration) }
}

private struct AppuiCorps: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var actif
    @State private var survol = false
    var body: some View {
        configuration.label
            .brightness(survol && actif && !configuration.isPressed ? 0.07 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : survol && actif ? 1.02 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: survol)
            .onHover { survol = $0 }
    }
}

/// Gerbe de particules : quand `declencheur` change, quelques emojis jaillissent du bouton et s'effacent.
struct Gerbe: ViewModifier {
    var emoji: String
    var declencheur: Int
    var taille: CGFloat = 11
    @State private var vagues: [Vague] = []
    struct Vague: Identifiable { let id = UUID(); let emoji: String }

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack { ForEach(vagues) { v in Eclats(emoji: v.emoji, taille: taille) } }
                    .allowsHitTesting(false)
            }
            .onChange(of: declencheur) { _, _ in
                let v = Vague(emoji: emoji)
                vagues.append(v)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { vagues.removeAll { $0.id == v.id } }
            }
    }
}

private struct Eclats: View {
    let emoji: String
    var taille: CGFloat
    @State private var parti = false
    @State private var points: [(x: CGFloat, y: CGFloat, r: Double, s: CGFloat)] = (0..<7).map { _ in
        (.random(in: -38...38), .random(in: -62 ... -24), .random(in: -50...50), .random(in: 0.75...1.15))
    }
    var body: some View {
        ZStack {
            ForEach(0..<points.count, id: \.self) { i in
                let p = points[i]
                Text(emoji).font(.system(size: taille))
                    .scaleEffect(parti ? p.s : 0.3)
                    .rotationEffect(.degrees(parti ? p.r : 0))
                    .offset(x: parti ? p.x : 0, y: parti ? p.y : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.7), value: parti)
                    .opacity(parti ? 0 : 1)
                    .animation(.easeIn(duration: 0.8), value: parti)
            }
        }
        .onAppear { DispatchQueue.main.async { parti = true } }
    }
}

/// Récolte prête : la plante sautille doucement.
struct Sautille: ViewModifier {
    var on: Bool
    @State private var haut = false
    func body(content: Content) -> some View {
        content
            .offset(y: on && haut ? -3 : 0)
            .onAppear { if on { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { haut = true } } }
            .onChange(of: on) { _, v in
                if v { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { haut = true } } else { haut = false }
            }
    }
}

/// Puces qui passent à la ligne.
struct Flux: Layout {
    var espace: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, ligne: CGFloat = 0, large: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > w { x = 0; y += ligne + espace; ligne = 0 }
            x += t.width + espace; ligne = max(ligne, t.height); large = max(large, x - espace)
        }
        return CGSize(width: min(w, large), height: y + ligne)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, ligne: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > b.minX && x + t.width > b.maxX { x = b.minX; y += ligne + espace; ligne = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espace; ligne = max(ligne, t.height)
        }
    }
}
