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
    var size: CGSize { Island.shapeSize(expanded: model.expanded, view: model.view, playing: playing, hud: model.sysObs.showVolumeHUD || model.sysObs.showBrightnessHUD, notifBanner: model.showNotifBanner, notchW: model.notchW, notchH: model.notchH, vh: model.viewHeight, sw: model.screenW) }

    var body: some View {
        let exp = model.expanded
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(bottom: exp ? 28 : 12).fill(Color.black)
                if exp { content.transition(.opacity) }
                else if model.view == .notification && model.showNotifBanner { notifBanner.transition(.opacity) }
                else { collapsedView.transition(.opacity) }
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
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.sysObs.showVolumeHUD)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.sysObs.showBrightnessHUD)
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: playing)
        .animation(.spring(response: 0.44, dampingFraction: 0.8), value: model.showNotifBanner)
        .ignoresSafeArea()
    }

    @ViewBuilder var content: some View {
        switch model.view {
        case .home:         homeView
        case .notes:        notesView
        case .dashboard:    DashboardView(model: model, accent: data.accent, back: { model.view = .home }).frame(width: 480, height: size.height)
        case .choice:       ChoiceView(model: model, accent: data.accent).frame(width: 380, height: size.height)
        case .notification: notifCenterView.frame(width: size.width, height: size.height)
        case .drop:         OsaDropView(model: model, accent: data.accent, back: { model.view = .home }, bridge: model.dropBridge).frame(width: 480, height: size.height)
        case .cast:         OsaCastView(model: model, accent: data.accent, back: { model.view = .home }, bridge: model.castBridge).frame(width: 520, height: size.height)
        case .party:        OsaPartyView(model: model, accent: data.accent, back: { model.view = .home }, bridge: model.partyBridge).frame(width: 500, height: size.height)
        case .onboarding:   OnboardingView(model: model, accent: data.accent).frame(width: 480, height: size.height)
        }
    }

    var hudActive: Bool { model.sysObs.showVolumeHUD || model.sysObs.showBrightnessHUD }

    // Bannière de notification : apparaît sous l'encoche sans survol.
    var notifBanner: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: model.notchH)
            HStack(spacing: 11) {
                OsaCharacter(model: model, mood: .happy, accent: data.accent, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Assistant IA").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    Text(model.notification ?? "Tâche terminée").font(.system(size: 11)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .frame(width: 360, height: model.notchH + 52)
    }

    // Écran de notifications : mascotte à gauche, notifications récentes à droite.
    var notifCenterView: some View {
        HStack(spacing: 16) {
            VStack {
                OsaCharacter(model: model, mood: .happy, accent: data.accent, size: 58)
                Text("Assistant IA").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6))
            }
            .frame(width: 110)
            .transition(.move(edge: .leading).combined(with: .opacity))

            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications récentes").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.45))
                if model.notifications.isEmpty {
                    Text("Rien pour le moment").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                } else {
                    ForEach(model.notifications.prefix(3)) { n in
                        HStack(alignment: .top, spacing: 9) {
                            Circle().fill(data.accent).frame(width: 6, height: 6).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.text).font(.system(size: 12.5, weight: .medium)).foregroundColor(.white).lineLimit(2)
                                Text(relTime(n.date)).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.35))
                            }
                            Spacer()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 14)
    }

    func relTime(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "à l'instant" }
        if s < 3600 { return "il y a \(s / 60) min" }
        return "il y a \(s / 3600) h"
    }

    @ViewBuilder var collapsedView: some View {
        if hudActive { hudView }
        else if playing {
            HStack(spacing: 0) { artwork(18, 5); Spacer(); Waveform(color: data.accent, active: true) }
                .padding(.horizontal, 12)
                .frame(width: model.notchW + 120, height: model.notchH)
        }
        else {
            HStack(spacing: 0) { Spacer(); OsaCharacter(model: model, mood: .idle, accent: data.accent, size: 28).offset(y: 5); Spacer() }
                .frame(width: model.notchW, height: model.notchH)
        }
    }

    func volumeIcon(_ v: Float) -> String {
        if v <= 0.001 { return "speaker.slash.fill" }
        if v < 0.34 { return "speaker.wave.1.fill" }
        if v < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // HUD volume / luminosité : pastille blanche qui descend sous l'encoche.
    var hudView: some View {
        let isVol = model.sysObs.showVolumeHUD
        let value = CGFloat(isVol ? model.sysObs.volume : model.sysObs.brightness)
        let icon = isVol ? volumeIcon(model.sysObs.volume) : "sun.max.fill"
        return VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: model.notchH)
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 20)
                    .contentTransition(.symbolEffect(.replace))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(Color.white)
                            .frame(width: max(5, g.size.width * value))
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 18)
            .frame(height: 30)
        }
        .frame(width: model.notchW + 190, height: model.notchH + 30)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.sysObs.volume)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.sysObs.brightness)
    }

    // ── Home ──
    var homeView: some View {
        VStack(spacing: 0) {
            TabBarView(model: model, accent: data.accent, dropHover: model.dropHover, battery: data.battery, lowBat: lowBat)
            if playing && !model.dropHover {
                playerView.transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                idleHome.transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // Accueil au repos : mascotte + raccourcis.
    var idleHome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 2)
            OsaCharacter(model: model, mood: mood, accent: data.accent, size: 60)
            Text(model.dropHover ? "Dépose ton fichier" : "Salut Yanis")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1).padding(.horizontal, 24)
            Text("OsaLabs")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                appTile("Party", "music.note", data.services.party) { NSWorkspace.shared.open(URL(string: "https://osaparty.osalabs.fr")!) }
                appTile("Drop", "paperplane.fill", data.services.drop) { model.view = .drop }
                appTile("Cast", "play.rectangle.fill", data.services.cast) { model.view = .cast }
            }.padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    // ── Lecteur musique : pochette à gauche, paroles + barre + contrôles à droite ──
    var playerView: some View {
        HStack(alignment: .center, spacing: 14) {
            artwork(92, 13)
                .shadow(color: data.accent.opacity(0.5), radius: 11, y: 4)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(data.music?.title ?? "")
                        .font(.system(size: 13.5, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text(data.music?.artist ?? "")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
                }

                Spacer(minLength: 5)
                lyricsBlock
                Spacer(minLength: 5)

                HStack(spacing: 12) {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        playerScrubber(now: ctx.date)
                    }
                    HStack(spacing: 16) {
                        ctrl("backward.fill", 13) { SystemData.controlMusic("previous track") }
                        Button { SystemData.controlMusic("playpause") } label: {
                            ZStack {
                                Circle().fill(.white).frame(width: 30, height: 30).shadow(color: data.accent.opacity(0.6), radius: 6, y: 1)
                                Image(systemName: "pause.fill").font(.system(size: 12)).foregroundColor(.black)
                            }
                        }.buttonStyle(.plain)
                        ctrl("forward.fill", 13) { SystemData.controlMusic("next track") }
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 12)
    }

    // Position lue + temps écoulé depuis la lecture → progression fluide entre deux sondages.
    func livePosition(_ now: Date) -> Double {
        guard let m = data.music else { return 0 }
        var p = m.position
        if m.playing { p += now.timeIntervalSince(data.positionSampledAt) }
        return m.duration > 0 ? min(p, m.duration) : p
    }

    @ViewBuilder var lyricsBlock: some View {
        if data.lyrics.isEmpty {
            // Pas de paroles trouvées : petit égaliseur discret pour ne pas laisser de vide.
            HStack { Waveform(color: data.accent, active: true); Spacer() }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let idx = currentLyric(at: livePosition(ctx.date))
                // Style Apple Music : la ligne active glisse vers le haut, la suivante monte à sa place.
                VStack(alignment: .leading, spacing: 2) {
                    lyricLine(idx, active: true)
                    lyricLine(idx + 1, active: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: idx)
            }
        }
    }

    @ViewBuilder func lyricLine(_ i: Int, active: Bool) -> some View {
        let text = (i >= 0 && i < data.lyrics.count) ? data.lyrics[i].text : (active && i < 0 ? "♪" : " ")
        Text(text)
            .font(.system(size: active ? 15 : 11.5, weight: active ? .semibold : .regular))
            .foregroundColor(.white.opacity(active ? 1 : 0.3))
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("\(active ? "a" : "b")-\(i)")
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)))
    }

    func currentLyric(at pos: Double) -> Int {
        var idx = -1
        for (i, l) in data.lyrics.enumerated() { if l.t <= pos + 0.2 { idx = i } else { break } }
        return idx
    }

    func timeStr(_ s: Double) -> String {
        let t = max(0, Int(s)); return String(format: "%d:%02d", t / 60, t % 60)
    }

    func playerScrubber(now: Date) -> some View {
        let dur = data.music?.duration ?? 0
        let pos = livePosition(now)
        let prog = dur > 0 ? min(1, pos / dur) : 0
        return VStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(data.accent).frame(width: max(0, g.size.width * prog))
                }
            }.frame(height: 4)
            HStack {
                Text(timeStr(pos)).font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("-" + timeStr(dur - pos)).font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundColor(.white.opacity(0.4))
            }
        }
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
