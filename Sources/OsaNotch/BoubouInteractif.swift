// Copie conforme de ~/dev/Boubou/Sources/Boubou/Interactif.swift. Recopier tel quel quand il change.

import SwiftUI

// Le potager et la cuisine en vrai : une île en 3D où l'on prend l'arrosoir pour arroser, où l'on glisse
// les sachets de graines dans les bacs, et une marmite sur le feu où l'on glisse les ingrédients.
// Partagé tel quel avec OsaNotch (BoubouInteractif.swift) : ne dépend que de Scenes.swift et de Boule.

// MARK: - Le potager

struct CaseJardin: Equatable {
    var emoji: String
    var pousse: Double      // 0…1
    var arrosee: Bool
    var prete: Bool
    var reste: String       // « 1 h 12 »
}

struct Graine: Identifiable, Equatable {
    var id: String
    var emoji: String
    var duree: String
}

struct JardinInteractif: View {
    var cases: [CaseJardin?]
    var graines: [Graine]
    var width: CGFloat
    var height: CGFloat
    var planter: (Int, String) -> Void
    var arroser: (Int) -> Void
    var recolter: (Int) -> Void
    /// Pour les captures : l'arrosoir tenu au-dessus de ce bac.
    var apercuArrosoir: Int? = nil

    private enum Outil: Equatable { case arrosoir, graine(String) }
    private struct Effet: Equatable { var quoi: String; var emoji: String; var debut: Date }

    @State private var outil: Outil?
    @State private var pointeur: CGPoint = .zero
    @State private var cible: Int?
    @State private var dessus: Int?
    @State private var choisie: String?
    @State private var effets: [Int: Effet] = [:]
    @State private var message: String?
    @State private var messageTache: Task<Void, Never>?

    private let espace = "jardin"

    // Géométrie : l'île au milieu, l'arrosoir à gauche, les sachets en bas.
    private var bas: CGFloat { 38 }
    private var aire: CGFloat { height - bas }
    private var iw: CGFloat { min(width * 0.84, aire * 2.15) }
    private var centre: CGPoint { CGPoint(x: width * 0.53, y: aire * 0.47) }
    private var ry: CGFloat { iw * 0.18 }
    private var canTaille: CGFloat { iw * 0.17 }
    private var maisonArrosoir: CGPoint { CGPoint(x: max(canTaille * 0.75, centre.x - iw * 0.55), y: centre.y + ry * 0.55) }

    private func bac(_ i: Int) -> (p: CGPoint, w: CGFloat) {
        let fond = i < 3, k = CGFloat(i % 3) - 1
        return (CGPoint(x: centre.x + k * iw * (fond ? 0.25 : 0.3), y: centre.y + (fond ? -ry * 0.46 : ry * 0.42)), iw * (fond ? 0.2 : 0.235))
    }

    private func bacSous(_ p: CGPoint) -> Int? {
        var meilleur: (Int, CGFloat)?
        for i in 0..<min(6, max(cases.count, 6)) {
            let (c, w) = bac(i)
            let dx = (p.x - c.x) / (w * 0.62), dy = (p.y - (c.y - w * 0.12)) / (w * 0.55)
            let d = dx * dx + dy * dy
            if d < 1, d < (meilleur?.1 ?? 9) { meilleur = (i, d) }
        }
        return meilleur?.0
    }

    /// Le bec de l'arrosoir quand on le tient en `p` incliné de `angle` degrés.
    private func bec(_ p: CGPoint, _ angle: Double) -> CGPoint {
        let s = canTaille, a = angle * .pi / 180, x = s * 0.62, y = -s * 0.3
        return CGPoint(x: p.x + x * cos(a) - y * sin(a), y: p.y + x * sin(a) + y * cos(a))
    }

    private func caseDe(_ i: Int) -> CaseJardin? { i < cases.count ? cases[i] : nil }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                Ilot(sol: .jardin, w: iw, t: t).position(x: centre.x, y: centre.y + iw * 0.03)
                ForEach(0..<6, id: \.self) { i in bacVue(i, t: t, now: tl.date) }
                sachets(t: t)
                arrosoirVue(t: t)
                if case .graine(let g) = outil, let gr = graines.first(where: { $0.id == g }) {
                    sachet(gr, souleve: true).position(pointeur).allowsHitTesting(false)
                }
                if let m = message {
                    Text(m).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.65)))
                        .position(x: width / 2, y: 12)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
        }
        .coordinateSpace(name: espace)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named(espace)) { phase in
            if case .active(let p) = phase { dessus = bacSous(p) } else { dessus = nil }
        }
        .gesture(SpatialTapGesture(coordinateSpace: .named(espace)).onEnded { v in toucher(v.location) })
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: dessus)
        .animation(.easeOut(duration: 0.2), value: message)
    }

    // MARK: Un bac

    @ViewBuilder
    private func bacVue(_ i: Int, t: Double, now: Date) -> some View {
        let (p, w) = bac(i), c = caseDe(i), e = effets[i]
        let age = e.map { now.timeIntervalSince($0.debut) } ?? 99
        let arrose = (outil == .arrosoir && cible == i) || apercuArrosoir == i
        let leve: CGFloat = (dessus == i || cible == i) ? -3 : 0
        let valide: Bool = {
            switch outil {
            case .arrosoir: return c != nil && c?.prete == false && c?.arrosee == false
            case .graine: return c == nil
            case nil: return false
            }
        }()
        ZStack {
            if cible == i {
                Ellipse().fill((valide ? Color(red: 0.6, green: 1, blue: 0.6) : Color(red: 1, green: 0.5, blue: 0.5)).opacity(0.35))
                    .frame(width: w * 1.25, height: w * 0.5).blur(radius: 4)
            }
            Bac(w: w, mouille: (c?.arrosee == true && c?.prete == false) || arrose || (e?.quoi == "arroser" && age < 3) ? 0.8 : 0)
            plante(i, c, e, age: age, t: t, w: w)
            if arrose || (e?.quoi == "arroser" && age < 1.3) {
                pluie(t: t, w: w, depuis: arrose ? nil : age)
            }
            if let c {
                Text(c.prete ? "Prête !" : (c.arrosee ? "💧 " : "") + c.reste)
                    .font(.system(size: max(8, w * 0.13), weight: .heavy, design: .rounded))
                    .foregroundStyle(c.prete ? .black.opacity(0.8) : .white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(c.prete ? Color(red: 0.55, green: 0.9, blue: 0.6) : .black.opacity(0.45)))
                    .offset(y: w * 0.36)
                    .opacity(dessus == i || c.prete || w > 60 ? 1 : 0.75)
            } else if dessus == i && outil == nil {
                Text(choisie != nil ? "Clique pour planter" : "Glisse une graine ici")
                    .font(.system(size: max(8, w * 0.12), weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(.black.opacity(0.5)))
                    .fixedSize()
                    .offset(y: w * 0.36)
            }
            Etincelles(t: age, t0: e?.quoi == "recolter" ? 0.45 : 0.8, centre: CGPoint(x: w * 0.6, y: w * 0.2), rayon: w * 0.5)
                .frame(width: w * 1.2, height: w * 0.6).offset(y: -w * 0.2).allowsHitTesting(false)
        }
        .frame(width: w * 1.3, height: w * 1.2)
        .position(x: p.x, y: p.y + leve)
    }

    @ViewBuilder
    private func plante(_ i: Int, _ c: CaseJardin?, _ e: Effet?, age: Double, t: Double, w: CGFloat) -> some View {
        let taille = w * 0.66
        if e?.quoi == "recolter" && age < 1.1 {
            // le légume jaillit en tournant
            let x = M.seg(age, 0, 1.1)
            Text(e?.emoji ?? "🥕").font(.system(size: w * 0.32))
                .rotationEffect(.degrees(x * 540))
                .offset(x: CGFloat(x) * w * 0.3, y: -w * 0.15 - CGFloat(sin(x * .pi)) * w * 0.9)
                .scaleEffect(1 + 0.4 * x).opacity(1 - x * x)
        } else if e?.quoi == "planter" && age < 1.4 {
            let chute = M.seg(age, 0, 0.45)
            if chute < 1 {
                Circle().fill(Color(red: 0.5, green: 0.35, blue: 0.2)).frame(width: w * 0.07)
                    .offset(y: -w * 0.6 + CGFloat(chute * chute) * w * 0.6)
            } else {
                PlanteDessin(emoji: e?.emoji ?? "🌱", pousse: 0.14 + 0.12 * M.spring(M.seg(age, 0.45, 1.2)), t: t, size: taille)
                    .offset(y: -taille * 0.45)
            }
        } else if let c {
            PlanteDessin(emoji: c.emoji, pousse: c.prete ? 1 : max(0.14, c.pousse), t: t, size: taille)
                .offset(y: -taille * 0.45 - (c.prete ? CGFloat(abs(sin(t * 3))) * w * 0.03 : 0))
            if c.prete {
                Image(systemName: "sparkle").font(.system(size: w * 0.14, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.88, blue: 0.45))
                    .offset(x: w * 0.3, y: -w * 0.5 + CGFloat(sin(t * 3)) * 3).opacity(0.5 + 0.5 * sin(t * 4))
            }
        }
    }

    /// L'eau qui tombe sur un bac (depuis l'arrosoir tenu au-dessus, ou juste après).
    private func pluie(t: Double, w: CGFloat, depuis: Double?) -> some View {
        ZStack {
            ForEach(0..<9, id: \.self) { k in
                let x = ((t * 2.6 + Double(k) / 9).truncatingRemainder(dividingBy: 1))
                Ellipse().fill(Color(red: 0.55, green: 0.8, blue: 0.98)).frame(width: max(2, w * 0.035), height: max(3, w * 0.06))
                    .offset(x: CGFloat(M.r(k, 1) - 0.5) * w * 0.55, y: -w * 0.55 + CGFloat(x) * w * 0.55)
                    .opacity((1 - x * 0.4) * (depuis.map { 1 - M.seg($0, 0.8, 1.3) } ?? 1))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: L'arrosoir

    private func arrosoirVue(t: Double) -> some View {
        let tenu = outil == .arrosoir || apercuArrosoir != nil
        let vise = cible ?? apercuArrosoir
        let angle: Double = tenu && vise != nil ? 42 + sin(t * 6) * 3 : (tenu ? 8 : 0)
        let p = apercuArrosoir.map { i in CGPoint(x: bac(i).p.x - canTaille * 0.75, y: bac(i).p.y - canTaille * 1.1) } ?? (tenu ? pointeur : maisonArrosoir)
        return ZStack {
            if tenu, let vise {
                // le filet d'eau, du bec jusqu'au bac
                let b = bec(p, angle), dest = bac(vise).p
                ForEach(0..<8, id: \.self) { k in
                    let x = ((t * 3 + Double(k) / 8).truncatingRemainder(dividingBy: 1))
                    Ellipse().fill(Color(red: 0.55, green: 0.82, blue: 1)).frame(width: 3, height: 4.5)
                        .position(M.arc(b, CGPoint(x: dest.x + CGFloat(M.r(k, 2) - 0.5) * 16, y: dest.y - 6), 3, x))
                }
            }
            Arrosoir(size: canTaille)
                .rotationEffect(.degrees(angle))
                .scaleEffect(tenu ? 1.12 : 1)
                .shadow(color: .black.opacity(tenu ? 0.45 : 0.25), radius: tenu ? 8 : 3, y: tenu ? 8 : 2)
                .position(p)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(espace))
                        .onChanged { v in
                            outil = .arrosoir
                            pointeur = v.location
                            cible = bacSous(bec(v.location, 42))
                        }
                        .onEnded { _ in
                            let i = cible
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { outil = nil; cible = nil }
                            if let i { arroserBac(i) }
                        }
                )
                .help("Prends l'arrosoir et glisse-le au-dessus d'un bac")
        }
    }

    private func arroserBac(_ i: Int) {
        guard let c = caseDe(i) else { return dire("Plante d'abord une graine ici 🌱") }
        if c.prete { return dire("C'est mûr : clique pour récolter ✨") }
        if c.arrosee { return dire("Déjà arrosé 💧") }
        effets[i] = Effet(quoi: "arroser", emoji: c.emoji, debut: Date())
        arroser(i)
    }

    // MARK: Les sachets de graines

    private func sachets(t: Double) -> some View {
        HStack(spacing: 6) {
            ForEach(graines) { g in
                sachet(g, souleve: false)
                    .opacity(outil == .graine(g.id) ? 0.25 : 1)
                    .scaleEffect(choisie == g.id ? 1.12 : 1)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(choisie == g.id ? Color(red: 0.6, green: 1, blue: 0.6) : .clear, lineWidth: 1.5))
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named(espace))
                            .onChanged { v in
                                outil = .graine(g.id)
                                pointeur = v.location
                                cible = bacSous(CGPoint(x: v.location.x, y: v.location.y + 6))
                            }
                            .onEnded { _ in
                                let i = cible
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { outil = nil; cible = nil }
                                if let i { planterBac(i, g) }
                            }
                    )
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { choisie = choisie == g.id ? nil : g.id } }
                    .help("Graines : \(g.duree) pour pousser. Glisse le sachet dans un bac vide.")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: choisie)
        .position(x: width / 2, y: height - bas / 2)
    }

    private func sachet(_ g: Graine, souleve: Bool) -> some View {
        VStack(spacing: 0) {
            Text(g.emoji).font(.system(size: 15))
            Text(g.duree).font(.system(size: 7.5, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 0.4, green: 0.28, blue: 0.18))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(width: 34, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.92, blue: 0.78), Color(red: 0.9, green: 0.8, blue: 0.62)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(Color(red: 0.55, green: 0.78, blue: 0.45)).frame(height: 4).clipShape(RoundedRectangle(cornerRadius: 2)) }
        )
        .rotationEffect(.degrees(souleve ? -10 : 0))
        .scaleEffect(souleve ? 1.15 : 1)
        .shadow(color: .black.opacity(souleve ? 0.45 : 0.25), radius: souleve ? 7 : 2, y: souleve ? 6 : 1)
    }

    private func planterBac(_ i: Int, _ g: Graine) {
        guard caseDe(i) == nil else { return dire("Ce bac est déjà occupé") }
        effets[i] = Effet(quoi: "planter", emoji: g.emoji, debut: Date())
        choisie = nil
        planter(i, g.id)
    }

    // MARK: Clics

    private func toucher(_ p: CGPoint) {
        guard let i = bacSous(p) else { return }
        if let c = caseDe(i) {
            if c.prete {
                effets[i] = Effet(quoi: "recolter", emoji: c.emoji, debut: Date())
                recolter(i)
            } else if !c.arrosee {
                dire("Prends l'arrosoir et glisse-le au-dessus 💧")
            } else {
                dire("Ça pousse… encore \(c.reste)")
            }
        } else if let g = choisie, let gr = graines.first(where: { $0.id == g }) {
            planterBac(i, gr)
        } else {
            dire("Glisse un sachet de graines dans ce bac 🌱")
        }
    }

    private func dire(_ m: String) {
        message = m
        messageTache?.cancel()
        messageTache = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            message = nil
        }
    }
}

// MARK: - La cuisine : une marmite sur le feu, on y glisse les ingrédients

struct IngredientDispo: Identifiable, Equatable {
    var id: String
    var emoji: String
    var nom: String
    var n: Int
}

struct CuisineInteractive: View {
    var ingredients: [IngredientDispo]
    @Binding var marmite: [String]
    var emoji: (String) -> String
    var width: CGFloat
    var height: CGFloat
    var cuisiner: () -> Void

    private struct Chute: Equatable { var index: Int; var depart: CGPoint; var debut: Date }
    @State private var tenu: String?
    @State private var pointeur: CGPoint = .zero
    @State private var auDessus = false
    @State private var chutes: [Chute] = []
    @State private var touille: Date?
    @State private var message: String?
    @State private var messageTache: Task<Void, Never>?

    private let espace = "cuisine"
    private var etagere: CGFloat { min(width * 0.36, 160) }
    private var scene: CGFloat { width - etagere }
    private var iw: CGFloat { min(scene * 0.95, height * 1.75) }
    private var centre: CGPoint { CGPoint(x: scene * 0.5, y: height * 0.62) }
    private var pw: CGFloat { iw * 0.33 }
    /// Le bord de la marmite.
    private var bord: CGPoint { CGPoint(x: centre.x + iw * 0.04, y: centre.y - iw * 0.14) }

    private func dansLaMarmite(_ p: CGPoint) -> Bool {
        let dx = (p.x - bord.x) / (pw * 0.75), dy = (p.y - bord.y) / (pw * 0.6)
        return dx * dx + dy * dy < 1
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate, now = tl.date
            ZStack {
                Ilot(sol: .cuisine, w: iw, t: t).position(x: centre.x, y: centre.y + iw * 0.06)
                rechaud(t: t)
                marmiteVue(t: t, now: now)
                bouton
                etagereVue
                if let k = tenu {
                    Text(emoji(k)).font(.system(size: 26)).rotationEffect(.degrees(-8)).scaleEffect(1.1)
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 6)
                        .position(pointeur).allowsHitTesting(false)
                }
                if let m = message {
                    Text(m).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.65)))
                        .position(x: scene / 2, y: 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
        }
        .coordinateSpace(name: espace)
        .animation(.easeOut(duration: 0.2), value: message)
    }

    private func rechaud(t: Double) -> some View {
        let y = bord.y + pw * 0.62
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                .frame(width: pw * 1.35, height: pw * 0.42)
                .overlay(alignment: .bottom) {
                    HStack(spacing: pw * 0.22) { ForEach(0..<2, id: \.self) { _ in Circle().fill(Color(white: 0.35)).frame(width: pw * 0.1) } }.padding(.bottom, 3)
                }
                .position(x: bord.x, y: y + pw * 0.2)
            ForEach(0..<5, id: \.self) { i in
                let f = 0.7 + 0.3 * sin(t * 17 + Double(i) * 2.1)
                Goutte().fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 1, green: 0.4, blue: 0.2)], startPoint: .top, endPoint: .bottom))
                    .frame(width: pw * 0.1, height: pw * 0.2 * CGFloat(f))
                    .position(x: bord.x - pw * 0.3 + CGFloat(i) * pw * 0.15, y: y - pw * 0.07 * CGFloat(f))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func marmiteVue(t: Double, now: Date) -> some View {
        let n = marmite.count
        let soupe = Color(red: M.lerp(0.55, 1, Double(n) / 3), green: M.lerp(0.78, 0.6, Double(n) / 3), blue: M.lerp(0.92, 0.3, Double(n) / 3))
        let tourne = touille.map { now.timeIntervalSince($0) } ?? -1
        let a = tourne >= 0 ? tourne * 9 : 0.7
        ZStack {
            // l'intérieur et la soupe
            Ellipse().fill(Color(white: 0.2)).frame(width: pw, height: pw * 0.32).position(bord)
            Ellipse().fill(soupe).frame(width: pw * 0.86, height: pw * 0.24).position(x: bord.x, y: bord.y + pw * 0.03)
                .overlay(Ellipse().strokeBorder(.white.opacity(auDessus ? 0.8 : 0), lineWidth: 2).frame(width: pw * 0.86, height: pw * 0.24).position(x: bord.x, y: bord.y + pw * 0.03))
            // la cuillère, au fond quand elle passe derrière
            if sin(a) <= 0 { cuillere(a) }
            // ce qui mijote : chaque ingrédient flotte (clic = on le ressort)
            ForEach(Array(marmite.enumerated()), id: \.offset) { k, id in
                let chute = chutes.first { $0.index == k }
                let age = chute.map { now.timeIntervalSince($0.debut) } ?? 9
                let place = CGPoint(x: bord.x + CGFloat(k - 1) * pw * 0.24 + CGFloat(sin(t * 2 + Double(k) * 2)) * 2 + (tourne >= 0 ? CGFloat(cos(a + Double(k) * 2)) * pw * 0.12 : 0),
                                    y: bord.y - pw * 0.1 + CGFloat(sin(t * 3 + Double(k))) * 1.5)
                Text(emoji(id)).font(.system(size: pw * 0.3))
                    .rotationEffect(.degrees(age < 0.4 ? age * 700 : sin(t * 2 + Double(k)) * 10))
                    .position(age < 0.4 ? M.arc(chute!.depart, place, 30, age / 0.4) : place)
                    .onTapGesture { retirer(k) }
                    .help("Clique pour le ressortir")
                Gouttes(t: age, t0: 0.38, centre: place, force: pw * 0.35, n: 7, couleur: soupe, duree: 0.5)
            }
            // le corps de la marmite
            RoundedRectangle(cornerRadius: pw * 0.18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.35), Color(red: 0.7, green: 0.25, blue: 0.22)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topLeading) { Capsule().fill(.white.opacity(0.35)).frame(width: pw * 0.1, height: pw * 0.26).offset(x: pw * 0.1, y: pw * 0.08) }
                .frame(width: pw, height: pw * 0.5).position(x: bord.x, y: bord.y + pw * 0.25)
                .allowsHitTesting(false)
            ForEach([-1.0, 1.0], id: \.self) { s in
                Capsule().fill(Color(red: 0.55, green: 0.2, blue: 0.18)).frame(width: pw * 0.16, height: pw * 0.07)
                    .position(x: bord.x + CGFloat(s) * pw * 0.55, y: bord.y + pw * 0.1)
            }
            Ellipse().trim(from: 0, to: 0.5).stroke(Color(red: 0.98, green: 0.55, blue: 0.45), lineWidth: pw * 0.04)
                .frame(width: pw, height: pw * 0.32).position(bord).allowsHitTesting(false)
            if sin(a) > 0 { cuillere(a) }
            // la vapeur
            ForEach(0..<4, id: \.self) { i in
                let x = ((t * 0.6 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1))
                Circle().fill(.white.opacity((n > 0 ? 0.45 : 0.15) * (1 - x)))
                    .frame(width: pw * CGFloat(0.12 + x * 0.25)).blur(radius: 2)
                    .position(x: bord.x - pw * 0.2 + CGFloat(i) * pw * 0.13 + CGFloat(sin(x * 6 + Double(i))) * pw * 0.07, y: bord.y - CGFloat(x) * pw * 0.9)
                    .allowsHitTesting(false)
            }
        }
    }

    private func cuillere(_ a: Double) -> some View {
        Capsule().fill(LinearGradient(colors: [Color(red: 0.85, green: 0.65, blue: 0.42), Color(red: 0.65, green: 0.46, blue: 0.3)], startPoint: .top, endPoint: .bottom))
            .frame(width: pw * 0.06, height: pw * 0.8)
            .rotationEffect(.degrees(-22 + cos(a) * 14), anchor: .bottom)
            .position(x: bord.x + CGFloat(cos(a)) * pw * 0.26, y: bord.y - pw * 0.34 + CGFloat(sin(a)) * pw * 0.05)
            .allowsHitTesting(false)
    }

    private var bouton: some View {
        let pret = marmite.count >= 2 && touille == nil
        return Button {
            guard marmite.count >= 2 else { return dire("Glisse au moins 2 ingrédients dans la marmite") }
            touille = Date()
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                touille = nil
                chutes = []
                cuisiner()
            }
        } label: {
            Text(touille != nil ? "Ça mijote…" : "🥄 Touiller")
                .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                .foregroundStyle(pret ? .black : .white.opacity(0.6))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(pret ? Color(red: 1, green: 0.82, blue: 0.4) : .white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .position(x: 48, y: height - 14)
    }

    private var etagereVue: some View {
        let nc = max(1, Int((etagere - 8) / 44)), rangs = max(1, (ingredients.count + nc - 1) / nc)
        let cote = min(40, (height - 8) / CGFloat(rangs) - 4)
        let colonnes = Array(repeating: GridItem(.fixed(40), spacing: 4), count: nc)
        return LazyVGrid(columns: colonnes, spacing: 4) {
            ForEach(ingredients) { ing in
                bocal(ing, cote: cote)
            }
        }
        .padding(4)
        .frame(width: etagere, height: height)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
        .overlay(alignment: .center) {
            if ingredients.isEmpty {
                Text("Placard vide").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .position(x: width - etagere / 2, y: height / 2)
    }

    private func bocal(_ ing: IngredientDispo, cote: CGFloat) -> some View {
        let reste = ing.n
        return ZStack(alignment: .bottomTrailing) {
            Text(ing.emoji).font(.system(size: min(20, cote * 0.55)))
                .frame(width: 40, height: cote)
                .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(tenu == ing.id ? 0.04 : 0.09)))
            Text("\(reste)").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.75)).padding(3)
        }
        .opacity(reste > 0 ? 1 : 0.3)
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named(espace))
                .onChanged { v in
                    guard reste > 0 else { return }
                    tenu = ing.id; pointeur = v.location; auDessus = dansLaMarmite(v.location)
                }
                .onEnded { v in
                    defer { tenu = nil; auDessus = false }
                    guard reste > 0, dansLaMarmite(v.location) else { return }
                    ajouter(ing.id, depuis: v.location)
                }
        )
        .gesture(SpatialTapGesture(coordinateSpace: .named(espace)).onEnded { v in
            guard reste > 0 else { return }
            ajouter(ing.id, depuis: v.location)
        })
        .help("\(ing.nom) : glisse-le dans la marmite (ou clique)")
    }

    private func ajouter(_ id: String, depuis p: CGPoint) {
        guard marmite.count < 3 else { return dire("La marmite est pleine (3 ingrédients)") }
        marmite.append(id)
        chutes.removeAll { Date().timeIntervalSince($0.debut) > 1 }
        chutes.append(Chute(index: marmite.count - 1, depart: p, debut: Date()))
    }

    private func retirer(_ k: Int) {
        guard k < marmite.count, touille == nil else { return }
        withAnimation(.spring(response: 0.3)) { _ = marmite.remove(at: k) }
        chutes = []
    }

    private func dire(_ m: String) {
        message = m
        messageTache?.cancel()
        messageTache = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            message = nil
        }
    }
}

enum InteractifApercu {
    @MainActor static func vue(largeur: CGFloat, hJardin: CGFloat, hCuisine: CGFloat) -> some View {
        let cases: [CaseJardin?] = [CaseJardin(emoji: "🥕", pousse: 1, arrosee: true, prete: true, reste: ""),
                                    CaseJardin(emoji: "🍅", pousse: 0.5, arrosee: false, prete: false, reste: "2 h 10"),
                                    nil,
                                    CaseJardin(emoji: "🍓", pousse: 0.2, arrosee: true, prete: false, reste: "3 h"),
                                    nil,
                                    CaseJardin(emoji: "🥔", pousse: 0.75, arrosee: false, prete: false, reste: "48 min")]
        let graines = [("carotte", "🥕", "3 h"), ("salade", "🥬", "4 h"), ("tomate", "🍅", "5 h"), ("patate", "🥔", "6 h"), ("fraise", "🍓", "6 h"), ("potiron", "🎃", "8 h")]
            .map { Graine(id: $0.0, emoji: $0.1, duree: $0.2) }
        let ings = [("carotte", "🥕", 3), ("oeuf", "🥚", 2), ("lait", "🥛", 1), ("farine", "🌾", 2), ("miel", "🍯", 1)]
            .map { IngredientDispo(id: $0.0, emoji: $0.1, nom: $0.0, n: $0.2) }
        return VStack(spacing: 10) {
            JardinInteractif(cases: cases, graines: graines, width: largeur, height: hJardin, planter: { _, _ in }, arroser: { _ in }, recolter: { _ in })
            JardinInteractif(cases: cases, graines: graines, width: largeur, height: hJardin, planter: { _, _ in }, arroser: { _ in }, recolter: { _ in }, apercuArrosoir: 1)
            CuisineInteractive(ingredients: ings, marmite: .constant(["carotte", "oeuf"]), emoji: { ["carotte": "🥕", "oeuf": "🥚"][$0] ?? "•" },
                               width: largeur, height: hCuisine, cuisiner: {})
        }
        .padding(10).background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }
}
