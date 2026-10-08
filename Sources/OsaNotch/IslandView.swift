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

    var playing: Bool { data.music?.playing ?? false }
    var lowBat: Bool { if let b = data.battery { return b.percent <= 15 && !b.charging } else { return false } }
    var mood: Mood {
        if !model.expanded { return .sleeping }
        if model.dropHover { return .happy }
        if lowBat { return .worried }
        if playing { return .dancing }
        return .idle
    }
    var size: CGSize { Island.shapeSize(expanded: model.expanded, view: model.view, playing: playing, volHUD: model.sysObs.showVolumeHUD, notchW: model.notchW, notchH: model.notchH, vh: model.viewHeight, sw: model.screenW) }

    var body: some View {
        let exp = model.expanded
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(bottom: exp ? 28 : 12).fill(Color.black)
                if exp { content.transition(.opacity) } else { collapsedView.transition(.opacity) }
                if model.dropHover { IslandShape(bottom: exp ? 28 : 12).stroke(data.accent, lineWidth: 2) }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(IslandShape(bottom: exp ? 28 : 12))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: model.view)
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: model.viewHeight)
        .ignoresSafeArea()
    }

    @ViewBuilder var content: some View {
        switch model.view {
        case .home:         homeView
        case .notes:        notesView
        case .dashboard:    DashboardView(model: model, accent: data.accent, back: { model.view = .home }).frame(width: 480, height: size.height)
        case .choice:       ChoiceView(model: model, accent: data.accent).frame(width: 380, height: size.height)
        case .notification: NotificationView(model: model, accent: data.accent).frame(width: 340, height: size.height)
        case .drop:         OsaDropView(model: model, accent: data.accent, back: { model.view = .home }, bridge: model.dropBridge).frame(width: 480, height: size.height)
        case .cast:         OsaCastView(model: model, accent: data.accent, back: { model.view = .home }, bridge: model.castBridge).frame(width: 520, height: size.height)
        case .onboarding:   OnboardingView(model: model, accent: data.accent).frame(width: 480, height: size.height)
        }
    }

    var collapsedView: some View {
        HStack(spacing: 0) {
            if model.sysObs.showVolumeHUD {
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundColor(.white).padding(.leading, 12).padding(.trailing, 8)
                GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(.white.opacity(0.14)); Capsule().fill(data.accent).frame(width: max(0, g.size.width * CGFloat(model.sysObs.volume))) } }.frame(height: 4).padding(.trailing, 16)
            }
            else if playing { artwork(18, 5); Spacer(); Waveform(color: data.accent, active: true) }
            else { Spacer(); OsaCharacter(model: model, mood: .idle, accent: data.accent, size: 28).offset(y: 5); Spacer() }
        }
        .padding(.horizontal, playing || model.sysObs.showVolumeHUD ? 12 : 0)
        .frame(width: model.sysObs.showVolumeHUD ? model.notchW + 140 : (playing ? model.notchW + 120 : model.notchW), height: model.notchH)
    }

    // ── Home centré ──
    var homeView: some View {
        VStack(spacing: 0) {
            TabBarView(model: model, accent: data.accent, dropHover: model.dropHover, battery: data.battery, lowBat: lowBat)

            Spacer(minLength: 2)
            OsaCharacter(model: model, mood: mood, accent: data.accent, size: 60)
            Text(model.dropHover ? "Dépose ton fichier" : (playing ? (data.music?.title ?? "") : "Salut Yanis"))
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1).padding(.horizontal, 24)
            Text(playing && !model.dropHover ? (data.music?.artist ?? "") : "OsaLabs")
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

    var notesView: some View {
        VStack(spacing: 0) {
            TabBarView(model: model, accent: data.accent, dropHover: model.dropHover, battery: data.battery, lowBat: lowBat)
            TextEditor(text: $notes).font(.system(size: 13)).scrollContentBackground(.hidden)
                .foregroundColor(.white).padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
                .padding(.horizontal, 20).padding(.bottom, 16)
        }.frame(width: size.width, height: size.height)
    }

    @ViewBuilder func artwork(_ s: CGFloat, _ radius: CGFloat) -> some View {
        if let a = data.artwork { Image(nsImage: a).resizable().frame(width: s, height: s).clipShape(RoundedRectangle(cornerRadius: radius)) }
        else { RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.08)).frame(width: s, height: s) }
    }

    var scrubber: some View {
        let dur = data.music?.duration ?? 0, pos = data.music?.position ?? 0
        let prog = dur > 0 ? min(1, pos / dur) : 0
        return GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(.white.opacity(0.14)); Capsule().fill(data.accent).frame(width: max(0, g.size.width * prog)) } }.frame(height: 3)
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
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.06)))
        }.buttonStyle(.plain)
    }

    func handleAirDrop(_ providers: [NSItemProvider]) -> Bool {
        print("📥 DROP RECEIVED! Providers count: \(providers.count)")
        guard let p = providers.first else { return false }
        print("📥 Loading provider: \(p.registeredTypeIdentifiers)")
        
        _ = p.loadObject(ofClass: URL.self) { url, error in
            print("📥 Loaded URL: \(String(describing: url)), Error: \(String(describing: error))")
            guard let url else { return }
            DispatchQueue.main.async {
                model.droppedURL = url
                model.view = .drop
            }
        }
        return true
    }
}
