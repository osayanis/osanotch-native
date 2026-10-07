import SwiftUI
import AppKit

enum Mood { case sleeping, idle, happy, dancing, worried }

struct OsaCharacter: View {
    @ObservedObject var model: AppModel
    var mood: Mood
    var accent: Color
    var size: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, cz in
                draw(ctx: &ctx, canvas: cz, t: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
    }

    private func draw(ctx: inout GraphicsContext, canvas: CGSize, t: TimeInterval) {
        let cx = canvas.width / 2, cy = canvas.height / 2
        let R = size * 0.42

        // Respiration / danse (corps)
        var bob: CGFloat = 0, roll: CGFloat = 0, squash: CGFloat = 1
        switch mood {
        case .idle:
            squash = 1 + 0.03 * sin(t * 2.4)
            bob = -size * 0.012 * sin(t * 2.4)
        case .dancing:
            bob = -size * 0.06 * abs(sin(t * 6))
            roll = 0.18 * sin(t * 6)
            squash = 1 - 0.05 * abs(sin(t * 6))
        case .happy:
            bob = -size * 0.10 * abs(sin(t * 7))
            squash = 1 + 0.06 * sin(t * 7)
        case .worried:
            roll = 0.06 * sin(t * 2.2)
        case .sleeping:
            squash = 1 + 0.02 * sin(t * 1.3)
        }

        // Yeux : direction vers le curseur (coords écran → vue)
        var ex: CGFloat = 0, ey: CGFloat = 0
        if mood != .sleeping, let scr = NSScreen.main {
            let dx = model.cursor.x - scr.frame.midX
            let dyUp = model.cursor.y - scr.frame.maxY        // ≤ 0 (curseur sous le haut)
            let dist = max(1, hypot(dx, dyUp))
            let k = min(1, dist / 420)
            let maxO = size * 0.09
            ex = (dx / dist) * maxO * k
            ey = (-dyUp / dist) * maxO * k                    // vue : y vers le bas
        }

        // Clignement déterministe (~ toutes les 3.4 s, 0.12 s)
        var blink: CGFloat = 1
        if mood == .sleeping { blink = 0.06 }
        else {
            let period = 3.4, phase = t.truncatingRemainder(dividingBy: period)
            if phase < 0.12 { blink = max(0.08, abs(phase - 0.06) / 0.06) }
        }

        ctx.translateBy(x: cx, y: cy + bob)
        ctx.rotate(by: .radians(roll))
        ctx.scaleBy(x: 1 + (1 - squash) * 0.6, y: squash) // volume ~ constant

        // Ombre
        var shadow = GraphicsContext.Shading.color(.black.opacity(0.28))
        ctx.fill(Path(ellipseIn: CGRect(x: -R * 0.7, y: R * 0.82, width: R * 1.4, height: R * 0.3)), with: shadow)
        _ = shadow

        // Corps squircle
        let bodyRect = CGRect(x: -R, y: -R, width: R * 2, height: R * 2)
        let body = Path(roundedRect: bodyRect, cornerSize: CGSize(width: R * 0.72, height: R * 0.78))
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [accent.opacity(0.95).lighter(0.22), accent, accent.darker(0.2)]),
            startPoint: CGPoint(x: -R * 0.4, y: -R), endPoint: CGPoint(x: R * 0.4, y: R)))

        // Reflet
        ctx.fill(Path(ellipseIn: CGRect(x: -R * 0.6, y: -R * 0.72, width: R * 0.9, height: R * 0.5)),
                 with: .radialGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0)]),
                                       center: CGPoint(x: -R * 0.15, y: -R * 0.47), startRadius: 0, endRadius: R * 0.55))

        // Yeux
        let eyeW = R * 0.34, eyeH = R * 0.62, dxE = R * 0.42, yE = -R * 0.06
        if mood == .happy {
            for sx in [-dxE, dxE] {
                var p = Path()
                p.move(to: CGPoint(x: sx - eyeW / 2 + ex, y: yE + ey))
                p.addQuadCurve(to: CGPoint(x: sx + eyeW / 2 + ex, y: yE + ey),
                               control: CGPoint(x: sx + ex, y: yE - eyeW * 0.7 + ey))
                ctx.stroke(p, with: .color(Color(red: 0.08, green: 0.09, blue: 0.11)), style: StrokeStyle(lineWidth: R * 0.12, lineCap: .round))
            }
        } else {
            for sx in [-dxE, dxE] {
                let r = CGRect(x: sx - eyeW / 2 + ex, y: yE - (eyeH * blink) / 2 + ey, width: eyeW, height: eyeH * blink)
                ctx.fill(Path(roundedRect: r, cornerSize: CGSize(width: eyeW / 2, height: eyeW / 2)),
                         with: .color(Color(red: 0.08, green: 0.09, blue: 0.11)))
                if blink > 0.5 {
                    ctx.fill(Path(ellipseIn: CGRect(x: sx + ex - eyeW * 0.05, y: yE + ey - eyeH * 0.26, width: eyeW * 0.32, height: eyeW * 0.32)),
                             with: .color(.white.opacity(0.9)))
                }
            }
        }

        // Joues contentes
        if mood == .happy {
            for sx in [-dxE - R * 0.12, dxE + R * 0.12] {
                ctx.fill(Path(ellipseIn: CGRect(x: sx - R * 0.12, y: R * 0.22, width: R * 0.24, height: R * 0.18)),
                         with: .color(Color(red: 1, green: 0.5, blue: 0.6).opacity(0.5)))
            }
        }

        // Zzz endormi
        if mood == .sleeping {
            ctx.draw(Text("z").font(.system(size: size * 0.2, weight: .bold)).foregroundColor(.white.opacity(0.5)),
                     at: CGPoint(x: R * 0.6, y: -R * 0.6))
        }
    }
}

extension Color {
    func lighter(_ amount: CGFloat) -> Color { mix(with: .white, amount: amount) }
    func darker(_ amount: CGFloat) -> Color { mix(with: .black, amount: amount) }
    func mix(with other: Color, amount: CGFloat) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        return Color(red: Double(a.redComponent + (b.redComponent - a.redComponent) * amount),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * amount),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * amount))
    }
}
