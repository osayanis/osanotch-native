// Copie conforme de ~/dev/Boubou/Sources/Boubou/Scenes.swift. Recopier tel quel quand il change.

import SwiftUI

// Les scènes du foyer : de petites îles en 3D qui flottent sur le bureau (ou dans le notch de Yanis),
// où Boubou fait vraiment les choses : les courses au marché, le bain, la cuisine, le repas, le potager,
// le passage de niveau. Chaque scène est une fonction du temps `t` (secondes depuis le début) : rien n'est
// laissé au hasard, on peut donc en dessiner n'importe quelle image (Boubou apercu-scenes).
// Ce fichier est recopié tel quel dans OsaNotch (BoubouScenes.swift) : il ne dépend que de Boule.

enum SceneKind: String, CaseIterable {
    case courses, bain, cuisine, repas, planter, arroser, recolter, niveau

    var duree: Double {
        switch self {
        case .courses: return 6.4
        case .bain: return 6.8
        case .cuisine: return 6.2
        case .repas: return 4.4
        case .planter, .arroser: return 4.2
        case .recolter: return 4.2
        case .niveau: return 4.8
        }
    }
}

struct SceneSpec: Equatable {
    var kind: SceneKind
    var debut = Date()
    /// courses : les articles ; cuisine : les ingrédients ; repas : le plat ; potager : la plante.
    var emojis: [String] = []
    /// cuisine : le plat obtenu ("🫕" = plat mystère) ; niveau : le nom du niveau.
    var resultat: String? = nil
    var accessoire: String? = nil
    var fin: Date { debut.addingTimeInterval(kind.duree) }
}

/// La scène qui se joue toute seule.
struct SceneAnimee: View {
    var spec: SceneSpec
    var width: CGFloat = 260
    var body: some View {
        TimelineView(.animation) { ctx in
            SceneFrame(spec: spec, t: ctx.date.timeIntervalSince(spec.debut), w: width)
        }
        .frame(width: width, height: width * SceneFrame.ratio)
        .allowsHitTesting(false)
    }
}

// MARK: - Petits outils de mouvement

enum M {
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    /// Avancement de 0 à 1 entre a et b.
    static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
    static func ease(_ x: Double) -> Double { let x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    /// Ressort : dépasse un peu puis se pose.
    static func spring(_ x: Double) -> Double { let x = clamp(x); return x >= 1 ? 1 : 1 - exp(-6 * x) * cos(9 * x) }
    static func lerp(_ a: Double, _ b: Double, _ x: Double) -> Double { a + (b - a) * x }
    /// Pseudo-hasard stable (même image à chaque fois).
    static func r(_ i: Int, _ s: Int = 0) -> Double {
        var x = UInt64(bitPattern: Int64(i &* 73_856_093 ^ (s &+ 7) &* 19_349_663))
        x ^= x >> 33; x &*= 0xff51_afd7_ed55_8ccd; x ^= x >> 33; x &*= 0xc4ce_b9fe_1a85_ec53; x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }
    /// Arc de lancer de p0 à p1 (hauteur `h` au-dessus du plus haut des deux).
    static func arc(_ p0: CGPoint, _ p1: CGPoint, _ h: CGFloat, _ x: Double) -> CGPoint {
        let x = clamp(x), top = min(p0.y, p1.y) - h
        let y = pow(1 - x, 2) * p0.y + 2 * (1 - x) * x * (2 * top - (p0.y + p1.y) / 2) + x * x * p1.y
        return CGPoint(x: p0.x + (p1.x - p0.x) * x, y: y)
    }
}

// MARK: - Le cadre commun : une île qui flotte

struct SceneFrame: View {
    static let ratio: CGFloat = 0.7
    var spec: SceneSpec
    var t: Double
    var w: CGFloat

    var body: some View {
        let h = w * Self.ratio, d = spec.kind.duree
        let entree = M.spring(M.seg(t, 0, 0.55)), sortie = M.ease(M.seg(t, d - 0.4, d))
        let flotte = sin(t * 1.6) * w * 0.006
        ZStack {
            Ilot(sol: sol, w: w * 0.84, t: t)
                .position(x: w / 2, y: h * 0.7 + flotte)
            contenu(h: h)
                .offset(y: flotte)
        }
        .frame(width: w, height: h)
        .scaleEffect(0.35 + 0.65 * entree - 0.25 * sortie, anchor: UnitPoint(x: 0.5, y: 0.75))
        .rotation3DEffect(.degrees((1 - entree) * 35), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
        .opacity(M.clamp(t / 0.15) * (1 - sortie))
    }

    private var sol: Ilot.Sol {
        switch spec.kind {
        case .courses: return .marche
        case .bain: return .bain
        case .cuisine: return .cuisine
        case .repas: return .salon
        case .planter, .arroser, .recolter: return .jardin
        case .niveau: return .fete
        }
    }

    @ViewBuilder
    private func contenu(h: CGFloat) -> some View {
        switch spec.kind {
        case .courses: ScCourses(t: t, w: w, h: h, articles: spec.emojis.isEmpty ? ["🥕", "🥚", "🥛", "🧀", "🍫"] : spec.emojis, accessoire: spec.accessoire)
        case .bain: ScBain(t: t, w: w, h: h, accessoire: spec.accessoire)
        case .cuisine: ScCuisine(t: t, w: w, h: h, ingredients: spec.emojis.isEmpty ? ["🥕", "🥔"] : spec.emojis, plat: spec.resultat ?? "🥣")
        case .repas: ScRepas(t: t, w: w, h: h, plat: spec.emojis.first ?? "🥞", accessoire: spec.accessoire)
        case .planter, .arroser, .recolter: ScPotager(t: t, w: w, h: h, kind: spec.kind, plante: spec.emojis.first ?? "🥕", accessoire: spec.accessoire)
        case .niveau: ScNiveau(t: t, w: w, h: h, nom: spec.resultat ?? "Niveau suivant", accessoire: spec.accessoire)
        }
    }
}

/// Un disque de sol en perspective avec son épaisseur, comme un petit diorama.
struct Ilot: View {
    enum Sol { case marche, bain, cuisine, salon, jardin, fete }
    var sol: Sol
    var w: CGFloat
    var t: Double = 0

    var body: some View {
        let haut = w * 0.36, epais = w * 0.07
        let (c1, c2, cote) = couleurs
        ZStack {
            // ombre portée loin dessous : l'île flotte
            Ellipse().fill(.black.opacity(0.28)).frame(width: w * 0.8, height: haut * 0.5).blur(radius: w * 0.04)
                .offset(y: epais + haut * 0.55)
            // l'épaisseur
            Ellipse().fill(LinearGradient(colors: [cote, cote.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: haut).offset(y: epais)
            Rectangle().fill(LinearGradient(colors: [cote.opacity(0.95), cote], startPoint: .leading, endPoint: .trailing))
                .frame(width: w, height: epais).offset(y: epais / 2)
            // le dessus, motif en vraie perspective
            motif(c1, c2)
                .frame(width: w, height: w)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: w * 0.008))
                .rotation3DEffect(.degrees(69), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                .frame(width: w, height: haut)
            // lumière douce sur le dessus
            Ellipse().fill(RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: w * 0.5))
                .frame(width: w, height: haut)
        }
        .frame(width: w, height: haut + epais)
    }

    private var couleurs: (Color, Color, Color) {
        switch sol {
        case .marche: return (Color(red: 0.93, green: 0.85, blue: 0.72), Color(red: 0.86, green: 0.76, blue: 0.62), Color(red: 0.62, green: 0.48, blue: 0.36))
        case .bain: return (Color(red: 0.86, green: 0.94, blue: 0.98), Color(red: 0.62, green: 0.82, blue: 0.92), Color(red: 0.42, green: 0.62, blue: 0.74))
        case .cuisine: return (Color(red: 0.96, green: 0.93, blue: 0.86), Color(red: 0.36, green: 0.4, blue: 0.47), Color(red: 0.45, green: 0.36, blue: 0.3))
        case .salon: return (Color(red: 0.85, green: 0.66, blue: 0.47), Color(red: 0.76, green: 0.56, blue: 0.39), Color(red: 0.5, green: 0.36, blue: 0.26))
        case .jardin: return (Color(red: 0.55, green: 0.8, blue: 0.42), Color(red: 0.47, green: 0.72, blue: 0.36), Color(red: 0.5, green: 0.36, blue: 0.25))
        case .fete: return (Color(red: 0.55, green: 0.42, blue: 0.85), Color(red: 0.45, green: 0.33, blue: 0.75), Color(red: 0.32, green: 0.22, blue: 0.55))
        }
    }

    @ViewBuilder
    private func motif(_ c1: Color, _ c2: Color) -> some View {
        Canvas { ctx, size in
            let s = size.width
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c1))
            switch sol {
            case .bain, .cuisine:
                let n = sol == .bain ? 9 : 8, c = s / CGFloat(n)
                for i in 0..<n { for j in 0..<n where (i + j) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(i) * c, y: CGFloat(j) * c, width: c, height: c)), with: .color(c2))
                } }
            case .marche:
                let rh = s / 10
                for j in 0..<10 {
                    let dec = j % 2 == 0 ? 0 : rh
                    for i in stride(from: -1, to: 6, by: 1) {
                        let r = CGRect(x: CGFloat(i) * rh * 2 + dec + 1.5, y: CGFloat(j) * rh + 1.5, width: rh * 2 - 3, height: rh - 3)
                        ctx.fill(Path(roundedRect: r, cornerRadius: rh * 0.2), with: .color(M.r(i, j) > 0.5 ? c2 : c2.opacity(0.7)))
                    }
                }
            case .salon:
                let n = 7, lh = s / CGFloat(n)
                for j in 0..<n {
                    ctx.fill(Path(CGRect(x: 0, y: CGFloat(j) * lh, width: s, height: lh - 2)), with: .color(j % 2 == 0 ? c1 : c2))
                    let x = CGFloat(M.r(j, 3)) * s
                    ctx.fill(Path(CGRect(x: x, y: CGFloat(j) * lh, width: 2, height: lh)), with: .color(.black.opacity(0.12)))
                }
            case .jardin:
                for j in 0..<8 where j % 2 == 0 {
                    ctx.fill(Path(CGRect(x: 0, y: CGFloat(j) * s / 8, width: s, height: s / 8)), with: .color(c2))
                }
                for k in 0..<60 {
                    let x = CGFloat(M.r(k, 1)) * s, y = CGFloat(M.r(k, 2)) * s
                    var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + 2, y: y - 7))
                    ctx.stroke(p, with: .color(Color(red: 0.32, green: 0.6, blue: 0.27).opacity(0.7)), lineWidth: 2)
                }
            case .fete:
                for k in 0..<16 {
                    let a = Double(k) / 16 * 2 * .pi
                    var p = Path(); p.move(to: CGPoint(x: s / 2, y: s / 2))
                    p.addArc(center: CGPoint(x: s / 2, y: s / 2), radius: s, startAngle: .radians(a), endAngle: .radians(a + .pi / 16), clockwise: false)
                    ctx.fill(p, with: .color(c2))
                }
            }
        }
    }
}

// MARK: - Boubou dans une scène

/// Boubou posé les pieds en `pied`, avec écrasement / étirement et inclinaison calculés par la scène.
struct Acteur: View {
    var mood: Boule.Mood = .happy
    var arms: Boule.Arms = .rest
    var look: CGSize = .zero
    var size: CGFloat
    var pied: CGPoint
    var squash: Double = 0   // > 0 écrasé, < 0 étiré
    var tilt: Double = 0
    var accessoire: String? = nil
    var sale = false
    var malade = false
    var miroir = false

    var body: some View {
        Boule(mood: mood, arms: arms, look: look, size: size, shadow: false, accessoire: accessoire, malade: malade, sale: sale)
            .scaleEffect(x: (miroir ? -1 : 1) * (1 + squash * 0.18), y: 1 - squash * 0.2, anchor: .bottom)
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .position(x: pied.x, y: pied.y - size * 0.5)
    }
}

/// Ombre de contact sous un objet posé.
struct Ombre: View {
    var x: CGFloat, y: CGFloat, w: CGFloat, force: Double = 0.3
    var body: some View {
        Ellipse().fill(.black.opacity(force)).frame(width: w, height: w * 0.26).blur(radius: w * 0.06).position(x: x, y: y)
    }
}

/// Une poignée d'étincelles qui éclatent autour d'un point à partir de `t0`.
struct Etincelles: View {
    var t: Double, t0: Double, centre: CGPoint, rayon: CGFloat, n = 8, couleur = Color(red: 1, green: 0.85, blue: 0.4)
    var body: some View {
        let x = M.seg(t, t0, t0 + 0.9)
        ZStack {
            if x > 0 && x < 1 {
                ForEach(0..<n, id: \.self) { i in
                    let a = Double(i) / Double(n) * 2 * .pi + M.r(i, 9) * 0.6
                    let d = rayon * CGFloat(0.4 + 0.6 * M.easeOut(x)) * CGFloat(0.7 + M.r(i, 4) * 0.5)
                    Image(systemName: "sparkle").font(.system(size: rayon * 0.28 * CGFloat(1 - x * 0.6), weight: .bold))
                        .foregroundStyle(couleur)
                        .position(x: centre.x + cos(a) * d, y: centre.y + sin(a) * d)
                        .opacity(1 - x)
                }
            }
        }
    }
}

/// Des gouttelettes projetées (éclaboussure, ébrouement).
struct Gouttes: View {
    var t: Double, t0: Double, centre: CGPoint, force: CGFloat, n = 10, couleur = Color(red: 0.55, green: 0.8, blue: 0.98), duree = 0.8
    var vers: Double = -.pi / 2   // direction moyenne
    var ouverture: Double = 2.4
    var body: some View {
        let x = M.seg(t, t0, t0 + duree)
        ZStack {
            if x > 0 && x < 1 {
                ForEach(0..<n, id: \.self) { i in
                    let a = vers + (M.r(i, 11) - 0.5) * ouverture
                    let v = force * CGFloat(0.6 + M.r(i, 12) * 0.6)
                    let tt = CGFloat(x)
                    Ellipse().fill(couleur)
                        .frame(width: force * 0.07, height: force * 0.1)
                        .position(x: centre.x + cos(a) * v * tt, y: centre.y + sin(a) * v * tt + force * 1.4 * tt * tt)
                        .opacity(Double(1 - tt))
                }
            }
        }
    }
}

// MARK: - Les courses au marché

struct ScCourses: View {
    var t: Double, w: CGFloat, h: CGFloat, articles: [String], accessoire: String?

    var body: some View {
        let sol = h * 0.72, b = w * 0.17
        // trajet : arrive au stand, remplit le chariot, repart vers la droite
        let aller = M.ease(M.seg(t, 0.45, 1.9)), retour = M.ease(M.seg(t, 4.3, 5.5))
        let x = w * CGFloat(M.lerp(0.2, 0.42, aller) + 0.2 * retour)
        let marche = (t > 0.45 && t < 1.9) || (t > 4.3 && t < 5.5)
        let pas = marche ? abs(sin(t * 13)) : 0
        let charge = articles.prefix(5)
        ZStack {
            stand(sol: sol)
            Ombre(x: x + b * 0.95, y: sol + 2, w: b * 1.2)
            Ombre(x: x, y: sol + 2, w: b * 0.8)
            // les articles qui volent du stand au chariot
            ForEach(Array(charge.enumerated()), id: \.offset) { i, e in
                let t0 = 2.0 + Double(i) * 0.42
                let v = M.seg(t, t0, t0 + 0.55)
                if v > 0 && v < 1 {
                    let p = M.arc(CGPoint(x: w * 0.25, y: sol - h * 0.3), CGPoint(x: x + b * 0.95, y: sol - b * 0.62), h * 0.2, M.easeOut(v))
                    Text(e).font(.system(size: b * 0.42)).rotationEffect(.degrees(v * 360)).position(p)
                }
            }
            Chariot(b: b, roue: Double(x) / Double(b) * 4,
                    dedans: charge.enumerated().filter { i, _ in t > 2.0 + Double(i) * 0.42 + 0.55 }.map(\.element),
                    rebond: charge.indices.map { i in M.spring(M.seg(t, 2.55 + Double(i) * 0.42, 2.95 + Double(i) * 0.42)) })
                .position(x: x + b * 0.95, y: sol - b * 0.42 - CGFloat(pas) * b * 0.02)
            Acteur(mood: t > 5.5 ? .excited : (t > 1.9 && t < 4.3 ? .love : .happy), arms: t > 5.5 ? .up : .hug,
                   look: CGSize(width: t > 1.9 && t < 4.3 ? -0.8 : 1, height: 0),
                   size: b, pied: CGPoint(x: x - b * 0.05, y: sol - CGFloat(pas) * b * 0.12),
                   squash: marche ? (pas - 0.5) * 0.25 : (t > 5.5 ? -0.15 * sin((t - 5.5) * 14) * exp(-(t - 5.5) * 4) : 0),
                   tilt: marche ? 6 + sin(t * 13) * 3 : 0, accessoire: accessoire)
            Etincelles(t: t, t0: 5.5, centre: CGPoint(x: x + b * 0.9, y: sol - b * 0.9), rayon: b * 0.8)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func stand(sol: CGFloat) -> some View {
        let sw = w * 0.3, sx = w * 0.25, top = sol - h * 0.52
        ZStack {
            // montants
            ForEach([-1.0, 1.0], id: \.self) { s in
                Rectangle().fill(Color(red: 0.55, green: 0.4, blue: 0.3)).frame(width: w * 0.012, height: h * 0.42)
                    .position(x: sx + CGFloat(s) * sw * 0.44, y: sol - h * 0.27)
            }
            // l'auvent rayé, avec son festonnage
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { i in
                    Rectangle().fill(i % 2 == 0 ? Color(red: 0.95, green: 0.38, blue: 0.4) : .white)
                }
            }
            .frame(width: sw, height: h * 0.11)
            .overlay(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        Circle().fill(i % 2 == 0 ? Color(red: 0.95, green: 0.38, blue: 0.4) : .white).frame(height: sw / 6)
                    }
                }
                .frame(height: sw / 12, alignment: .top).clipped().offset(y: sw / 12)
            }
            .rotation3DEffect(.degrees(-25), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
            .position(x: sx, y: top)
            // l'étal et ses cagettes
            RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.72, green: 0.52, blue: 0.36))
                .frame(width: sw * 0.95, height: h * 0.12)
                .overlay(alignment: .top) { Rectangle().fill(Color(red: 0.82, green: 0.62, blue: 0.44)).frame(height: h * 0.025) }
                .position(x: sx, y: sol - h * 0.1)
            HStack(spacing: w * 0.004) {
                ForEach(["🥕", "🍅", "🥬", "🍓"], id: \.self) { e in Text(e).font(.system(size: w * 0.045)) }
            }
            .position(x: sx, y: sol - h * 0.19)
        }
    }
}

/// Un chariot de supermarché en métal, de trois quarts.
struct Chariot: View {
    var b: CGFloat
    var roue: Double
    var dedans: [String]
    var rebond: [Double]

    var body: some View {
        let metal = LinearGradient(colors: [Color(white: 0.92), Color(white: 0.62)], startPoint: .top, endPoint: .bottom)
        ZStack {
            // les articles posés dans le panier (derrière la grille de devant)
            HStack(spacing: -b * 0.12) {
                ForEach(Array(dedans.enumerated()), id: \.offset) { i, e in
                    Text(e).font(.system(size: b * 0.36))
                        .offset(y: -b * 0.08 - CGFloat(i % 2) * b * 0.08 - b * 0.12 * CGFloat(1 - (i < rebond.count ? rebond[i] : 1)))
                }
            }
            .offset(y: -b * 0.2)
            // le panier : un trapèze en grille
            Trapeze().fill(Color(white: 0.85).opacity(0.35))
                .overlay(Trapeze().stroke(metal, lineWidth: b * 0.05))
                .overlay(
                    HStack(spacing: b * 0.12) { ForEach(0..<6, id: \.self) { _ in Rectangle().fill(Color(white: 0.75)).frame(width: b * 0.018) } }
                        .mask(Trapeze())
                )
                .frame(width: b * 1.3, height: b * 0.6)
            // poignée
            Capsule().fill(Color(red: 0.95, green: 0.38, blue: 0.4)).frame(width: b * 0.08, height: b * 0.3)
                .rotationEffect(.degrees(-20)).offset(x: -b * 0.72, y: -b * 0.3)
            // châssis et roues qui tournent
            Rectangle().fill(metal).frame(width: b * 1.0, height: b * 0.04).offset(y: b * 0.35)
            ForEach([-1.0, 1.0], id: \.self) { s in
                Roue(angle: roue).frame(width: b * 0.2, height: b * 0.2).offset(x: CGFloat(s) * b * 0.38, y: b * 0.44)
            }
        }
        .frame(width: b * 1.6, height: b * 1.1)
    }
}

struct Trapeze: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY))
        p.closeSubpath(); return p
    }
}

struct Roue: View {
    var angle: Double
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.2))
            Circle().fill(Color(white: 0.6)).padding(3)
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Color(white: 0.3)).frame(width: 1.5).padding(.vertical, 3).rotationEffect(.radians(angle + Double(i) * .pi / 3))
            }
        }
    }
}

// MARK: - Le bain

struct ScBain: View {
    var t: Double, w: CGFloat, h: CGFloat, accessoire: String?

    var body: some View {
        let sol = h * 0.74, cx = w * 0.5, tw = w * 0.42, th = w * 0.16, eau = sol - th * 1.05
        let b = w * 0.15
        // 0–0.6 au bord, 0.6–1.3 saut dans le bain, 1.3–4.8 bain, 4.8–5.4 saut dehors, 5.4–6.4 s'ébroue
        let sautIn = M.seg(t, 0.65, 1.3), sautOut = M.seg(t, 4.8, 5.4)
        let dansLeBain = t >= 1.3 && t < 4.8
        let pied: CGPoint = {
            if t < 0.65 { return CGPoint(x: w * 0.17, y: sol) }
            if t < 1.3 { return M.arc(CGPoint(x: w * 0.17, y: sol), CGPoint(x: cx - tw * 0.08, y: eau + b * 0.18), h * 0.22, sautIn) }
            if t < 4.8 { return CGPoint(x: cx - tw * 0.08 + CGFloat(sin(t * 2.2)) * tw * 0.05, y: eau + b * 0.18 + CGFloat(sin(t * 3.1)) * b * 0.03) }
            return M.arc(CGPoint(x: cx - tw * 0.08, y: eau + b * 0.18), CGPoint(x: w * 0.82, y: sol), h * 0.22, sautOut)
        }()
        let prep = t > 0.4 && t < 0.65 ? sin(M.seg(t, 0.4, 0.65) * .pi) : 0
        let ebroue = t > 5.4 ? sin((t - 5.4) * 30) * exp(-(t - 5.4) * 2.6) : 0
        let propre = t > 3.2
        ZStack {
            Ombre(x: cx, y: sol + 2, w: tw * 1.05)
            if !dansLeBain { Ombre(x: pied.x, y: sol + 2, w: b * 0.8, force: 0.25) }
            // le fond de la baignoire et l'eau
            baignoireFond(cx: cx, eau: eau, tw: tw)
            // le canard passe derrière Boubou quand il est au fond
            canard(cx: cx, eau: eau, tw: tw, devant: false)
            Acteur(mood: dansLeBain ? .happy : (t > 5.4 ? .dizzy : (t < 0.65 ? .curious : .excited)),
                   arms: dansLeBain ? (Int(t * 2) % 2 == 0 ? .up : .wave) : .up,
                   look: CGSize(width: t < 0.65 ? 1 : sin(t * 1.3) * 0.6, height: 0),
                   size: b, pied: pied,
                   squash: prep * 0.6 - (t > 0.65 && t < 1.3 ? 0.3 : 0) + (t > 5.4 && t < 5.6 ? 0.4 : 0),
                   tilt: dansLeBain ? sin(t * 2.2) * 5 : ebroue * 22, accessoire: dansLeBain || t < 1.3 ? nil : accessoire,
                   sale: !propre)
            // la mousse par-dessus le bas de Boubou, puis le devant de la baignoire
            mousse(cx: cx, eau: eau, tw: tw)
            baignoireDevant(cx: cx, sol: sol, eau: eau, tw: tw, th: th)
            canard(cx: cx, eau: eau, tw: tw, devant: true)
            bulles(cx: cx, eau: eau, tw: tw)
            Gouttes(t: t, t0: 1.25, centre: CGPoint(x: cx - tw * 0.08, y: eau), force: w * 0.16, n: 14)
            Gouttes(t: t, t0: 5.45, centre: CGPoint(x: w * 0.82, y: sol - b * 0.6), force: w * 0.12, n: 16, vers: -.pi / 2, ouverture: 5.5)
            Gouttes(t: t, t0: 5.75, centre: CGPoint(x: w * 0.82, y: sol - b * 0.6), force: w * 0.1, n: 12, vers: -.pi / 2, ouverture: 5.5)
            Etincelles(t: t, t0: 6.0, centre: CGPoint(x: w * 0.82, y: sol - b * 0.6), rayon: b * 0.9, couleur: .white)
        }
        .frame(width: w, height: h)
    }

    private func baignoireFond(cx: CGFloat, eau: CGFloat, tw: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(Color(white: 0.97)).frame(width: tw, height: tw * 0.32).position(x: cx, y: eau)
            Ellipse().fill(LinearGradient(colors: [Color(red: 0.55, green: 0.82, blue: 0.95), Color(red: 0.35, green: 0.66, blue: 0.86)], startPoint: .top, endPoint: .bottom))
                .frame(width: tw * 0.9, height: tw * 0.24).position(x: cx, y: eau + tw * 0.02)
            // reflets qui ondulent
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(.white.opacity(0.5)).frame(width: tw * 0.12, height: 1.5)
                    .position(x: cx - tw * 0.25 + CGFloat(i) * tw * 0.22 + CGFloat(sin(t * 2 + Double(i))) * 4, y: eau + tw * 0.02 + CGFloat(i % 2) * 4)
            }
        }
    }

    private func baignoireDevant(cx: CGFloat, sol: CGFloat, eau: CGFloat, tw: CGFloat, th: CGFloat) -> some View {
        let blanc = LinearGradient(colors: [.white, Color(red: 0.84, green: 0.9, blue: 0.94)], startPoint: .top, endPoint: .bottom)
        return ZStack {
            // pieds dorés
            ForEach([-1.0, 1.0], id: \.self) { s in
                Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.45), Color(red: 0.8, green: 0.6, blue: 0.25)], startPoint: .top, endPoint: .bottom))
                    .frame(width: tw * 0.07, height: th * 0.32).rotationEffect(.degrees(s * 15))
                    .position(x: cx + CGFloat(s) * tw * 0.36, y: sol - th * 0.1)
            }
            BaignoireForme().fill(blanc)
                .overlay(BaignoireForme().stroke(.white, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    Capsule().fill(.white.opacity(0.9)).frame(width: tw * 0.25, height: th * 0.1).offset(x: tw * 0.12, y: th * 0.22)
                }
                .frame(width: tw, height: th)
                .position(x: cx, y: eau + th * 0.5)
            // le rebord avant
            Ellipse().trim(from: 0, to: 0.5).stroke(Color(white: 0.98), lineWidth: tw * 0.04)
                .frame(width: tw, height: tw * 0.32).position(x: cx, y: eau)
        }
    }

    private func mousse(cx: CGFloat, eau: CGFloat, tw: CGFloat) -> some View {
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                let r = tw * CGFloat(0.09 + M.r(i, 5) * 0.06)
                Circle().fill(.white).overlay(Circle().strokeBorder(Color(red: 0.8, green: 0.9, blue: 0.97), lineWidth: 0.8))
                    .frame(width: r, height: r)
                    .position(x: cx - tw * 0.38 + CGFloat(i) * tw * 0.095, y: eau + tw * 0.03 + CGFloat(sin(t * 3 + Double(i))) * 1.5 - CGFloat(i % 2) * 3)
            }
        }
    }

    @ViewBuilder
    private func canard(cx: CGFloat, eau: CGFloat, tw: CGFloat, devant: Bool) -> some View {
        let a = t * 1.3
        if (sin(a) > 0) == devant {
            Text("🐥").font(.system(size: tw * (0.15 + 0.03 * sin(a))))
                .scaleEffect(x: cos(a) > 0 ? -1 : 1)
                .position(x: cx + CGFloat(cos(a)) * tw * 0.32, y: eau + CGFloat(sin(a)) * tw * 0.07 - tw * 0.04 + CGFloat(sin(t * 5)) * 1.5)
        }
    }

    private func bulles(cx: CGFloat, eau: CGFloat, tw: CGFloat) -> some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let periode = 1.6 + M.r(i, 2), dep = M.r(i, 3) * periode
                let x = ((t - 1.3 + dep).truncatingRemainder(dividingBy: periode)) / periode
                if t > 1.3 && t < 5.2 && x > 0 {
                    let r = tw * CGFloat(0.04 + M.r(i, 4) * 0.05) * CGFloat(x > 0.85 ? 1 + (x - 0.85) * 4 : 1)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.1), .white.opacity(0.6)], center: .center, startRadius: 0, endRadius: r))
                        .overlay(Circle().fill(.white.opacity(0.9)).frame(width: r * 0.25).offset(x: -r * 0.18, y: -r * 0.18))
                        .frame(width: r, height: r)
                        .position(x: cx - tw * 0.35 + CGFloat(M.r(i, 6)) * tw * 0.7 + CGFloat(sin(t * 4 + Double(i))) * 3,
                                  y: eau - CGFloat(x) * h * 0.4)
                        .opacity(x > 0.85 ? (1 - x) / 0.15 : 1)
                }
            }
        }
    }
}

struct BaignoireForme: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX - r.width * 0.18, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY * 0.8), control2: CGPoint(x: r.maxX - r.width * 0.05, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.18, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY), control1: CGPoint(x: r.minX + r.width * 0.05, y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY * 0.8))
        p.closeSubpath()
        return p
    }
}

// MARK: - La cuisine

struct ScCuisine: View {
    var t: Double, w: CGFloat, h: CGFloat, ingredients: [String], plat: String

    var body: some View {
        let sol = h * 0.74, px = w * 0.6, pw = w * 0.27, b = w * 0.15
        let haut = sol - h * 0.2 - pw * 0.42   // bord de la marmite
        let mystere = plat == "🫕"
        let revele = M.spring(M.seg(t, 4.3, 5.0))
        let ing = Array(ingredients.prefix(3))
        ZStack {
            // le réchaud
            Ombre(x: px, y: sol + 2, w: pw * 1.4)
            RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: pw * 1.25, height: h * 0.2)
                .overlay(alignment: .bottom) {
                    HStack(spacing: pw * 0.2) { ForEach(0..<2, id: \.self) { _ in Circle().fill(Color(white: 0.35)).frame(width: pw * 0.12) } }.padding(.bottom, 4)
                }
                .position(x: px, y: sol - h * 0.1)
            flammes(px: px, y: sol - h * 0.2, pw: pw)
            // l'intérieur de la marmite
            Ellipse().fill(Color(white: 0.2)).frame(width: pw, height: pw * 0.3).position(x: px, y: haut)
            Ellipse().fill(soupe).frame(width: pw * 0.86, height: pw * 0.22).position(x: px, y: haut + pw * 0.03)
            blups(px: px, y: haut + pw * 0.03, pw: pw)
            // la cuillère : derrière quand elle passe au fond
            cuillere(px: px, haut: haut, pw: pw, devant: false)
            // la marmite
            RoundedRectangle(cornerRadius: pw * 0.18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.35), Color(red: 0.7, green: 0.25, blue: 0.22)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topLeading) { Capsule().fill(.white.opacity(0.35)).frame(width: pw * 0.12, height: pw * 0.3).offset(x: pw * 0.1, y: pw * 0.08) }
                .frame(width: pw, height: pw * 0.45).position(x: px, y: haut + pw * 0.22)
            ForEach([-1.0, 1.0], id: \.self) { s in
                Capsule().fill(Color(red: 0.55, green: 0.2, blue: 0.18)).frame(width: pw * 0.16, height: pw * 0.07).position(x: px + CGFloat(s) * pw * 0.55, y: haut + pw * 0.1)
            }
            Ellipse().trim(from: 0, to: 0.5).stroke(Color(red: 0.98, green: 0.55, blue: 0.45), lineWidth: pw * 0.04)
                .frame(width: pw, height: pw * 0.3).position(x: px, y: haut)
            cuillere(px: px, haut: haut, pw: pw, devant: true)
            // Boubou, toque sur la tête, qui touille
            Acteur(mood: t > 4.4 ? (mystere ? .dizzy : .excited) : (t < 2.6 ? .curious : .happy), arms: t > 4.4 ? .up : .hug,
                   look: CGSize(width: t < 2.6 ? -0.7 : 0.8, height: t < 2.6 ? -0.5 : 0.3), size: b,
                   pied: CGPoint(x: w * 0.27, y: sol), squash: t > 4.4 ? -0.2 * sin((t - 4.4) * 12) * exp(-(t - 4.4) * 3) : 0,
                   tilt: t > 2.6 && t < 4.3 ? sin(t * 9) * 4 : 0, accessoire: "toque")
            // les ingrédients lancés dans la marmite
            ForEach(Array(ing.enumerated()), id: \.offset) { i, e in
                let t0 = 0.6 + Double(i) * 0.65, v = M.seg(t, t0, t0 + 0.6)
                if v > 0 && v < 1 {
                    Text(e).font(.system(size: b * 0.45)).rotationEffect(.degrees(v * 420))
                        .position(M.arc(CGPoint(x: w * 0.1, y: sol - h * 0.45), CGPoint(x: px, y: haut), h * 0.18, v))
                }
                Gouttes(t: t, t0: t0 + 0.58, centre: CGPoint(x: px, y: haut), force: w * 0.08, n: 7, couleur: Color(red: 1, green: 0.75, blue: 0.4), duree: 0.5)
            }
            vapeur(px: px, haut: haut, pw: pw)
            // le plat sort de la marmite
            if t > 4.3 {
                if mystere {
                    ForEach(0..<6, id: \.self) { i in
                        Circle().fill(Color(white: 0.55).opacity(0.7 * (1 - M.seg(t, 4.3, 5.6))))
                            .frame(width: pw * CGFloat(0.3 + M.seg(t, 4.3, 5.6) * 0.5))
                            .position(x: px + CGFloat(M.r(i, 1) - 0.5) * pw * 1.2, y: haut - CGFloat(M.seg(t, 4.3, 5.6)) * h * 0.3 - CGFloat(M.r(i, 2)) * pw * 0.4)
                    }
                } else {
                    Rayons(t: t).frame(width: pw * 1.8, height: pw * 1.8).opacity(revele * 0.8).position(x: px, y: haut - h * 0.22)
                }
                Text(plat).font(.system(size: b * 0.75)).scaleEffect(revele)
                    .rotation3DEffect(.degrees((1 - revele) * 180), axis: (x: 0, y: 1, z: 0))
                    .position(x: px, y: haut - h * 0.22 * CGFloat(revele))
                Etincelles(t: t, t0: 4.6, centre: CGPoint(x: px, y: haut - h * 0.22), rayon: pw * 0.8)
            }
        }
        .frame(width: w, height: h)
    }

    private var soupe: Color {
        let x = M.seg(t, 0.6, 2.6)
        return Color(red: M.lerp(0.6, 1, x), green: M.lerp(0.75, 0.6, x), blue: M.lerp(0.9, 0.3, x))
    }

    private func flammes(px: CGFloat, y: CGFloat, pw: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let f = 0.7 + 0.3 * sin(t * 18 + Double(i) * 2.1)
                Goutte().fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 1, green: 0.4, blue: 0.2)], startPoint: .top, endPoint: .bottom))
                    .frame(width: pw * 0.12, height: pw * 0.22 * CGFloat(f))
                    .position(x: px - pw * 0.27 + CGFloat(i) * pw * 0.18, y: y - pw * 0.08 * CGFloat(f))
            }
        }
    }

    private func blups(px: CGFloat, y: CGFloat, pw: CGFloat) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let periode = 0.7 + M.r(i, 1) * 0.5, x = ((t + M.r(i, 2)).truncatingRemainder(dividingBy: periode)) / periode
                if t > 0.8 {
                    Circle().stroke(.white.opacity(0.7 * (1 - x)), lineWidth: 1)
                        .frame(width: pw * 0.08 * CGFloat(0.5 + x))
                        .position(x: px - pw * 0.3 + CGFloat(M.r(i, 3)) * pw * 0.6, y: y + CGFloat(M.r(i, 4) - 0.5) * pw * 0.1)
                }
            }
        }
    }

    @ViewBuilder
    private func cuillere(px: CGFloat, haut: CGFloat, pw: CGFloat, devant: Bool) -> some View {
        let a = t > 2.4 && t < 4.3 ? (t - 2.4) * 7 : 0.6
        if (sin(a) > 0) == devant {
            Capsule().fill(LinearGradient(colors: [Color(red: 0.85, green: 0.65, blue: 0.42), Color(red: 0.65, green: 0.46, blue: 0.3)], startPoint: .top, endPoint: .bottom))
                .frame(width: pw * 0.06, height: pw * 0.75)
                .rotationEffect(.degrees(-25 + cos(a) * 12), anchor: .bottom)
                .position(x: px + CGFloat(cos(a)) * pw * 0.28, y: haut - pw * 0.32 + CGFloat(sin(a)) * pw * 0.06)
        }
    }

    private func vapeur(px: CGFloat, haut: CGFloat, pw: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let periode = 1.8, x = ((t + Double(i) * 0.45).truncatingRemainder(dividingBy: periode)) / periode
                if t > 1 && t < 4.4 {
                    Circle().fill(.white.opacity(0.55 * (1 - x) * M.seg(t, 1, 2)))
                        .frame(width: pw * CGFloat(0.12 + x * 0.25))
                        .blur(radius: 2)
                        .position(x: px - pw * 0.2 + CGFloat(i) * pw * 0.14 + CGFloat(sin(x * 6 + Double(i))) * pw * 0.08, y: haut - CGFloat(x) * h * 0.38)
                }
            }
        }
    }
}

struct Goutte: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - r.width / 2), control: CGPoint(x: r.maxX, y: r.midY))
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY - r.width / 2), radius: r.width / 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.midY))
        return p
    }
}

/// Des rayons de lumière qui tournent derrière une révélation.
struct Rayons: View {
    var t: Double
    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.5).opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
                    .frame(width: 6, height: 50)
                    .offset(y: -25)
                    .rotationEffect(.degrees(Double(i) * 30 + t * 40))
            }
        }
        .scaledToFit()
    }
}

// MARK: - Le repas

struct ScRepas: View {
    var t: Double, w: CGFloat, h: CGFloat, plat: String, accessoire: String?

    var body: some View {
        let sol = h * 0.74, b = w * 0.17, px = w * 0.62
        let arrive = M.spring(M.seg(t, 0.1, 0.8))
        let bouchees = [1.0, 1.7, 2.4].map { M.seg(t, $0, $0 + 0.25) }
        let mange = bouchees.reduce(0, +)   // 0 à 3
        let croque = bouchees.map { $0 > 0 && $0 < 1 ? sin($0 * .pi) : 0 }.reduce(0, +)
        ZStack {
            // la table basse et l'assiette qui glisse
            Ombre(x: px, y: sol + 2, w: w * 0.28)
            RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.6, green: 0.42, blue: 0.3)).frame(width: w * 0.025, height: h * 0.16).position(x: px, y: sol - h * 0.08)
            Ellipse().fill(LinearGradient(colors: [Color(red: 0.75, green: 0.55, blue: 0.38), Color(red: 0.62, green: 0.44, blue: 0.3)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.3, height: w * 0.08).position(x: px, y: sol - h * 0.16)
            ZStack {
                Ellipse().fill(.white).frame(width: w * 0.2, height: w * 0.055)
                Ellipse().stroke(Color(white: 0.85), lineWidth: 1).frame(width: w * 0.14, height: w * 0.035)
                Text(plat).font(.system(size: b * 0.8))
                    .scaleEffect(CGFloat(max(0, 1 - mange * 0.3)))
                    .mask {
                        ZStack {
                            Rectangle()
                            ForEach(0..<3, id: \.self) { i in
                                if bouchees[i] > 0 {
                                    Circle().frame(width: b * 0.3).offset(x: -b * 0.22 + CGFloat(i) * b * 0.06, y: -b * 0.1 + CGFloat(i) * b * 0.08)
                                        .blendMode(.destinationOut)
                                }
                            }
                        }
                        .compositingGroup()
                    }
                    .offset(y: -b * 0.18)
            }
            .position(x: px + w * 0.5 * CGFloat(1 - arrive), y: sol - h * 0.18)
            // les miettes
            ForEach(0..<3, id: \.self) { i in
                Gouttes(t: t, t0: [1.0, 1.7, 2.4][i] + 0.12, centre: CGPoint(x: px - w * 0.06, y: sol - h * 0.28), force: w * 0.07, n: 6,
                        couleur: Color(red: 0.9, green: 0.7, blue: 0.4), duree: 0.6, vers: .pi * 0.75, ouverture: 1.5)
            }
            Acteur(mood: t > 3 ? .love : (croque > 0.1 ? .excited : .happy), arms: t > 3 ? .hug : .rest,
                   look: CGSize(width: 1, height: 0.3), size: b,
                   pied: CGPoint(x: w * 0.36 + CGFloat(croque) * w * 0.05, y: sol),
                   squash: croque * 0.3 + (t > 3 ? -0.12 * sin((t - 3) * 10) * exp(-(t - 3) * 3) : 0), tilt: croque * 10, accessoire: accessoire)
            // des petits cœurs : c'était bon
            ForEach(0..<4, id: \.self) { i in
                let x = M.seg(t, 3.0 + Double(i) * 0.15, 4.2)
                if x > 0 && x < 1 {
                    Image(systemName: "heart.fill").font(.system(size: b * 0.2)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.55))
                        .position(x: w * 0.36 + CGFloat(i - 2) * b * 0.3 + CGFloat(sin(x * 8 + Double(i))) * 4, y: sol - b * 1.1 - CGFloat(x) * h * 0.3)
                        .opacity(1 - x)
                }
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Le potager : planter, arroser, récolter

struct ScPotager: View {
    var t: Double, w: CGFloat, h: CGFloat, kind: SceneKind, plante: String, accessoire: String?

    var body: some View {
        let sol = h * 0.74, b = w * 0.15, bx = w * 0.6, bw = w * 0.34
        let pousse: Double = {
            switch kind {
            case .planter: return M.spring(M.seg(t, 1.6, 2.6)) * 0.35
            case .arroser: return 0.4 + M.ease(M.seg(t, 1.2, 3.2)) * 0.35
            default: return 1
            }
        }()
        let tire = kind == .recolter ? M.seg(t, 0.7, 1.9) : 0
        let pop = kind == .recolter ? M.seg(t, 1.9, 2.8) : 0
        let mouille = kind == .arroser ? M.seg(t, 1.2, 2.4) : 0
        ZStack {
            Bac(w: bw, mouille: mouille).position(x: bx, y: sol - bw * 0.12)
            // la plante dans le bac
            if pop == 0 {
                PlanteDessin(emoji: plante, pousse: pousse, t: t, size: bw * 0.55, tire: tire)
                    .position(x: bx, y: sol - bw * 0.36 - CGFloat(tire) * b * 0.15)
            }
            // planter : la graine tombe
            if kind == .planter {
                let g = M.seg(t, 0.9, 1.5)
                if g > 0 && g < 1 {
                    Circle().fill(Color(red: 0.5, green: 0.35, blue: 0.2)).frame(width: b * 0.1)
                        .position(M.arc(CGPoint(x: bx - bw * 0.35, y: sol - b * 0.9), CGPoint(x: bx, y: sol - bw * 0.2), h * 0.05, g))
                }
            }
            // arroser : l'arrosoir et le filet d'eau
            if kind == .arroser {
                let incline = M.ease(M.seg(t, 0.8, 1.2)) * (1 - M.ease(M.seg(t, 3.0, 3.4)))
                let ax = w * 0.28 + b * 0.62, ay = sol - b * 0.62
                Arrosoir(size: b * 0.75).rotationEffect(.degrees(incline * 35), anchor: .leading)
                    .position(x: ax, y: ay)
                if incline > 0.8 {
                    ForEach(0..<12, id: \.self) { i in
                        let x = ((t * 2.4 + Double(i) / 12).truncatingRemainder(dividingBy: 1))
                        Ellipse().fill(Color(red: 0.55, green: 0.8, blue: 0.98)).frame(width: 2.5, height: 4)
                            .position(M.arc(CGPoint(x: ax + b * 0.5, y: ay - b * 0.02), CGPoint(x: bx - bw * 0.15 + CGFloat(M.r(i, 1)) * bw * 0.35, y: sol - bw * 0.2), 2, x))
                    }
                }
            }
            // récolter : le légume jaillit en tournant et atterrit dans le panier
            if pop > 0 {
                let p = M.arc(CGPoint(x: bx, y: sol - bw * 0.35), CGPoint(x: w * 0.2, y: sol - b * 0.45), h * 0.3, M.easeOut(pop))
                Text(plante).font(.system(size: b * 0.6)).rotationEffect(.degrees(pop * 540)).position(p)
                Gouttes(t: t, t0: 1.9, centre: CGPoint(x: bx, y: sol - bw * 0.22), force: w * 0.12, n: 12, couleur: Color(red: 0.45, green: 0.32, blue: 0.22), duree: 0.7)
            }
            if kind == .recolter {
                Text("🧺").font(.system(size: b * 0.65)).position(x: w * 0.2, y: sol - b * 0.3)
                    .scaleEffect(1 + 0.15 * sin(M.seg(t, 2.8, 3.1) * .pi), anchor: .bottom)
            }
            Acteur(mood: t > 2.8 ? .excited : (tire > 0 ? .worried : .happy), arms: tire > 0 ? .hug : (t > 2.8 ? .up : .rest),
                   look: CGSize(width: 1, height: 0.4), size: b,
                   pied: CGPoint(x: (kind == .arroser ? w * 0.28 : w * 0.38) - CGFloat(tire) * b * 0.15 - CGFloat(sin(tire * 40)) * 2, y: sol),
                   squash: tire > 0 ? 0.25 : (t > 2.8 ? -0.15 * sin((t - 2.8) * 12) * exp(-(t - 2.8) * 3) : 0),
                   tilt: tire > 0 ? -12 + sin(tire * 50) * 4 : 0, accessoire: accessoire)
            Etincelles(t: t, t0: kind == .recolter ? 2.8 : 2.6, centre: CGPoint(x: kind == .recolter ? w * 0.2 : bx, y: sol - b * 0.9), rayon: b * 0.8)
        }
        .frame(width: w, height: h)
    }
}

/// Un bac de potager surélevé, en planches, vu de trois quarts.
struct Bac: View {
    var w: CGFloat
    var mouille: Double = 0
    var body: some View {
        let bois = LinearGradient(colors: [Color(red: 0.78, green: 0.56, blue: 0.36), Color(red: 0.6, green: 0.42, blue: 0.27)], startPoint: .top, endPoint: .bottom)
        let terre = Color(red: M.lerp(0.47, 0.32, mouille), green: M.lerp(0.34, 0.22, mouille), blue: M.lerp(0.24, 0.16, mouille))
        ZStack {
            Ellipse().fill(.black.opacity(0.25)).frame(width: w * 1.1, height: w * 0.2).blur(radius: 3).offset(y: w * 0.14)
            // dessus : la terre en perspective, avec des sillons
            RoundedRectangle(cornerRadius: w * 0.05).fill(terre)
                .overlay(VStack(spacing: w * 0.07) { ForEach(0..<4, id: \.self) { _ in Capsule().fill(.black.opacity(0.15)).frame(height: w * 0.025) } }.padding(w * 0.08))
                .overlay(RoundedRectangle(cornerRadius: w * 0.05).strokeBorder(bois, lineWidth: w * 0.06))
                .frame(width: w, height: w)
                .rotation3DEffect(.degrees(66), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .frame(width: w, height: w * 0.4)
            // planche de devant
            RoundedRectangle(cornerRadius: 2).fill(bois)
                .overlay(VStack(spacing: w * 0.05) { ForEach(0..<2, id: \.self) { _ in Rectangle().fill(.black.opacity(0.12)).frame(height: 1) } })
                .frame(width: w * 0.98, height: w * 0.13).offset(y: w * 0.2)
        }
        .frame(width: w * 1.1, height: w * 0.55)
    }
}

/// Une plante qui pousse : butte → pousse → feuilles → légume (pousse de 0 à 1).
struct PlanteDessin: View {
    var emoji: String
    var pousse: Double
    var t: Double = 0
    var size: CGFloat
    var tire: Double = 0
    var body: some View {
        let s = size, vert = Color(red: 0.33, green: 0.68, blue: 0.33), vertClair = Color(red: 0.52, green: 0.82, blue: 0.4)
        let p = M.clamp(pousse), vent = sin(t * 2.2) * 4 + sin(tire * 60) * 10 * tire
        ZStack(alignment: .bottom) {
            if p < 0.12 {
                Ellipse().fill(Color(red: 0.4, green: 0.28, blue: 0.2)).frame(width: s * 0.3, height: s * 0.1)
            } else {
                // la tige
                Capsule().fill(vert).frame(width: s * 0.06, height: s * CGFloat(0.15 + 0.4 * p))
                    .rotationEffect(.degrees(vent), anchor: .bottom)
                // les feuilles qui s'ouvrent
                ForEach(0..<(p > 0.5 ? 4 : 2), id: \.self) { i in
                    let cote: Double = i % 2 == 0 ? -1 : 1, etage = CGFloat(i / 2)
                    Ellipse().fill(LinearGradient(colors: [vertClair, vert], startPoint: .top, endPoint: .bottom))
                        .frame(width: s * CGFloat(0.12 + 0.18 * p), height: s * CGFloat(0.07 + 0.08 * p))
                        .rotationEffect(.degrees(cote * (25 + 30 * p) + vent), anchor: cote < 0 ? .trailing : .leading)
                        .offset(x: CGFloat(cote) * s * CGFloat(0.06 + 0.08 * p), y: -s * CGFloat(0.1 + 0.2 * p) - etage * s * 0.14)
                }
                // le légume, quand c'est mûr
                if p > 0.8 {
                    Text(emoji).font(.system(size: s * CGFloat(0.2 + 0.3 * M.seg(p, 0.8, 1))))
                        .rotationEffect(.degrees(vent))
                        .offset(y: -s * 0.08 + CGFloat(tire) * -s * 0.15)
                }
            }
        }
        .frame(width: s, height: s, alignment: .bottom)
    }
}

/// L'arrosoir vert.
struct Arrosoir: View {
    var size: CGFloat
    var body: some View {
        let vert = LinearGradient(colors: [Color(red: 0.45, green: 0.78, blue: 0.62), Color(red: 0.28, green: 0.58, blue: 0.46)], startPoint: .top, endPoint: .bottom)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12).fill(vert).frame(width: size * 0.55, height: size * 0.45)
            Capsule().fill(vert).frame(width: size * 0.55, height: size * 0.08).rotationEffect(.degrees(-35)).offset(x: size * 0.42, y: -size * 0.12)
            Ellipse().fill(Color(red: 0.28, green: 0.58, blue: 0.46)).frame(width: size * 0.1, height: size * 0.16).rotationEffect(.degrees(-35)).offset(x: size * 0.66, y: -size * 0.28)
            Circle().trim(from: 0.5, to: 1).stroke(Color(red: 0.28, green: 0.58, blue: 0.46), lineWidth: size * 0.06).frame(width: size * 0.4).offset(y: -size * 0.2)
            Capsule().fill(.white.opacity(0.35)).frame(width: size * 0.08, height: size * 0.3).offset(x: -size * 0.16)
        }
        .frame(width: size * 1.3, height: size)
    }
}

// MARK: - Le passage de niveau

struct ScNiveau: View {
    var t: Double, w: CGFloat, h: CGFloat, nom: String, accessoire: String?

    var body: some View {
        let sol = h * 0.74, b = w * 0.16, mx = w * 0.5, my = h * 0.3
        let arrive = M.spring(M.seg(t, 0.3, 1.0))
        let tour = 720 * (1 - M.easeOut(M.seg(t, 0.3, 2.2)))
        let saut = t > 2.2 ? abs(sin((t - 2.2) * 6)) * exp(-(t - 2.2) * 0.8) : 0
        ZStack {
            Rayons(t: t).frame(width: w * 0.5, height: w * 0.5).opacity(M.seg(t, 0.8, 1.6) * 0.9).position(x: mx, y: my)
            // la médaille qui tourne en 3D puis se pose face à nous
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.5), Color(red: 0.88, green: 0.62, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().strokeBorder(Color(red: 1, green: 0.95, blue: 0.7), lineWidth: b * 0.05).padding(b * 0.06)
                Text("🩺").font(.system(size: b * 0.4))
                // reflet qui balaie
                Rectangle().fill(LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: b * 0.25).rotationEffect(.degrees(25))
                    .offset(x: b * CGFloat(M.lerp(-1, 1, M.seg(t, 2.2, 2.9))))
                    .mask(Circle())
            }
            .frame(width: b * 0.95, height: b * 0.95)
            .rotation3DEffect(.degrees(tour), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(arrive)
            .position(x: mx, y: my)
            // le nom du niveau
            Text(nom).font(.system(size: w * 0.065, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.3, green: 0.15, blue: 0.5).opacity(0.8), radius: 0, x: 0, y: 2)
                .scaleEffect(M.spring(M.seg(t, 1.6, 2.2)))
                .position(x: mx, y: my + b * 0.72)
            Acteur(mood: .excited, arms: .up, size: b, pied: CGPoint(x: mx, y: sol - CGFloat(saut) * h * 0.08),
                   squash: saut < 0.1 && t > 2.2 ? 0.3 : -0.1 * saut, accessoire: accessoire)
            Confettis(t: t, t0: 1.0, w: w, h: h)
        }
        .frame(width: w, height: h)
    }
}

struct Confettis: View {
    var t: Double, t0: Double, w: CGFloat, h: CGFloat, n = 26
    var body: some View {
        let couleurs: [Color] = [Color(red: 1, green: 0.45, blue: 0.55), Color(red: 1, green: 0.82, blue: 0.35), Color(red: 0.45, green: 0.8, blue: 0.7), Color(red: 0.55, green: 0.65, blue: 1), .white]
        ZStack {
            ForEach(0..<n, id: \.self) { i in
                let x = M.seg(t, t0 + M.r(i, 1) * 0.6, t0 + 2.4 + M.r(i, 1) * 0.6)
                if x > 0 && x < 1 {
                    Rectangle().fill(couleurs[i % couleurs.count])
                        .frame(width: w * 0.018, height: w * 0.03)
                        .rotation3DEffect(.degrees(x * 720 * (0.5 + M.r(i, 2))), axis: (x: 1, y: M.r(i, 3), z: 0.3))
                        .position(x: w * CGFloat(0.1 + M.r(i, 4) * 0.8) + CGFloat(sin(x * 8 + Double(i))) * w * 0.03, y: -h * 0.05 + CGFloat(x) * h * 0.95)
                        .opacity(x > 0.85 ? (1 - x) / 0.15 : 1)
                }
            }
        }
    }
}

// MARK: - Aperçu : une bande d'images par scène

enum ScenesApercu {
    @MainActor static func pellicule(_ kind: SceneKind, emojis: [String] = [], resultat: String? = nil, images: Int = 8, w: CGFloat = 260) -> some View {
        let d = kind.duree
        return HStack(spacing: 6) {
            ForEach(0..<images, id: \.self) { i in
                let t = d * (Double(i) + 0.5) / Double(images)
                VStack(spacing: 2) {
                    SceneFrame(spec: SceneSpec(kind: kind, emojis: emojis, resultat: resultat, accessoire: nil), t: t, w: w)
                        .background(Color(white: 0.3))
                    Text(String(format: "%@ t=%.1f", kind.rawValue, t)).font(.system(size: 10)).foregroundStyle(.white)
                }
            }
        }
        .padding(6).background(Color(white: 0.15))
    }
}
