import SwiftUI
import AppKit

struct OsaPartyView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void
    @ObservedObject var bridge: PartyBridge

    enum Mode { case choose, hosting, joining }
    @State private var mode: Mode = .choose
    @State private var entry: String = ""

    var connected: Bool { bridge.phase == .connected }
    var inRoom: Bool { mode == .hosting || (mode == .joining && connected) }

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
        .onChange(of: mode) { _, _ in applyHeight() }
        .onChange(of: bridge.phase) { _, _ in applyHeight() }
        .onChange(of: bridge.members) { _, _ in applyHeight() }
        .background(HiddenWeb(webView: bridge.webView).frame(width: 1, height: 1).opacity(0.02))
    }

    func applyHeight() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { model.viewHeight = inRoom ? 238 : 210 }
    }

    // ── Boîte Créer (comme OsaCast / OsaDrop) ──
    var creerBox: some View {
        Button { bridge.host(); mode = .hosting } label: {
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
                            if entry.count == 6 { mode = .joining; bridge.join(entry) }
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
            VStack(spacing: 9) {
                HStack(spacing: 6) {
                    Circle().fill(connected || bridge.mode == "host" ? .green : .white.opacity(0.4)).frame(width: 7, height: 7)
                    Text(bridge.mode == "host" ? "TON SALON" : "SALON REJOINT").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6)).tracking(1.5)
                    Spacer()
                    Text("\(bridge.members) à l'écoute").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.4))
                }
                Text(bridge.code.isEmpty ? "······" : bridge.code).font(.system(size: 32, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(5)
                if let m = model.data.music, m.playing {
                    Text("♪ \(m.title) — \(m.artist)").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                } else {
                    Text("Lance un morceau sur Apple Music").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 1))

            HStack {
                Text("osaparty.osalabs.fr · partage le code").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.35))
                Spacer()
                Button { bridge.leave(); mode = .choose; entry = "" } label: {
                    Text("Quitter").font(.system(size: 11, weight: .semibold)).foregroundColor(.red)
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 20).padding(.top, 2)
    }
}
