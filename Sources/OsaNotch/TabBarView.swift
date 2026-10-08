import SwiftUI

struct TabBarView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var dropHover: Bool
    var battery: BatteryInfo?
    var lowBat: Bool

    var body: some View {
        HStack(spacing: 16) {
            tbButton("house.fill", .home)
            tbButton("square.grid.2x2.fill", .dashboard)
            tbButton("paperplane.fill", .drop)
            tbButton("note.text", .notes)
            Spacer()
            if dropHover { Text("Lâcher pour AirDrop").font(.system(size: 10, weight: .semibold)).foregroundColor(accent) }
            
            if let b = battery {
                HStack(spacing: 5) {
                    BatteryGlyph(percent: b.percent, charging: b.charging)
                    Text("\(b.percent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundColor(b.charging ? .green : (lowBat ? .red : .white.opacity(0.6)))
                }
            }
            
            OsaCharacter(model: model, mood: .idle, accent: accent, size: 16)
        }.padding(.horizontal, 18).padding(.top, 11)
    }

    func tbButton(_ icon: String, _ target: AppView) -> some View {
        Button { model.view = target } label: {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(model.view == target ? .white : .white.opacity(0.45)).padding(5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// Petite batterie avec un visage : contente quand chargée, inquiète quand faible.
struct BatteryGlyph: View {
    var percent: Int
    var charging: Bool

    private var frac: CGFloat { max(0, min(1, CGFloat(percent) / 100)) }
    private var color: Color {
        if charging { return .green }
        if percent <= 15 { return .red }
        if percent <= 40 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5).strokeBorder(.white.opacity(0.4), lineWidth: 1).frame(width: 26, height: 14)
                RoundedRectangle(cornerRadius: 2.5).fill(color).frame(width: max(4, 24 * frac), height: 12).padding(.leading, 1)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)).foregroundColor(.black.opacity(0.75)).frame(width: 26)
                } else {
                    face.frame(width: 26, height: 14)
                }
            }
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.4)).frame(width: 2, height: 5)
        }
    }

    // Visage : yeux + bouche qui sourit (plein), reste neutre (moyen) ou boude (faible).
    var face: some View {
        let ink = Color.black.opacity(0.72)
        return VStack(spacing: 1.5) {
            HStack(spacing: 3) {
                Circle().fill(ink).frame(width: 1.8, height: 1.8)
                Circle().fill(ink).frame(width: 1.8, height: 1.8)
            }
            Mouth(smile: percent > 45 ? 1 : (percent > 20 ? 0 : -1)).stroke(ink, style: StrokeStyle(lineWidth: 1, lineCap: .round)).frame(width: 7, height: 3)
        }
    }
}

struct Mouth: Shape {
    var smile: CGFloat   // 1 = sourire, 0 = neutre, -1 = moue
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY),
                       control: CGPoint(x: r.midX, y: r.midY + smile * r.height * 0.9))
        return p
    }
}
