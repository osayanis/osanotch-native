import SwiftUI
import AppKit

enum Mood { case sleeping, idle, happy, dancing, worried }

struct OsaCharacter: View {
    @ObservedObject var model: AppModel
    var mood: Mood
    var accent: Color          // teinte du halo (couleur pochette)
    var size: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, cz in draw(&ctx, cz, tl.date.timeIntervalSinceReferenceDate) }
        }
        .frame(width: size, height: size)
    }

    private func draw(_ ctx: inout GraphicsContext, _ canvas: CGSize, _ t: TimeInterval) {
        let cx = canvas.width / 2, cy = canvas.height / 2
        let R = size * 0.34

        var bob: CGFloat = 0, roll: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1
        switch mood {
        case .idle:    sy = 1 + 0.03 * sin(t * 2.2); sx = 1 - 0.02 * sin(t * 2.2); bob = -size * 0.012 * sin(t * 2.2)
        case .dancing: bob = -size * 0.06 * abs(sin(t * 6.2)); roll = 0.15 * sin(t * 6.2); sx = 1 + 0.05 * sin(t * 6.2); sy = 1 - 0.05 * sin(t * 6.2)
        case .happy:   let h = abs(sin(t * 7)); bob = -size * 0.11 * h; sy = 1 + 0.08 * h; sx = 1 - 0.05 * h
        case .worried: roll = 0.05 * sin(t * 2.4)
        case .sleeping: sy = 1 + 0.02 * sin(t * 1.2)
        }

        // Regard
        var ex: CGFloat = 0, ey: CGFloat = 0
        if mood != .sleeping, let scr = NSScreen.main {
            let dx = model.cursor.x - scr.frame.midX
            let dyUp = model.cursor.y - scr.frame.maxY
            let dist = max(1, hypot(dx, dyUp)); let k = min(1, dist / 440)
            let maxO = size * 0.07
            ex = (dx / dist) * maxO * k; ey = (-dyUp / dist) * maxO * k
            if k < 0.25 { ex += size * 0.02 * sin(t * 0.7); ey += size * 0.015 * sin(t * 0.9 + 1) }
        }

        var blink: CGFloat = 1
        if mood == .sleeping { blink = 0.05 }
        else { let d = t.truncatingRemainder(dividingBy: 3.2); if d < 0.13 { blink = max(0.08, abs(d - 0.065) / 0.065) } }

        // Halo lumineux (couleur pochette) derrière le perso — subtil
        ctx.fill(Path(ellipseIn: CGRect(x: cx - R * 1.9, y: cy - R * 1.9, width: R * 3.8, height: R * 3.8)),
                 with: .radialGradient(Gradient(colors: [accent.opacity(0.32), accent.opacity(0)]),
                                       center: CGPoint(x: cx, y: cy), startRadius: R * 0.6, endRadius: R * 1.9))

        ctx.translateBy(x: cx, y: cy + bob)
        ctx.rotate(by: .radians(roll))
        ctx.scaleBy(x: sx, y: sy)

        // Corps : crème clair, doux (esprit Mochi mais le nôtre)
        let bw = R * 2.0, bh = R * 1.86
        let bodyRect = CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh)
        let body = Path(roundedRect: bodyRect, cornerSize: CGSize(width: bw * 0.44, height: bh * 0.48))
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [Color(red: 1, green: 0.99, blue: 0.97), Color(red: 0.95, green: 0.93, blue: 0.89), Color(red: 0.86, green: 0.83, blue: 0.80)]),
            startPoint: CGPoint(x: 0, y: -bh / 2), endPoint: CGPoint(x: 0, y: bh / 2)))
        // Ombre interne bas
        ctx.fill(Path(ellipseIn: CGRect(x: -bw * 0.4, y: bh * 0.1, width: bw * 0.8, height: bh * 0.5)),
                 with: .radialGradient(Gradient(colors: [.clear, accent.opacity(0.14)]), center: CGPoint(x: 0, y: bh * 0.35), startRadius: bw * 0.1, endRadius: bw * 0.5))

        // Yeux (ovales sombres, grands, vivants)
        let eyeW = R * 0.42, eyeH = R * 0.60, dxE = R * 0.40, yE = R * 0.0
        let dark = Color(red: 0.11, green: 0.12, blue: 0.15)
        if mood == .happy {
            for s in [-dxE, dxE] {
                var p = Path()
                p.move(to: CGPoint(x: s - eyeW * 0.6 + ex, y: yE + ey))
                p.addQuadCurve(to: CGPoint(x: s + eyeW * 0.6 + ex, y: yE + ey), control: CGPoint(x: s + ex, y: yE - eyeW * 0.8 + ey))
                ctx.stroke(p, with: .color(dark), style: StrokeStyle(lineWidth: R * 0.14, lineCap: .round))
            }
        } else {
            for s in [-dxE, dxE] {
                let r = CGRect(x: s - eyeW / 2 + ex, y: yE - (eyeH * blink) / 2 + ey, width: eyeW, height: eyeH * blink)
                ctx.fill(Path(roundedRect: r, cornerSize: CGSize(width: eyeW / 2, height: min(eyeW / 2, eyeH * blink / 2))), with: .color(dark))
                if blink > 0.6 {
                    ctx.fill(Path(ellipseIn: CGRect(x: s + ex - eyeW * 0.02, y: yE + ey - eyeH * 0.26, width: eyeW * 0.38, height: eyeW * 0.38)), with: .color(.white.opacity(0.95)))
                }
            }
        }
        // Bouche
        let my = R * 0.5
        if mood == .happy || mood == .dancing {
            var p = Path(); p.move(to: CGPoint(x: -R * 0.14 + ex * 0.3, y: my))
            p.addQuadCurve(to: CGPoint(x: R * 0.14 + ex * 0.3, y: my), control: CGPoint(x: ex * 0.3, y: my + R * 0.16))
            ctx.stroke(p, with: .color(dark.opacity(0.8)), style: StrokeStyle(lineWidth: R * 0.06, lineCap: .round))
        } else if mood == .worried {
            var p = Path(); p.move(to: CGPoint(x: -R * 0.1, y: my + R * 0.03))
            p.addQuadCurve(to: CGPoint(x: R * 0.1, y: my + R * 0.03), control: CGPoint(x: 0, y: my - R * 0.06))
            ctx.stroke(p, with: .color(dark.opacity(0.7)), style: StrokeStyle(lineWidth: R * 0.05, lineCap: .round))
        }
        if mood == .happy {
            for s in [-dxE - R * 0.16, dxE + R * 0.16] {
                ctx.fill(Path(ellipseIn: CGRect(x: s - R * 0.12, y: R * 0.28, width: R * 0.24, height: R * 0.16)),
                         with: .color(Color(red: 1, green: 0.55, blue: 0.62).opacity(0.5)))
            }
        }
        if mood == .sleeping {
            ctx.draw(Text("z").font(.system(size: size * 0.16, weight: .bold)).foregroundColor(.white.opacity(0.5)), at: CGPoint(x: R * 0.6, y: -R * 0.55))
        }
    }
}

extension Color {
    func lighter(_ a: CGFloat) -> Color { mix(.white, a) }
    func darker(_ a: CGFloat) -> Color { mix(.black, a) }
    func mix(_ other: Color, _ a: CGFloat) -> Color {
        let x = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let y = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        return Color(red: Double(x.redComponent + (y.redComponent - x.redComponent) * a),
                     green: Double(x.greenComponent + (y.greenComponent - x.greenComponent) * a),
                     blue: Double(x.blueComponent + (y.blueComponent - x.blueComponent) * a))
    }
}
