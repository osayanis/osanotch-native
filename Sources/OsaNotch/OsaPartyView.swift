import SwiftUI
import AppKit

struct OsaPartyView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void
    @ObservedObject var bridge: PartyBridge

    @State private var entry: String = ""

    var connected: Bool { bridge.phase == .connected }
    // Lu depuis le pont (possédé par AppModel) et non un @State : la vue est recréée
    // à chaque dépli du notch, le salon, lui, reste connecté.
    var inRoom: Bool { !bridge.code.isEmpty && (bridge.mode == "host" || connected) }

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(model: model, accent: accent, dropHover: false, battery: model.data.battery, lowBat: (model.data.battery?.percent ?? 100) < 20)
            ZStack {
                if inRoom { roomView }
                else {
                    HStack(spacing: 12) {
                        creerBox
                        rejoindreBox
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { applyHeight() }
        .onChange(of: inRoom) { _, _ in applyHeight() }
        .onChange(of: bridge.phase) { _, _ in applyHeight() }
        .onChange(of: bridge.members) { _, _ in applyHeight() }
    }

    func applyHeight() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { model.viewHeight = inRoom ? 238 : 210 }
    }

    // ── Boîte Créer (comme OsaCast / OsaDrop) ──
    var creerBox: some View {
        Button { bridge.host() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(.white.opacity(0.2))
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(.white.opacity(0.1)).frame(width: 48, height: 48)
                        Image(systemName: "music.note.list").font(.system(size: 19)).foregroundColor(.white)
                    }
                    Text("Créer").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Text("Lancer un salon").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 150)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // ── Boîte Rejoindre (champ code, comme OsaCast) ──
    var rejoindreBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundColor(.white.opacity(0.2))
            if bridge.phase == .joining && !connected {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Connexion…").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                }
            } else {
                VStack(spacing: 12) {
                    Text("REJOINDRE").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6)).tracking(1.5)
                    TextField("CODE", text: $entry)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 110, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)))
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .onChange(of: entry) { _, new in
                            entry = String(new.filter { $0.isNumber }.prefix(6))
                            if entry.count == 6 { bridge.join(entry) }
                        }
                    Text(bridge.phase == .error ? "Salon introuvable" : "Code à 6 chiffres")
                        .font(.system(size: 10)).foregroundColor(bridge.phase == .error ? .red : .white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 150)
    }

    // ── Dans le salon ──
    var roomView: some View {
        VStack(spacing: 10) {
            // Bandeau du haut avec le code
            HStack(spacing: 6) {
                Circle().fill(connected || bridge.mode == "host" ? .green : .white.opacity(0.4)).frame(width: 7, height: 7)
                Text(bridge.mode == "host" ? "TON SALON" : "SALON REJOINT").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6)).tracking(1.5)
                Spacer()
                Text(bridge.code.isEmpty ? "······" : bridge.code).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(3)
                Spacer()
                Image(systemName: "headphones").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                Text("\(bridge.members)").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 4)

            // Mini-lecteur façon Dashboard
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06))
                
                if let art = model.data.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 86)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .blur(radius: 20)
                        .opacity(0.4)
                }
                
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        if let art = model.data.artwork {
                            Image(nsImage: art).resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        } else {
                            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)).frame(width: 44, height: 44)
                                .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.3)))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            let title = bridge.mode == "guest" ? (bridge.remoteMusic?.title ?? "En attente du host...") : (model.data.music?.title ?? "Aucune lecture")
                            let artist = bridge.mode == "guest" ? (bridge.remoteMusic?.artist ?? "OsaParty") : (model.data.music?.artist ?? "Apple Music / Spotify")
                            Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
                            Text(artist).font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer()
                        
                        // Contrôles
                        HStack(spacing: 8) {
                            Button { SystemData.controlMusic("previous track") } label: {
                                Image(systemName: "backward.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                            }.buttonStyle(.plain)
                            
                            let playing = bridge.mode == "guest" ? (bridge.remoteMusic?.playing == true) : (model.data.music?.playing == true)
                            Button { SystemData.controlMusic("playpause") } label: {
                                ZStack {
                                    Circle().fill(.white).frame(width: 32, height: 32)
                                    Image(systemName: playing ? "pause.fill" : "play.fill")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundColor(.black)
                                        .offset(x: playing ? 0 : 1.5)
                                }
                            }.buttonStyle(.plain)
                            
                            Button { SystemData.controlMusic("next track") } label: {
                                Image(systemName: "forward.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                            }.buttonStyle(.plain)
                        }
                    }
                    
                    // Barre de progression
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let dur = model.data.music?.duration ?? 0
                        let pos = livePos(ctx.date)
                        let prog = dur > 0 ? min(1, pos / dur) : 0
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                                Capsule().fill(accent).frame(width: g.size.width * prog, height: 4)
                            }
                        }.frame(height: 4)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .frame(height: 86)

            HStack {
                Text("osaparty.osalabs.fr · rejoins sur le web").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.35))
                Spacer()
                Button { bridge.leave(); entry = "" } label: {
                    Text("Quitter le salon").font(.system(size: 10, weight: .bold)).foregroundColor(.red.opacity(0.8))
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 20).padding(.top, 2)
    }

    func livePos(_ now: Date) -> Double {
        guard let m = model.data.music else { return 0 }
        var p = m.position
        if m.playing { p += now.timeIntervalSince(model.data.positionSampledAt) }
        return m.duration > 0 ? min(p, m.duration) : p
    }
}
