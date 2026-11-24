// Copie conforme de ~/dev/Boubou/Sources/Boubou/Boubou.swift (dessin de Boubou + accessoires).
// Pour resynchroniser : recopier ce fichier tel quel (jusqu'à enum Accessoires inclus). Le choix de l'humeur est dans BoubouPortrait.swift.

import SwiftUI

// Boubou : la mascotte Osa (corps crème, bras, pieds, joues roses), en docteur :
// miroir frontal (ou chapeau de fête les jours de fête), blouse avec poche et stylo, stéthoscope.
// Elle cligne des yeux, regarde où on lui dit (`look`, de -1 à 1), lève les bras,
// saute quand `hop` change, et gonfle doucement avec `breath` (0…1) pendant la respiration.
struct Boule: View {
    enum Mood: Equatable { case calm, curious, excited, happy, worried, sad, sleepy, dizzy, love }
    enum Arms: Equatable { case rest, up, wave, hug }

    var mood: Mood = .calm
    var arms: Arms = .rest
    var look: CGSize = .zero
    var size: CGFloat = 90
    var hop = 0
    var breath: CGFloat = 0
    var shadow = true
    var tilt: Double = 0
    var hat = false
    /// Sans accessoires ni bras (couché sous la couverture).
    var plain = false
    /// Ce qu'il porte : toque, echarpe, bonnet, lunettes, noeud, couronne (voir le foyer).
    var accessoire: String? = nil
    /// Enrhumé : nez rouge, thermomètre, joues en feu.
    var malade = false
    /// Pas lavé depuis longtemps : quelques taches.
    var sale = false

    @State private var blink = false
    @State private var swing = false

    static let ink = Color(red: 0.106, green: 0.114, blue: 0.141)
    static let light = Color(red: 0.995, green: 0.99, blue: 0.97)
    static let shade = Color(red: 0.84, green: 0.81, blue: 0.76)
    static let cheek = Color(red: 1, green: 0.5, blue: 0.59)
    /// La seule couleur du costume : le vert d'eau des blocs opératoires.
    static let scrub = Color(red: 0.36, green: 0.72, blue: 0.68)

    private var ink: Color { Self.ink }
    private var light: Color { Self.light }
    private var shade: Color { Self.shade }

    var body: some View {
        let w = size, h = size * 0.92
        ZStack {
            if shadow && !plain {
                Ellipse().fill(.black.opacity(0.4)).frame(width: w * 0.85, height: w * 0.12).blur(radius: w * 0.03).offset(y: h * 0.56)
            }
            if !plain {
                ForEach([-1.0, 1.0], id: \.self) { s in
                    Ellipse().fill(LinearGradient(colors: [shade, Color(red: 0.7, green: 0.67, blue: 0.62)], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.24, height: w * 0.13).offset(x: s * w * 0.2, y: h * 0.47)
                }
            }
            if !plain {
                arm(side: -1)
                arm(side: 1)
            }
            ZStack {
                bodyShape
                    .fill(RadialGradient(colors: [light, light, shade], center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: w * 0.78))
                coat.clipShape(bodyShape)
                if sale { taches.clipShape(bodyShape) }
                bodyShape.strokeBorder(.white.opacity(0.6), lineWidth: 1).blur(radius: 0.5)
                stethoscope
                if accessoire == "echarpe" { Accessoires.echarpe(w: w, h: h) }
                if accessoire == "noeud" { Accessoires.noeud(w: w, h: h) }
                ZStack {
                    face
                    if malade { Accessoires.rhume(w: w) }
                    if accessoire == "lunettes" { Accessoires.lunettes(w: w) }
                }
                .offset(x: look.width * w * 0.05, y: look.height * w * 0.035)
                Group {
                    if plain { EmptyView() }
                    else if hat { partyHat }
                    else if accessoire == "toque" { Accessoires.toque(w: w, h: h) }
                    else if accessoire == "bonnet" { Accessoires.bonnet(w: w, h: h) }
                    else if accessoire == "couronne" { Accessoires.couronne(w: w, h: h) }
                    else { headMirror }
                }
                .offset(x: look.width * w * 0.03, y: look.height * w * 0.02)
            }
            .frame(width: w, height: h)
            .scaleEffect(x: 1 + breath * 0.07, y: 1 + breath * 0.1, anchor: .bottom)
        }
        .rotationEffect(.degrees(tilt), anchor: .bottom)
        .animation(.spring(response: 0.6, dampingFraction: 0.6), value: tilt)
        .frame(width: w * 1.6, height: h * 1.35)
        .keyframeAnimator(initialValue: 0.0, trigger: hop) { view, y in
            view.offset(y: y).scaleEffect(x: 1 - y / (w * 6), y: 1 + y / (w * 8), anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(w * 0.04, duration: 0.08)
                SpringKeyframe(-w * 0.3, duration: 0.22, spring: .snappy)
                SpringKeyframe(0, duration: 0.25, spring: .bouncy)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: look)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: arms)
        .animation(.easeInOut(duration: 0.25), value: mood)
        .onAppear { updateSwing() }
        .onChange(of: arms) { updateSwing() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.4...5.5)))
                if mood == .sleepy || mood == .happy || mood == .love || mood == .dizzy { continue }
                withAnimation(.easeIn(duration: 0.06)) { blink = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeOut(duration: 0.1)) { blink = false }
            }
        }
        .accessibilityHidden(true)
    }

    // Quelques taches de boue quand il n'a pas pris de bain depuis longtemps.
    private var taches: some View {
        let w = size, h = size * 0.92, boue = Color(red: 0.55, green: 0.42, blue: 0.3)
        return ZStack {
            Ellipse().fill(boue.opacity(0.35)).frame(width: w * 0.16, height: w * 0.1).offset(x: -w * 0.28, y: -h * 0.12)
            Ellipse().fill(boue.opacity(0.3)).frame(width: w * 0.1, height: w * 0.07).offset(x: w * 0.3, y: -h * 0.24)
            Ellipse().fill(boue.opacity(0.32)).frame(width: w * 0.2, height: w * 0.09).offset(x: -w * 0.1, y: h * 0.3)
            Circle().fill(boue.opacity(0.3)).frame(width: w * 0.05).offset(x: w * 0.12, y: -h * 0.34)
        }
    }

    private var bodyShape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.42, style: .continuous) }

    private func updateSwing() {
        if arms == .wave {
            swing = false
            withAnimation(.easeInOut(duration: 0.28).repeatCount(7, autoreverses: true)) { swing = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { swing = false }
        }
    }

    private func angle(_ side: Double) -> Double {
        let out: Double
        switch arms {
        case .rest: out = 18
        case .up: out = 150
        case .wave: out = side > 0 ? (swing ? 165 : 125) : 18
        case .hug: out = 62
        }
        return -side * out
    }

    // Les manches de la blouse : blanches, avec un poignet vert d'eau.
    private func arm(side: Double) -> some View {
        let w = size, len = w * 0.36
        return Capsule()
            .fill(LinearGradient(colors: [.white, Color(red: 0.88, green: 0.9, blue: 0.91)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottom) {
                Capsule().fill(light).frame(width: w * 0.15, height: w * 0.1)
            }
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6))
            .frame(width: w * 0.15, height: len)
            .rotationEffect(.degrees(angle(side)), anchor: .top)
            .offset(x: side * w * 0.44, y: w * 0.02 + len / 2)
    }

    // Le bas du corps : une blouse blanche, col en V, une poche avec un stylo.
    private var coat: some View {
        let w = size, h = size * 0.92
        return ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [.white, Color(red: 0.9, green: 0.92, blue: 0.93)], startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: h * 0.32)
                .offset(y: h * 0.34)
            // col : deux revers qui descendent en V
            Path { p in
                p.move(to: CGPoint(x: w * 0.32, y: h * 0.68))
                p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.8))
                p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.68))
            }
            .stroke(Color.black.opacity(0.13), style: StrokeStyle(lineWidth: w * 0.018, lineCap: .round, lineJoin: .round))
            .frame(width: w, height: h)
            // poche + stylo
            RoundedRectangle(cornerRadius: w * 0.02)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: w * 0.012)
                .frame(width: w * 0.15, height: w * 0.1)
                .offset(x: w * 0.3, y: h * 0.4)
            Capsule().fill(Color(red: 0.35, green: 0.45, blue: 0.75)).frame(width: w * 0.025, height: w * 0.09)
                .offset(x: w * 0.33, y: h * 0.345)
        }
        .frame(width: w, height: h)
    }

    // Le stéthoscope : un U autour du cou, et le pavillon argenté qui pend.
    private var stethoscope: some View {
        let w = size, h = size * 0.92
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: w * 0.2, y: h * 0.64))
                p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.88), control: CGPoint(x: w * 0.24, y: h * 0.88))
                p.addQuadCurve(to: CGPoint(x: w * 0.8, y: h * 0.64), control: CGPoint(x: w * 0.76, y: h * 0.88))
                p.move(to: CGPoint(x: w * 0.5, y: h * 0.88))
                p.addQuadCurve(to: CGPoint(x: w * 0.36, y: h * 0.97), control: CGPoint(x: w * 0.47, y: h * 0.97))
            }
            .stroke(Self.scrub, style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round, lineJoin: .round))
            .frame(width: w, height: h)
            Circle()
                .fill(LinearGradient(colors: [.white, Color(red: 0.7, green: 0.72, blue: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: w * 0.012))
                .frame(width: w * 0.12, height: w * 0.12)
                .offset(x: -w * 0.16, y: h * 0.47)
        }
    }

    // Le miroir frontal du docteur, sur un bandeau.
    private var headMirror: some View {
        let w = size, h = size * 0.92
        return ZStack {
            Capsule().fill(Color.black.opacity(0.18))
                .frame(width: w * 0.62, height: w * 0.035)
                .offset(y: -h * 0.36)
            Circle()
                .fill(RadialGradient(colors: [.white, Color(red: 0.78, green: 0.8, blue: 0.84), Color(red: 0.6, green: 0.62, blue: 0.67)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: w * 0.12))
                .overlay(Circle().strokeBorder(Color(red: 0.55, green: 0.57, blue: 0.62), lineWidth: w * 0.015))
                .overlay(Circle().fill(Self.ink.opacity(0.75)).frame(width: w * 0.04))
                .frame(width: w * 0.2, height: w * 0.2)
                .offset(y: -h * 0.4)
        }
    }

    // Chapeau pointu de fête, rayé, avec un pompon.
    private var partyHat: some View {
        let w = size, h = size * 0.92
        return ZStack {
            Triangle()
                .fill(LinearGradient(colors: [Self.cheek, Color(red: 1, green: 0.72, blue: 0.5)], startPoint: .bottom, endPoint: .top))
                .overlay(
                    VStack(spacing: w * 0.06) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(.white.opacity(0.75)).frame(height: w * 0.025) } }
                        .rotationEffect(.degrees(-18)).mask(Triangle())
                )
                .frame(width: w * 0.3, height: w * 0.36)
            Circle().fill(.white).frame(width: w * 0.1).offset(y: -w * 0.18)
        }
        .rotationEffect(.degrees(12))
        .offset(x: w * 0.1, y: -h * 0.56)
    }

    private var face: some View {
        let w = size
        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { s in
                eye(s).offset(x: s * w * 0.17, y: -w * 0.07)
                if mood == .worried || mood == .sad {
                    Capsule().fill(ink).frame(width: w * 0.13, height: w * 0.03)
                        .rotationEffect(.degrees(s * (mood == .sad ? 20 : 16)))
                        .offset(x: s * w * 0.18, y: -w * 0.2)
                }
                Ellipse().fill(Self.cheek.opacity(0.55)).frame(width: w * 0.16, height: w * 0.08).offset(x: s * w * 0.3, y: w * 0.06)
            }
            mouth.offset(y: w * 0.11)
        }
    }

    @ViewBuilder private func eye(_ s: Double) -> some View {
        let w = size
        switch mood {
        case .happy:
            Smile(up: true).stroke(ink, style: StrokeStyle(lineWidth: w * 0.045, lineCap: .round)).frame(width: w * 0.15, height: w * 0.08)
        case .sleepy:
            Smile(up: false).stroke(ink, style: StrokeStyle(lineWidth: w * 0.04, lineCap: .round)).frame(width: w * 0.13, height: w * 0.05)
        case .dizzy:
            ZStack {
                Circle().strokeBorder(ink, lineWidth: w * 0.025).frame(width: w * 0.15, height: w * 0.15)
                Circle().strokeBorder(ink, lineWidth: w * 0.025).frame(width: w * 0.07, height: w * 0.07).offset(x: s * w * 0.015)
            }
        case .love:
            Image(systemName: "heart.fill").font(.system(size: w * 0.15, weight: .black)).foregroundStyle(Self.cheek)
        default:
            let big = mood == .excited ? 1.2 : 1
            let round = mood == .worried || mood == .sad
            Capsule().fill(ink)
                .frame(width: w * 0.12 * big, height: (round ? w * 0.13 : w * 0.18) * big)
                .overlay(Circle().fill(.white.opacity(0.92)).frame(width: w * 0.045 * big).offset(x: w * 0.015, y: -w * 0.03 * big))
                .scaleEffect(x: 1, y: blink ? 0.1 : 1)
        }
    }

    @ViewBuilder private var mouth: some View {
        let w = size
        switch mood {
        case .sad:
            Smile(up: true).stroke(ink, style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round)).frame(width: w * 0.15, height: w * 0.05)
        case .worried:
            Capsule().fill(ink).frame(width: w * 0.1, height: w * 0.03)
        case .excited:
            Ellipse().fill(ink).frame(width: w * 0.15, height: w * 0.11)
                .overlay(Ellipse().fill(Self.cheek).frame(width: w * 0.08, height: w * 0.045).offset(y: w * 0.03))
                .clipShape(Ellipse())
        case .curious, .dizzy:
            Ellipse().fill(ink).frame(width: w * 0.07, height: w * 0.07)
        case .love:
            Smile(up: false).stroke(ink, style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round)).frame(width: w * 0.2, height: w * 0.07)
        case .sleepy:
            Ellipse().fill(ink).frame(width: w * 0.06, height: w * 0.05)
        case .calm, .happy:
            Smile(up: false).stroke(ink, style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round))
                .frame(width: mood == .happy ? w * 0.22 : w * 0.16, height: w * 0.06)
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath(); return p
    }
}

/// Boubou qui dort dans son petit lit : tête sur l'oreiller, couverture qui se soulève, des « z » qui montent.
struct BedView: View {
    var size: CGFloat = 96
    @State private var breathe = false
    @State private var zz = false

    var body: some View {
        let w = size, wood = Color(red: 0.8, green: 0.64, blue: 0.5), woodDark = Color(red: 0.66, green: 0.5, blue: 0.38)
        return ZStack(alignment: .bottomLeading) {
            // pieds + cadre
            ForEach([0.08, 0.86], id: \.self) { x in
                Capsule().fill(woodDark).frame(width: w * 0.06, height: w * 0.12).offset(x: w * x, y: 0)
            }
            RoundedRectangle(cornerRadius: w * 0.04).fill(wood).frame(width: w * 0.94, height: w * 0.1).offset(x: w * 0.03, y: -w * 0.07)
            // tête de lit (à gauche) et pied de lit (à droite)
            RoundedRectangle(cornerRadius: w * 0.05).fill(wood).frame(width: w * 0.1, height: w * 0.42).offset(x: w * 0.03, y: -w * 0.07)
            RoundedRectangle(cornerRadius: w * 0.05).fill(wood).frame(width: w * 0.08, height: w * 0.27).offset(x: w * 0.89, y: -w * 0.07)
            // matelas
            RoundedRectangle(cornerRadius: w * 0.04).fill(.white).frame(width: w * 0.78, height: w * 0.08).offset(x: w * 0.12, y: -w * 0.16)
            // oreiller
            Ellipse().fill(Color(red: 0.95, green: 0.95, blue: 0.97)).frame(width: w * 0.24, height: w * 0.12).offset(x: w * 0.13, y: -w * 0.21)
            // Boubou bordé, la tête sur l'oreiller
            Boule(mood: .sleepy, size: w * 0.34, shadow: false, tilt: -10, plain: true)
                .offset(x: w * 0.07, y: -w * 0.27)
            // couverture
            RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                .fill(LinearGradient(colors: [Boule.scrub, Color(red: 0.27, green: 0.6, blue: 0.57)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Capsule().fill(.white).frame(height: w * 0.045).padding(.horizontal, w * 0.01)
                }
                .frame(width: w * 0.74, height: w * 0.17)
                .scaleEffect(x: 1, y: breathe ? 1.06 : 0.97, anchor: .bottom)
                .offset(x: w * 0.15, y: -w * 0.15)
            // les z
            ForEach(0..<3, id: \.self) { i in
                Text("z").font(.system(size: w * (0.1 + Double(i) * 0.03), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(zz ? 0 : 0.9))
                    .shadow(color: .black.opacity(0.4), radius: 1)
                    .offset(x: w * (0.36 + Double(i) * 0.08) + (zz ? w * 0.08 : 0), y: -w * (0.5 + Double(i) * 0.1) - (zz ? w * 0.16 : 0))
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8), value: zz)
            }
        }
        .frame(width: w, height: w * 0.75, alignment: .bottomLeading)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
            zz = true
        }
    }
}

/// Un arc : sourire (`up` faux) ou œil fermé de joie / bouche triste (`up` vrai).
struct Smile: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: up ? r.maxY : r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: up ? r.maxY : r.minY), control: CGPoint(x: r.midX, y: up ? r.minY - r.height : r.maxY + r.height))
        return p
    }
}

/// Les accessoires de la garde-robe (débloqués avec les niveaux) et le rhume.
enum Accessoires {
    static let rouge = Color(red: 0.93, green: 0.36, blue: 0.4)
    static let jaune = Color(red: 1, green: 0.82, blue: 0.4)

    /// Toque de chef : trois boules blanches gonflées sur un bandeau.
    static func toque(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach([-1.0, 0.0, 1.0], id: \.self) { i in
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(red: 0.9, green: 0.91, blue: 0.93)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: w * 0.16))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.8))
                    .frame(width: w * (i == 0 ? 0.3 : 0.24))
                    .offset(x: i * w * 0.15, y: i == 0 ? -w * 0.1 : -w * 0.04)
            }
            RoundedRectangle(cornerRadius: w * 0.03)
                .fill(LinearGradient(colors: [.white, Color(red: 0.88, green: 0.89, blue: 0.91)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: w * 0.03).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8))
                .frame(width: w * 0.5, height: w * 0.14)
                .offset(y: w * 0.07)
        }
        .offset(y: -h * 0.5)
    }

    /// Bonnet tricoté vert d'eau, côtes et pompon.
    static func bonnet(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(LinearGradient(colors: [Boule.scrub, Color(red: 0.27, green: 0.6, blue: 0.57)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.74, height: w * 0.46)
                .mask(Rectangle().frame(height: w * 0.25).offset(y: -w * 0.11))
            Capsule().fill(Color(red: 0.95, green: 0.95, blue: 0.93))
                .overlay(HStack(spacing: w * 0.035) { ForEach(0..<9, id: \.self) { _ in Capsule().fill(Color.black.opacity(0.08)).frame(width: w * 0.012) } }.padding(.vertical, w * 0.015))
                .frame(width: w * 0.78, height: w * 0.12)
                .offset(y: w * 0.03)
            Circle().fill(Color(red: 0.97, green: 0.97, blue: 0.95)).frame(width: w * 0.14).offset(y: -w * 0.27)
        }
        .offset(y: -h * 0.42)
    }

    /// Couronne de fleurs posée sur le front.
    static func couronne(w: CGFloat, h: CGFloat) -> some View {
        let couleurs = [Boule.cheek, jaune, .white, Color(red: 0.75, green: 0.62, blue: 0.95), Boule.cheek, jaune, .white]
        return ZStack {
            ForEach(0..<7, id: \.self) { i in
                let x = (Double(i) - 3) * 0.12
                Capsule().fill(Color(red: 0.42, green: 0.66, blue: 0.4)).frame(width: w * 0.1, height: w * 0.045)
                    .rotationEffect(.degrees(i % 2 == 0 ? 30 : -30))
                    .offset(x: w * (x + 0.05), y: -h * 0.43 + abs(x) * w * 0.3 + w * 0.02)
            }
            ForEach(0..<7, id: \.self) { i in
                let x = (Double(i) - 3) * 0.12
                ZStack {
                    ForEach(0..<5, id: \.self) { k in
                        Circle().fill(couleurs[i]).frame(width: w * 0.075)
                            .offset(y: -w * 0.04).rotationEffect(.degrees(Double(k) * 72))
                    }
                    Circle().fill(i % 3 == 1 ? .white : jaune).frame(width: w * 0.045)
                }
                .offset(x: w * x, y: -h * 0.44 + abs(x) * w * 0.3)
            }
        }
    }

    /// Lunettes rondes (posées sur le visage, suivent le regard).
    static func lunettes(w: CGFloat) -> some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { s in
                Circle().strokeBorder(Boule.ink, lineWidth: w * 0.022)
                    .background(Circle().fill(.white.opacity(0.18)))
                    .frame(width: w * 0.25).offset(x: s * w * 0.17, y: -w * 0.07)
            }
            Capsule().fill(Boule.ink).frame(width: w * 0.08, height: w * 0.02).offset(y: -w * 0.08)
        }
    }

    /// Écharpe rouge à rayures autour du cou, un pan qui pend.
    static func echarpe(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Capsule().fill(LinearGradient(colors: [rouge, Color(red: 0.78, green: 0.26, blue: 0.32)], startPoint: .top, endPoint: .bottom))
                .overlay(HStack(spacing: w * 0.09) { ForEach(0..<6, id: \.self) { _ in Rectangle().fill(.white.opacity(0.55)).frame(width: w * 0.03) } })
                .clipShape(Capsule())
                .frame(width: w * 0.9, height: w * 0.11)
                .offset(y: h * 0.3)
            RoundedRectangle(cornerRadius: w * 0.03).fill(rouge)
                .overlay(VStack(spacing: w * 0.05) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(.white.opacity(0.55)).frame(height: w * 0.025) } })
                .clipShape(RoundedRectangle(cornerRadius: w * 0.03))
                .frame(width: w * 0.13, height: w * 0.26)
                .rotationEffect(.degrees(-8))
                .offset(x: -w * 0.24, y: h * 0.43)
        }
    }

    /// Nœud papillon rose au col.
    static func noeud(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { s in
                Triangle().fill(Boule.cheek).frame(width: w * 0.12, height: w * 0.11)
                    .rotationEffect(.degrees(s * 90)).offset(x: s * w * 0.06)
            }
            Circle().fill(Color(red: 0.9, green: 0.4, blue: 0.5)).frame(width: w * 0.055)
        }
        .offset(y: h * 0.34)
    }

    /// Le rhume : nez rouge et thermomètre au coin de la bouche.
    static func rhume(w: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.45), Color(red: 0.9, green: 0.25, blue: 0.3)], center: .topLeading, startRadius: 0, endRadius: w * 0.06))
                .frame(width: w * 0.09, height: w * 0.07).offset(y: w * 0.02)
            ZStack(alignment: .leading) {
                Capsule().fill(.white).overlay(Capsule().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.7)).frame(width: w * 0.24, height: w * 0.04)
                Circle().fill(rouge).frame(width: w * 0.05)
            }
            .rotationEffect(.degrees(-20))
            .offset(x: w * 0.18, y: w * 0.13)
        }
    }
}

/// Boubou dans sa petite baignoire, de la mousse plein la tête et un canard.
