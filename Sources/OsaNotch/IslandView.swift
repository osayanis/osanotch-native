import SwiftUI
import AppKit

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
        }.frame(height: 16).onAppear { on = active }.onChange(of: active) { _, v in on = v }
    }
}

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var data: SystemData

    var playing: Bool { data.music?.playing ?? false }
    var lowBat: Bool { if let b = data.battery { return b.percent <= 15 && !b.charging } else { return false } }
    var mood: Mood {
        if !model.expanded { return .sleeping }
        if lowBat { return .worried }
        if playing { return .dancing }
        return .idle
    }
    var collapsedW: CGFloat { playing ? 300 : 186 }

    var body: some View {
        let exp = model.expanded
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(top: exp ? 16 : 0, bottom: exp ? 32 : 12).fill(Color.black)
                if exp { expandedView.transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top))) }
                else { collapsedView.transition(.opacity) }
            }
            .frame(width: exp ? Island.expandedW : collapsedW,
                   height: exp ? Island.expandedH : Island.collapsedH)
            .clipShape(IslandShape(top: exp ? 16 : 0, bottom: exp ? 32 : 12))
            .shadow(color: .black.opacity(exp ? 0.55 : 0), radius: 22, y: 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.expanded)
        .ignoresSafeArea()
    }

    // Replié
    var collapsedView: some View {
        HStack(spacing: 0) {
            if playing {
                artwork(18, 5); Spacer(); Waveform(color: data.accent, active: true)
            } else {
                Spacer(); OsaCharacter(model: model, mood: .idle, accent: data.accent, size: 28).offset(y: 5); Spacer()
            }
        }
        .padding(.horizontal, playing ? 12 : 0)
        .frame(width: collapsedW, height: Island.collapsedH)
    }

    // Déployé — home façon îlot
    var expandedView: some View {
        VStack(spacing: 0) {
            // Barre d'outils
            HStack(spacing: 14) {
                tbIcon("house.fill")
                tbIcon("square.grid.2x2.fill")
                Spacer()
                batteryBadge
            }
            .padding(.horizontal, 18).padding(.top, 11)

            Spacer(minLength: 2)

            OsaCharacter(model: model, mood: mood, accent: data.accent, size: 60)

            Text(playing ? (data.music?.title ?? "") : "Salut Yanis")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1).padding(.horizontal, 24)
            Text(playing ? (data.music?.artist ?? "") : "OsaLabs")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1)

            Spacer(minLength: 6)

            if playing {
                scrubber.padding(.horizontal, 40)
                HStack(spacing: 30) {
                    ctrl("backward.fill", 16) { SystemData.controlMusic("previous track") }
                    Button { SystemData.controlMusic("playpause") } label: {
                        ZStack {
                            Circle().fill(.white).frame(width: 38, height: 38).shadow(color: data.accent.opacity(0.7), radius: 8, y: 2)
                            Image(systemName: "pause.fill").font(.system(size: 15)).foregroundColor(.black)
                        }
                    }.buttonStyle(.plain)
                    ctrl("forward.fill", 16) { SystemData.controlMusic("next track") }
                }.padding(.top, 8)
                Spacer(minLength: 8)
            }

            // Lanceurs
            HStack(spacing: 8) {
                appTile("Party", "music.note", data.services.party, "https://osaparty.osalabs.fr")
                appTile("Drop", "paperplane.fill", data.services.drop, "https://osadrop.osalabs.fr")
                appTile("Cast", "play.rectangle.fill", data.services.cast, "https://osacast.osalabs.fr")
            }.padding(.horizontal, 16).padding(.bottom, 14)
        }
        .frame(width: Island.expandedW, height: Island.expandedH)
    }

    func tbIcon(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
    }

    @ViewBuilder func artwork(_ s: CGFloat, _ radius: CGFloat) -> some View {
        if let a = data.artwork {
            Image(nsImage: a).resizable().frame(width: s, height: s).clipShape(RoundedRectangle(cornerRadius: radius))
        } else {
            RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.08)).frame(width: s, height: s)
        }
    }

    var scrubber: some View {
        let dur = data.music?.duration ?? 0, pos = data.music?.position ?? 0
        let prog = dur > 0 ? min(1, pos / dur) : 0
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(data.accent).frame(width: max(0, g.size.width * prog))
            }
        }.frame(height: 3)
    }

    var batteryBadge: some View {
        Group {
            if let b = data.battery {
                HStack(spacing: 2) {
                    if b.charging { Image(systemName: "bolt.fill").font(.system(size: 8)) }
                    Text("\(b.percent)%").font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                }.foregroundColor(b.charging ? .green : (lowBat ? .red : .white.opacity(0.5)))
            }
        }
    }

    func ctrl(_ icon: String, _ sz: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: sz)).foregroundColor(.white.opacity(0.65)) }.buttonStyle(.plain)
    }

    func appTile(_ label: String, _ icon: String, _ online: Bool, _ url: String) -> some View {
        Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundColor(.white.opacity(0.6))
                Circle().fill(online ? .green : Color.white.opacity(0.2)).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.06)))
        }.buttonStyle(.plain)
    }
}
