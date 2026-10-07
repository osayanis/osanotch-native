import SwiftUI
import AppKit

// Coin arrondi en bas uniquement (haut plat, collé à l'écran comme l'encoche)
struct BottomRounded: Shape {
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Wave: View {
    var color: Color; var active: Bool
    @State private var phase = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 2.5, height: active ? (phase ? 13 : 5) + CGFloat(i % 2) * 3 : 4)
                    .animation(.easeInOut(duration: 0.4 + Double(i) * 0.08).repeatForever(autoreverses: true), value: phase)
            }
        }
        .frame(height: 14)
        .onAppear { phase = active }
        .onChange(of: active) { _, v in phase = v }
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

    var body: some View {
        ZStack(alignment: .top) {
            // Fond
            BottomRounded(radius: model.expanded ? 28 : 12)
                .fill(Color(red: 0.03, green: 0.03, blue: 0.04))
                .overlay(
                    BottomRounded(radius: model.expanded ? 28 : 12)
                        .fill(RadialGradient(colors: [data.accent.opacity(model.expanded && data.music != nil ? 0.22 : 0),
                                                      .clear],
                                             center: .top, startRadius: 0, endRadius: 260))
                )
                .shadow(color: .black.opacity(model.expanded ? 0.6 : 0), radius: 24, y: 12)

            if model.expanded { expandedView } else { collapsedView }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { model.expanded = h }
        }
        .ignoresSafeArea()
    }

    // MARK: Replié
    var collapsedView: some View {
        HStack {
            if playing, data.artwork != nil {
                Image(nsImage: data.artwork!).resizable().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                OsaCharacter(model: model, mood: .idle, accent: data.accent, size: 24)
            }
            Spacer()
            if playing { Wave(color: data.accent, active: true) }
        }
        .padding(.horizontal, 10)
        .frame(height: Island.collapsedH)
    }

    // MARK: Déployé
    var expandedView: some View {
        VStack(spacing: 10) {
            // Perso (star)
            OsaCharacter(model: model, mood: mood, accent: data.accent, size: 78)
                .padding(.top, 4)

            // Lecteur
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    artworkThumb
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.music?.title ?? "Rien en lecture").font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                        Text(data.music.map { "\($0.artist) · \($0.source)" } ?? "Apple Music · Spotify").font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
                    }
                    Spacer()
                    Wave(color: data.accent, active: playing)
                }
                scrubber
                HStack(spacing: 34) {
                    ctrlButton("backward.fill") { SystemData.controlMusic("previous track") }
                    Button { SystemData.controlMusic("playpause") } label: {
                        ZStack {
                            Circle().fill(.white).frame(width: 44, height: 44)
                            Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 17)).foregroundColor(.black)
                        }
                    }.buttonStyle(.plain)
                    ctrlButton("forward.fill") { SystemData.controlMusic("next track") }
                }
            }
            .padding(.horizontal, 16)

            // Pills
            HStack(spacing: 8) {
                pill(icon: "headphones", text: airpodsText)
                pill(icon: "calendar", text: data.event?.title ?? "Rien de prévu", wide: true)
            }.padding(.horizontal, 16)

            // Écosystème
            HStack(spacing: 8) {
                ecoButton("Party", "music.note", data.services.party, "https://osaparty.osalabs.fr")
                ecoButton("Drop", "paperplane.fill", data.services.drop, "https://osadrop.osalabs.fr")
                ecoButton("Cast", "play.rectangle.fill", data.services.cast, "https://osacast.osalabs.fr")
            }.padding(.horizontal, 16)
        }
        .padding(.bottom, 16)
        .overlay(alignment: .topTrailing) { batteryBadge.padding(.top, 8).padding(.trailing, 14) }
    }

    @ViewBuilder var artworkThumb: some View {
        if let art = data.artwork {
            Image(nsImage: art).resizable().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 11))
                .shadow(color: data.accent.opacity(0.6), radius: 8, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.06)).frame(width: 48, height: 48)
                .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.4)))
        }
    }

    var scrubber: some View {
        let dur = data.music?.duration ?? 0
        let pos = data.music?.position ?? 0
        let prog = dur > 0 ? min(1, pos / dur) : 0
        return HStack(spacing: 8) {
            Text(fmt(pos)).font(.system(size: 9)).monospacedDigit().foregroundColor(.white.opacity(0.35)).frame(width: 26, alignment: .trailing)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(data.accent).frame(width: g.size.width * prog)
                }
            }.frame(height: 3)
            Text(fmt(dur)).font(.system(size: 9)).monospacedDigit().foregroundColor(.white.opacity(0.35)).frame(width: 26, alignment: .leading)
        }
    }

    var batteryBadge: some View {
        Group {
            if let b = data.battery {
                HStack(spacing: 2) {
                    if b.charging { Image(systemName: "bolt.fill").font(.system(size: 9)) }
                    Text("\(b.percent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                }.foregroundColor(b.charging ? .green : (lowBat ? .red : .white.opacity(0.6)))
            }
        }
    }

    func ctrlButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 20)).foregroundColor(.white.opacity(0.6)) }.buttonStyle(.plain)
    }

    func pill(icon: String, text: String, wide: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(.white.opacity(0.45))
            Text(text).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.05)))
    }

    func ecoButton(_ label: String, _ icon: String, _ online: Bool, _ url: String) -> some View {
        Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.05)))
            .overlay(alignment: .topTrailing) {
                Circle().fill(online ? .green : Color.white.opacity(0.2)).frame(width: 4, height: 4).padding(6)
            }
        }.buttonStyle(.plain)
    }

    var airpodsText: String {
        guard let a = data.airpods else { return "—" }
        if let s = a.single { return "\(s)%" }
        return "\(a.left ?? 0)·\(a.right ?? 0)%"
    }

    func fmt(_ s: Double) -> String {
        if s <= 0 { return "0:00" }
        let m = Int(s) / 60, r = Int(s) % 60
        return "\(m):" + String(format: "%02d", r)
    }
}
