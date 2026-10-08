import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Coins HAUT carrés (bloc collé au sommet), bas arrondi.
struct IslandShape: Shape {
    var bottom: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.maxX - bottom, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bottom), control: CGPoint(x: r.minX, y: r.maxY))
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
    @AppStorage("osa.notes") private var notes: String = ""
    @State private var dropHover = false

    var playing: Bool { data.music?.playing ?? false }
    var lowBat: Bool { if let b = data.battery { return b.percent <= 15 && !b.charging } else { return false } }
    var mood: Mood {
        if !model.expanded { return .sleeping }
        if dropHover { return .happy }
        if lowBat { return .worried }
        if playing { return .dancing }
        return .idle
    }

    var size: CGSize { Island.shapeSize(expanded: model.expanded, view: model.view, playing: playing) }

    var body: some View {
        let exp = model.expanded
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(bottom: exp ? 30 : 12).fill(Color.black)
                if exp {
                    content.transition(.opacity)
                } else {
                    collapsedView.transition(.opacity)
                }
                if dropHover {
                    IslandShape(bottom: exp ? 30 : 12).stroke(data.accent, lineWidth: 2)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(IslandShape(bottom: exp ? 30 : 12))
            .shadow(color: .black.opacity(exp ? 0.55 : 0), radius: 24, y: 10)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropHover) { providers in handleDrop(providers) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.view)
        .ignoresSafeArea()
    }

    @ViewBuilder var content: some View {
        switch model.view {
        case .home:  homeView
        case .notes: notesView
        case .drop:  webView("https://osadrop.osalabs.fr", "OsaDrop")
        case .cast:  webView("https://osacast.osalabs.fr", "OsaCast")
        }
    }

    // ── Replié ──
    var collapsedView: some View {
        HStack(spacing: 0) {
            if playing { artwork(18, 5); Spacer(); Waveform(color: data.accent, active: true) }
            else { Spacer(); OsaCharacter(model: model, mood: .idle, accent: data.accent, size: 28).offset(y: 5); Spacer() }
        }
        .padding(.horizontal, playing ? 12 : 0)
        .frame(width: Island.collapsedW(playing), height: Island.collapsedH)
    }

    // ── Home ──
    var homeView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                tbButton("house.fill") { model.view = .home }
                tbButton("note.text") { model.view = .notes }
                Spacer()
                if dropHover { Text("Lâcher pour AirDrop").font(.system(size: 10, weight: .semibold)).foregroundColor(data.accent) }
                batteryBadge
            }.padding(.horizontal, 18).padding(.top, 11)

            Spacer(minLength: 2)
            OsaCharacter(model: model, mood: mood, accent: data.accent, size: 60)
            Text(dropHover ? "Dépose ton fichier" : (playing ? (data.music?.title ?? "") : "Salut Yanis"))
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1).padding(.horizontal, 24)
            Text(playing && !dropHover ? (data.music?.artist ?? "") : "OsaLabs")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
            Spacer(minLength: 6)

            if playing {
                scrubber.padding(.horizontal, 44)
                HStack(spacing: 32) {
                    ctrl("backward.fill", 16) { SystemData.controlMusic("previous track") }
                    Button { SystemData.controlMusic("playpause") } label: {
                        ZStack { Circle().fill(.white).frame(width: 38, height: 38).shadow(color: data.accent.opacity(0.7), radius: 8, y: 2)
                            Image(systemName: "pause.fill").font(.system(size: 15)).foregroundColor(.black) }
                    }.buttonStyle(.plain)
                    ctrl("forward.fill", 16) { SystemData.controlMusic("next track") }
                }.padding(.top, 8)
                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                appTile("Party", "music.note", data.services.party) { NSWorkspace.shared.open(URL(string: "https://osaparty.osalabs.fr")!) }
                appTile("Drop", "paperplane.fill", data.services.drop) { model.view = .drop }
                appTile("Cast", "play.rectangle.fill", data.services.cast) { model.view = .cast }
            }.padding(.horizontal, 16).padding(.bottom, 14)
        }
        .frame(width: size.width, height: size.height)
    }

    // ── Bloc-note ──
    var notesView: some View {
        VStack(spacing: 0) {
            viewHeader("Bloc-note", "note.text")
            TextEditor(text: $notes)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .foregroundColor(.white).padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
                .padding(.horizontal, 16).padding(.bottom, 16)
        }.frame(width: size.width, height: size.height)
    }

    // ── OsaDrop / OsaCast embarqués ──
    func webView(_ url: String, _ title: String) -> some View {
        VStack(spacing: 0) {
            viewHeader(title, title == "OsaDrop" ? "paperplane.fill" : "play.rectangle.fill")
            WebPane(url: URL(string: url)!)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 12).padding(.bottom, 14)
        }.frame(width: size.width, height: size.height)
    }

    func viewHeader(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Button { model.view = .home } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(data.accent)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            Spacer()
            batteryBadge
        }.padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 8)
    }

    // ── Helpers ──
    func tbButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(model.view == viewFor(icon) ? .white : .white.opacity(0.4))
        }.buttonStyle(.plain)
    }
    func viewFor(_ icon: String) -> AppView { icon == "note.text" ? .notes : .home }

    @ViewBuilder func artwork(_ s: CGFloat, _ radius: CGFloat) -> some View {
        if let a = data.artwork { Image(nsImage: a).resizable().frame(width: s, height: s).clipShape(RoundedRectangle(cornerRadius: radius)) }
        else { RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.08)).frame(width: s, height: s) }
    }

    var scrubber: some View {
        let dur = data.music?.duration ?? 0, pos = data.music?.position ?? 0
        let prog = dur > 0 ? min(1, pos / dur) : 0
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)); Capsule().fill(data.accent).frame(width: max(0, g.size.width * prog))
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

    func appTile(_ label: String, _ icon: String, _ online: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundColor(.white.opacity(0.6))
                Circle().fill(online ? .green : Color.white.opacity(0.2)).frame(width: 4, height: 4)
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.06)))
        }.buttonStyle(.plain)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                let svc = NSSharingService(named: .sendViaAirDrop) ?? NSSharingService(named: NSSharingService.Name("com.apple.share.AirDrop.send"))
                svc?.perform(withItems: [url])
            }
        }
        return true
    }
}
