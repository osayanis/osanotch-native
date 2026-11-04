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
            Spacer()
            // Groupe de droite resserré : il se tasse vers le bord et s'éloigne de l'encoche.
            HStack(spacing: 8) {
                tbButton("play.rectangle.fill", .cast)
                tbButton("music.note", .party)
                if dropHover { Text("Lâcher ici").font(.system(size: 10, weight: .semibold)).foregroundColor(accent) }
                if let b = battery {
                    BatteryGlyph(percent: b.percent, charging: b.charging)
                        .padding(.leading, 4)
                }
            }
        }.padding(.leading, 18).padding(.trailing, 14).padding(.top, 11)
    }

    func tbButton(_ icon: String, _ target: AppView) -> some View {
        Button { model.view = target } label: {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(model.view == target ? .white : .white.opacity(0.45)).padding(5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// Petite batterie avec le pourcentage dedans, comme sur l'iPhone : le chiffre est sombre sur la
// partie remplie et clair sur la partie vide (deux calques, le sombre découpé à la largeur du plein).
struct BatteryGlyph: View {
    var percent: Int
    var charging: Bool

    private let w: CGFloat = 27, h: CGFloat = 13
    private var frac: CGFloat { max(0, min(1, CGFloat(percent) / 100)) }
    private var color: Color {
        if charging { return Color(red: 0.30, green: 0.85, blue: 0.39) }
        if percent <= 15 { return .red }
        return .white
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5).strokeBorder(.white.opacity(0.4), lineWidth: 0.9)
                label(.white.opacity(0.9))
                ZStack {
                    RoundedRectangle(cornerRadius: 2.5).fill(color).padding(1.2)
                    label(.black.opacity(0.82))
                }
                .mask(alignment: .leading) { Rectangle().frame(width: 1.2 + (w - 2.4) * frac) }
            }
            .frame(width: w, height: h)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.4)).frame(width: 1.6, height: 4.5)
        }
        .accessibilityElement()
        .accessibilityLabel("Batterie \(percent) %\(charging ? ", en charge" : "")")
    }

    private func label(_ ink: Color) -> some View {
        HStack(spacing: 0.5) {
            if charging { Image(systemName: "bolt.fill").font(.system(size: 6.5, weight: .heavy)) }
            Text("\(percent)").font(.system(size: percent >= 100 ? 8 : 9, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .foregroundColor(ink)
        .frame(width: w, height: h)
    }
}
