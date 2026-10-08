import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                Capsule().fill(color).frame(width: 2.5, height: active ? (on ? [10.0,16,8,13][i] : [5.0,8,13,6][i]) : 4)
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
    var size: CGSize { Island.shapeSize(expanded: model.expanded, view: model.view, playing: playing, full: model.screenW) }

    var body: some View {
        let exp = model.expanded
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(bottom: exp ? 28 : 12).fill(Color.black)
                if exp { content.transition(.opacity) } else { collapsedView.transition(.opacity) }
                if dropHover { IslandShape(bottom: exp ? 28 : 12).stroke(data.accent, lineWidth: 2) }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(IslandShape(bottom: exp ? 28 : 12))
            .onDrop(of: [UTType.fileURL], isTargeted: $dropHover) { handleDrop($0) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: model.view)
        .ignoresSafeArea()
    }

    @ViewBuilder var content: some View {
        switch model.view {
        case .home:  homeBar
        case .notes: notesView
        case .drop:  webView("https://osadrop.osalabs.fr", "OsaDrop")
        case .cast:  webView("https://osacast.osalabs.fr", "OsaCast")
        }
    }

    var collapsedView: some View {
        HStack(spacing: 0) {
            if playing { artwork(18, 5); Spacer(); Waveform(color: data.accent, active: true) }
            else { Spacer(); OsaCharacter(model: model, mood: .idle, accent: data.accent, size: 28).offset(y: 5); Spacer() }
        }
        .padding(.horizontal, playing ? 12 : 0)
        .frame(width: Island.collapsedW(playing), height: Island.collapsedH)
    }

    // ── Home : barre horizontale pleine largeur ──
    var homeBar: some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) { tbButton("house.fill", .home); tbButton("note.text", .notes) }
            OsaCharacter(model: model, mood: mood, accent: data.accent, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(dropHover ? "Dépose ton fichier" : (playing ? (data.music?.title ?? "") : "Salut Yanis"))
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Text(dropHover ? "pour AirDrop" : (playing ? (data.music?.artist ?? "") : "OsaLabs"))
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
            }.frame(width: 150, alignment: .leading)

            Spacer(minLength: 8)

            if playing {
                HStack(spacing: 14) {
                    artwork(46, 11)
                    VStack(alignment: .leading, spacing: 5) {
                        scrubber.frame(width: 190)
                        Waveform(color: data.accent, active: true)
                    }
                    HStack(spacing: 16) {
                        ctrl("backward.fill", 14) { SystemData.controlMusic("previous track") }
                        Button { SystemData.controlMusic("playpause") } label: {
                            ZStack { Circle().fill(.white).frame(width: 34, height: 34).shadow(color: data.accent.opacity(0.7), radius: 7, y: 2)
                                Image(systemName: "pause.fill").font(.system(size: 14)).foregroundColor(.black) }
                        }.buttonStyle(.plain)
                        ctrl("forward.fill", 14) { SystemData.controlMusic("next track") }
                    }
                }
                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                appTile("Party", "music.note", data.services.party) { NSWorkspace.shared.open(URL(string: "https://osaparty.osalabs.fr")!) }
                appTile("Drop", "paperplane.fill", data.services.drop) { model.view = .drop }
                appTile("Cast", "play.rectangle.fill", data.services.cast) { model.view = .cast }
            }
            batteryBadge
        }
        .padding(.horizontal, 36)
        .frame(width: size.width, height: size.height)
    }

    var notesView: some View {
        VStack(spacing: 0) {
            viewHeader("Bloc-note", "note.text")
            TextEditor(text: $notes).font(.system(size: 13)).scrollContentBackground(.hidden)
                .foregroundColor(.white).padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
                .frame(maxWidth: 640).padding(.horizontal, 24).padding(.bottom, 18)
        }.frame(width: size.width, height: size.height)
    }

    func webView(_ url: String, _ title: String) -> some View {
        VStack(spacing: 0) {
            viewHeader(title, title == "OsaDrop" ? "paperplane.fill" : "play.rectangle.fill")
            WebPane(url: URL(string: url)!).clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 900).padding(.horizontal, 20).padding(.bottom, 16)
        }.frame(width: size.width, height: size.height)
    }

    func viewHeader(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Button { model.view = .home } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.7)) }.buttonStyle(.plain)
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(data.accent)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            Spacer(); batteryBadge
        }.frame(maxWidth: 900).padding(.horizontal, 24).padding(.top, 11).padding(.bottom, 8)
    }

    func tbButton(_ icon: String, _ target: AppView) -> some View {
        Button { model.view = target } label: {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(model.view == target ? .white : .white.opacity(0.4))
        }.buttonStyle(.plain)
    }

    @ViewBuilder func artwork(_ s: CGFloat, _ radius: CGFloat) -> some View {
        if let a = data.artwork { Image(nsImage: a).resizable().frame(width: s, height: s).clipShape(RoundedRectangle(cornerRadius: radius)) }
        else { RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.08)).frame(width: s, height: s).overlay(Image(systemName: "music.note").font(.system(size: s*0.4)).foregroundColor(.white.opacity(0.35))) }
    }

    var scrubber: some View {
        let dur = data.music?.duration ?? 0, pos = data.music?.position ?? 0
        let prog = dur > 0 ? min(1, pos / dur) : 0
        return GeometryReader { g in
            ZStack(alignment: .leading) { Capsule().fill(.white.opacity(0.14)); Capsule().fill(data.accent).frame(width: max(0, g.size.width * prog)) }
        }.frame(height: 3)
    }

    var batteryBadge: some View {
        Group {
            if let b = data.battery {
                HStack(spacing: 2) {
                    if b.charging { Image(systemName: "bolt.fill").font(.system(size: 9)) }
                    Text("\(b.percent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                }.foregroundColor(b.charging ? .green : (lowBat ? .red : .white.opacity(0.55)))
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
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundColor(.white.opacity(0.65))
                Circle().fill(online ? .green : Color.white.opacity(0.2)).frame(width: 4, height: 4)
            }.padding(.horizontal, 12).padding(.vertical, 8)
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
