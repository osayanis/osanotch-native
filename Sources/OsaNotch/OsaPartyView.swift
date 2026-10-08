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

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch mode {
                case .choose:  chooseView
                case .hosting: roomView
                case .joining: if connected { roomView } else { joiningView }
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { applyHeight() }
        .onChange(of: mode) { _, _ in applyHeight() }
        .onChange(of: bridge.phase) { _, _ in applyHeight() }
        .onChange(of: bridge.members) { _, _ in applyHeight() }
        // Moteur socket.io caché.
        .background(HiddenWeb(webView: bridge.webView).frame(width: 1, height: 1).opacity(0.02))
    }

    func applyHeight() {
        let h: CGFloat = mode == .choose ? 196 : (mode == .hosting || connected ? 250 : 236)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { model.viewHeight = h }
    }

    var header: some View {
        HStack(spacing: 9) {
            Button {
                if mode == .choose { back() } else { bridge.leave(); mode = .choose }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.8)).padding(8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if mode != .choose { OsaCharacter(model: model, mood: .dancing, accent: accent, size: 26) }
            VStack(alignment: .leading, spacing: 0) {
                Text("OsaParty").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text(connected ? "\(bridge.members) à l'écoute" : "Écoute synchronisée").font(.system(size: 9)).foregroundColor(connected ? accent : .white.opacity(0.4))
            }
            Spacer()
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
    }

    var chooseView: some View {
        HStack(spacing: 14) {
            optionCard("Créer", "Lancer un salon", "plus") { bridge.host(); mode = .hosting }
            OsaCharacter(model: model, mood: .dancing, accent: accent, size: 64)
            optionCard("Rejoindre", "Entrer un code", "arrow.right") { mode = .joining }
        }.padding(.horizontal, 18).padding(.top, 8)
    }

    var roomView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(accent.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.5), lineWidth: 1.5))
                VStack(spacing: 9) {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note.list").font(.system(size: 11)).foregroundColor(accent)
                        Text(bridge.mode == "host" ? "TON SALON" : "SALON REJOINT").font(.system(size: 10, weight: .bold)).foregroundColor(accent).tracking(1.5)
                    }
                    Text(bridge.code.isEmpty ? "····" : bridge.code).font(.system(size: 32, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(6)
                    if let m = model.data.music, m.playing {
                        Text("♪ \(m.title) — \(m.artist)").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)).lineLimit(1).padding(.horizontal, 16)
                    } else {
                        Text("Lance un morceau sur Apple Music").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.45))
                    }
                }
            }.frame(height: 148)
            Text("osaparty.osalabs.fr · partage ce code").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.35))
        }.padding(.horizontal, 22).padding(.top, 2)
    }

    var joiningView: some View {
        VStack(spacing: 14) {
            Text("Entre le code du salon").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            TextField("", text: $entry)
                .textFieldStyle(.plain).font(.system(size: 28, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).foregroundColor(.white).tracking(6)
                .frame(height: 56).background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
                .onChange(of: entry) { _, v in entry = String(v.uppercased().prefix(4)) }
            Button { bridge.join(entry) } label: {
                Text(bridge.phase == .joining && !connected ? "Connexion…" : (entry.count == 4 ? "Rejoindre" : "Code à 4 caractères")).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(entry.count == 4 ? .black : .white.opacity(0.4)).frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 13).fill(entry.count == 4 ? accent : .white.opacity(0.08)))
            }.buttonStyle(.plain).disabled(entry.count != 4)
            if bridge.phase == .error { Text("Salon introuvable").font(.system(size: 10)).foregroundColor(.red) }
        }.padding(.horizontal, 26).padding(.top, 2)
    }

    func optionCard(_ title: String, _ sub: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [accent.lighter(0.16), accent], startPoint: .top, endPoint: .bottom)).frame(width: 48, height: 48).shadow(color: accent.opacity(0.55), radius: 9, y: 3)
                    Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                }
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(.white)
                    Text(sub).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
