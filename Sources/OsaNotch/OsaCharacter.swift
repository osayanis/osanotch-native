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
            Canvas { ctx, cz in draw(&ctx, cz, tl.date.timeIntervalSinceReferenceDate) }
        }
        .frame(width: size, height: size)
    }

    private func draw(_ ctx: inout GraphicsContext, _ canvas: CGSize, _ t: TimeInterval) {
        let cx = canvas.width / 2, cy = canvas.height / 2
        let R = size * 0.40

        // ── Mouvement du corps ───────────────────────────────
        var bob: CGFloat = 0, roll: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1
        switch mood {
        case .idle:
            sy = 1 + 0.025 * sin(t * 2.2); sx = 1 - 0.018 * sin(t * 2.2)
            bob = -size * 0.010 * sin(t * 2.2)
        case .dancing:
            bob = -size * 0.07 * abs(sin(t * 6.2))
            roll = 0.16 * sin(t * 6.2)
            sx = 1 + 0.05 * sin(t * 6.2); sy = 1 - 0.05 * sin(t * 6.2)
        case .happy:
            let h = abs(sin(t * 7)); bob = -size * 0.12 * h
            sy = 1 + 0.08 * h; sx = 1 - 0.05 * h
        case .worried:
            roll = 0.05 * sin(t * 2.4)
        case .sleeping:
            sy = 1 + 0.018 * sin(t * 1.2)
        }

        // ── Regard : vers le curseur + micro-saccades au repos ──
        var ex: CGFloat = 0, ey: CGFloat = 0
        if mood != .sleeping, let scr = NSScreen.main {
            let dx = model.cursor.x - scr.frame.midX
            let dyUp = model.cursor.y - scr.frame.maxY
            let dist = max(1, hypot(dx, dyUp))
            let k = min(1, dist / 440)
            let maxO = size * 0.085
            ex = (dx / dist) * maxO * k
            ey = (-dyUp / dist) * maxO * k
            if k < 0.25 { // curseur proche/immobile → petit regard vivant
                ex += size * 0.03 * sin(t * 0.7)
                ey += size * 0.02 * sin(t * 0.9 + 1)
            }
        }

        // ── Clignement ───────────────────────────────────────
        var blink: CGFloat = 1
        if mood == .sleeping { blink = 0.05 }
        else {
            let seed = floor(t / 3.1)
            let start = seed * 3.1 + Double(Int(seed) % 3) * 0.3
            let d = t - start
            if d >= 0 && d < 0.13 { blink = max(0.08, abs(d - 0.065) / 0.065) }
        }

        ctx.translateBy(x: cx, y: cy + bob)
        ctx.rotate(by: .radians(roll))
        ctx.scaleBy(x: sx, y: sy)

        // Ombre au sol
        ctx.fill(Path(ellipseIn: CGRect(x: -R * 0.72, y: R * 0.86, width: R * 1.44, height: R * 0.26)),
                 with: .color(.black.opacity(0.26)))

        // ── Corps : squircle doux, légèrement plus large que haut ──
        let bw = R * 2.06, bh = R * 1.9
        let bodyRect = CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh)
        let body = Path(roundedRect: bodyRect, cornerSize: CGSize(width: bw * 0.42, height: bh * 0.46))
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [accent.lighter(0.26), accent, accent.darker(0.22)]),
            startPoint: CGPoint(x: 0, y: -bh / 2), endPoint: CGPoint(x: 0, y: bh / 2)))
        // Rim light bas
        ctx.stroke(body, with: .color(accent.lighter(0.3).opacity(0.5)), lineWidth: 1)
        // Gloss haut
        ctx.fill(Path(ellipseIn: CGRect(x: -bw * 0.34, y: -bh * 0.44, width: bw * 0.62, height: bh * 0.4)),
                 with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                       center: CGPoint(x: -bw * 0.06, y: -bh * 0.26), startRadius: 0, endRadius: bw * 0.4))

        // ── Yeux ─────────────────────────────────────────────
        let eyeW = R * 0.40, eyeH = R * 0.70, dxE = R * 0.42, yE = -R * 0.02
        let dark = Color(red: 0.09, green: 0.10, blue: 0.13)
        if mood == .happy {
            for s in [-dxE, dxE] {
                var p = Path()
                p.move(to: CGPoint(x: s - eyeW * 0.6 + ex, y: yE + ey))
                p.addQuadCurve(to: CGPoint(x: s + eyeW * 0.6 + ex, y: yE + ey),
                               control: CGPoint(x: s + ex, y: yE - eyeW * 0.85 + ey))
                ctx.stroke(p, with: .color(dark), style: StrokeStyle(lineWidth: R * 0.13, lineCap: .round))
            }
        } else {
            for s in [-dxE, dxE] {
                let r = CGRect(x: s - eyeW / 2 + ex, y: yE - (eyeH * blink) / 2 + ey, width: eyeW, height: eyeH * blink)
                ctx.fill(Path(roundedRect: r, cornerSize: CGSize(width: eyeW / 2, height: min(eyeW / 2, (eyeH * blink) / 2))), with: .color(dark))
                if blink > 0.6 {
                    ctx.fill(Path(ellipseIn: CGRect(x: s + ex - eyeW * 0.02, y: yE + ey - eyeH * 0.28, width: eyeW * 0.4, height: eyeW * 0.4)),
                             with: .color(.white.opacity(0.95)))
                    ctx.fill(Path(ellipseIn: CGRect(x: s + ex - eyeW * 0.3, y: yE + ey + eyeH * 0.08, width: eyeW * 0.16, height: eyeW * 0.16)),
                             with: .color(.white.opacity(0.6)))
                }
            }
        }

        // ── Bouche ───────────────────────────────────────────
        let my = R * 0.42
        if mood == .happy || mood == .dancing {
            var p = Path()
            p.move(to: CGPoint(x: -R * 0.16 + ex * 0.4, y: my))
            p.addQuadCurve(to: CGPoint(x: R * 0.16 + ex * 0.4, y: my), control: CGPoint(x: ex * 0.4, y: my + R * 0.16))
            ctx.stroke(p, with: .color(dark.opacity(0.8)), style: StrokeStyle(lineWidth: R * 0.07, lineCap: .round))
        } else if mood == .worried {
            var p = Path()
            p.move(to: CGPoint(x: -R * 0.12, y: my + R * 0.04))
            p.addQuadCurve(to: CGPoint(x: R * 0.12, y: my + R * 0.04), control: CGPoint(x: 0, y: my - R * 0.08))
            ctx.stroke(p, with: .color(dark.opacity(0.7)), style: StrokeStyle(lineWidth: R * 0.06, lineCap: .round))
        } else if mood != .sleeping {
            ctx.fill(Path(ellipseIn: CGRect(x: -R * 0.05, y: my - R * 0.03, width: R * 0.1, height: R * 0.08)), with: .color(dark.opacity(0.55)))
        }

        // Joues contentes
        if mood == .happy {
            for s in [-dxE - R * 0.18, dxE + R * 0.18] {
                ctx.fill(Path(ellipseIn: CGRect(x: s - R * 0.13, y: R * 0.2, width: R * 0.26, height: R * 0.18)),
                         with: .color(Color(red: 1, green: 0.5, blue: 0.62).opacity(0.55)))
            }
        }
        // Zzz
        if mood == .sleeping {
            ctx.draw(Text("z").font(.system(size: size * 0.18, weight: .bold)).foregroundColor(.white.opacity(0.45)),
                     at: CGPoint(x: R * 0.62, y: -R * 0.55))
            ctx.draw(Text("z").font(.system(size: size * 0.12, weight: .bold)).foregroundColor(.white.opacity(0.3)),
                     at: CGPoint(x: R * 0.9, y: -R * 0.8))
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
