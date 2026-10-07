import SwiftUI
import AppKit

// Forme avec rayons haut/bas distincts (collé au sommet, s'arrondit vers le bas)
struct IslandShape: Shape {
    var top: CGFloat; var bottom: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + top), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.maxX - bottom, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bottom), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct Waveform: View {
    var color: Color; var active: Bool
    @State private var on = false
    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 2.5, height: active ? (on ? [10.0,16,8,13][i] : [5.0,8,13,6][i]) : 4)
                    .animation(.easeInOut(duration: 0.42 + Double(i) * 0.07).repeatForever(autoreverses: true), value: on)
            }
        }
        .frame(height: 16)
        .onAppear { on = active }.onChange(of: active) { _, v in on = v }
    }
}

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var data: SystemData

    var playing: Bool { data.music?.playing ?? false }
    var lowBat: Bool { if let b = data.battery { return b.percent <= 15 && !b.charging } else { return false } }
    var mood: Mood {
        if !model.expanded { return playing ? .idle : .sleeping }
        if lowBat { return .worried }
        if playing { return .dancing }
        return .idle
    }

    var collapsedW: CGFloat { playing ? 300 : 188 }

    var body: some View {
        let exp = model.expanded
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(top: exp ? 14 : 0, bottom: exp ? 30 : 12)
                    .fill(Color.black)
                    .overlay(
                        IslandShape(top: exp ? 14 : 0, bottom: exp ? 30 : 12)
                            .fill(LinearGradient(colors: [data.accent.opacity(exp && data.music != nil ? 0.28 : 0), .clear],
                                                 startPoint: .top, endPoint: .center))
                    )
                if exp { expandedView.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top))) }
                else { collapsedView.transition(.opacity) }
            }
            .frame(width: exp ? Island.expandedW : collapsedW,
                   height: exp ? Island.expandedH : Island.collapsedH)
            .clipShape(IslandShape(top: exp ? 14 : 0, bottom: exp ? 30 : 12))
            .shadow(color: .black.opacity(exp ? 0.5 : 0), radius: 20, y: 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: model.expanded)
        .ignoresSafeArea()
    }

    // ── Replié : Dynamic Island ──
    var collapsedView: some View {
        HStack(spacing: 0) {
            if playing {
                artwork(18, radius: 5)
                Spacer()
                Waveform(color: data.accent, active: true)
            } else {
                Spacer()
                OsaCharacter(model: model, mood: .idle, accent: data.accent, size: 30)
                    .offset(y: 5) // dépasse par le bas de l'encoche
                Spacer()
            }
        }
        .padding(.horizontal, playing ? 11 : 0)
        .frame(width: collapsedW, height: Island.collapsedH, alignment: .center)
    }

    // ── Déployé : media-hero ──
    var expandedView: some View {
        VStack(spacing: 0) {
            OsaCharacter(model: model, mood: mood, accent: data.accent, size: 74).padding(.top, 8)

            // Titre + artiste
            VStack(spacing: 2) {
                Text(data.music?.title ?? "Rien en lecture")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Text(data.music.map { "\($0.artist)" } ?? "Mets de la musique")
                    .font(.system(size: 11.5)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
            }.padding(.top, 2).padding(.horizontal, 20)

            // Pochette + onde
            HStack(spacing: 14) {
                artwork(60, radius: 14)
                VStack(alignment: .leading, spacing: 6) {
                    scrubber
                    HStack(spacing: 8) {
                        Waveform(color: data.accent, active: playing)
                        Text(data.music?.source ?? "").font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.3)).textCase(.uppercase)
                    }
                }
            }.padding(.horizontal, 22).padding(.top, 12)

            // Contrôles
            HStack(spacing: 38) {
                ctrl("backward.fill", 18) { SystemData.controlMusic("previous track") }
                Button { SystemData.controlMusic("playpause") } label: {
                    ZStack {
                        Circle().fill(.white).frame(width: 46, height: 46).shadow(color: data.accent.opacity(0.7), radius: 10, y: 3)
                        Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 18)).foregroundColor(.black)
                    }
                }.buttonStyle(.plain)
                ctrl("forward.fill", 18) { SystemData.controlMusic("next track") }
            }.padding(.top, 14)

            // Glance chips
            HStack(spacing: 7) {
                chip("headphones", airpodsText)
                chip("calendar", data.event?.title ?? "Libre", wide: true)
            }.padding(.horizontal, 18).padding(.top, 16)

            // Apps
            HStack(spacing: 7) {
                appTile("Party", "music.note", data.services.party, "https://osaparty.osalabs.fr")
                appTile("Drop", "paperplane.fill", data.services.drop, "https://osadrop.osalabs.fr")
                appTile("Cast", "play.rectangle.fill", data.services.cast, "https://osacast.osalabs.fr")
            }.padding(.horizontal, 18).padding(.top, 7)

            Spacer(minLength: 0)
        }
        .frame(width: Island.expandedW, height: Island.expandedH)
        .overlay(alignment: .topTrailing) { batteryBadge.padding(10) }
    }

    @ViewBuilder func artwork(_ s: CGFloat, radius: CGFloat) -> some View {
        if let a = data.artwork {
            Image(nsImage: a).resizable().frame(width: s, height: s).clipShape(RoundedRectangle(cornerRadius: radius))
                .shadow(color: data.accent.opacity(0.55), radius: s > 30 ? 10 : 0, y: 3)
        } else {
            RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.07)).frame(width: s, height: s)
                .overlay(Image(systemName: "music.note").font(.system(size: s * 0.4)).foregroundColor(.white.opacity(0.4)))
        }
    }

    var scrubber: some View {
        let dur = data.music?.duration ?? 0, pos = data.music?.position ?? 0
        let prog = dur > 0 ? min(1, pos / dur) : 0
        return VStack(spacing: 3) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(data.accent).frame(width: max(0, g.size.width * prog))
                }
            }.frame(height: 3)
            HStack {
                Text(fmt(pos)).font(.system(size: 8.5)).monospacedDigit().foregroundColor(.white.opacity(0.35))
                Spacer()
                Text(fmt(dur)).font(.system(size: 8.5)).monospacedDigit().foregroundColor(.white.opacity(0.35))
            }
        }
    }

    var batteryBadge: some View {
        Group {
            if let b = data.battery {
                HStack(spacing: 2) {
                    if b.charging { Image(systemName: "bolt.fill").font(.system(size: 8)) }
                    Text("\(b.percent)%").font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                }.foregroundColor(b.charging ? .green : (lowBat ? .red : .white.opacity(0.55)))
            }
        }
    }

    func ctrl(_ icon: String, _ sz: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: sz)).foregroundColor(.white.opacity(0.65)) }.buttonStyle(.plain)
    }

    func chip(_ icon: String, _ text: String, wide: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
            Text(text).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.72)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: wide ? .infinity : 96, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
    }

    func appTile(_ label: String, _ icon: String, _ online: Bool, _ url: String) -> some View {
        Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 14)).foregroundColor(.white.opacity(0.78))
                Text(label).font(.system(size: 9.5, weight: .medium)).foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
            .overlay(alignment: .topTrailing) { Circle().fill(online ? .green : Color.white.opacity(0.18)).frame(width: 4, height: 4).padding(6) }
        }.buttonStyle(.plain)
    }

    var airpodsText: String {
        guard let a = data.airpods else { return "—" }
        if let s = a.single { return "\(s)%" }
        return "\(a.left ?? 0)·\(a.right ?? 0)"
    }
    func fmt(_ s: Double) -> String { s <= 0 ? "0:00" : "\(Int(s)/60):" + String(format: "%02d", Int(s)%60) }
}
