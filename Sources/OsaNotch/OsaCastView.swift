import SwiftUI
import AppKit

struct OsaCastView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void

    enum Mode { case choose, hosting, joining }
    @State private var mode: Mode = .choose
    @State private var entry: String = ""
    @ObservedObject var bridge: CastBridge

    var watching: Bool { mode == .joining && (bridge.phase == .connected || bridge.phase == .live) }
    var mascotMood: Mood { mode == .hosting ? .happy : .idle }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                // Moteur WebRTC : caché (1×1) par défaut, plein cadre quand on regarde un cast
                HiddenWeb(webView: bridge.webView)
                    .frame(maxWidth: watching ? .infinity : 1, maxHeight: watching ? .infinity : 1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(watching ? 1 : 0.02)
                if !watching {
                    switch mode {
                    case .choose:  chooseView
                    case .hosting: hostingView
                    case .joining: joiningView
                    }
                }
            }
            .padding(watching ? 10 : 0)
            Spacer(minLength: 0)
        }
        .onAppear {
            applyHeight()
            // Le notch vient d'être rouvert : si un cast était en cours, on relance la vidéo.
            if bridge.phase == .connected || bridge.phase == .live {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { bridge.resume() }
            }
        }
        .onChange(of: mode) { _, _ in applyHeight() }
        .onChange(of: bridge.phase) { _, _ in applyHeight() }
    }

    func applyHeight() {
        let h: CGFloat = watching ? 340 : (mode == .choose ? 192 : (mode == .hosting ? 248 : 236))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) { model.viewHeight = h }
    }

    var header: some View {
        HStack(spacing: 9) {
            Button { if mode == .choose { back() } else { bridge.stop(); mode = .choose } } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.8)).padding(8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if mode != .choose { OsaCharacter(model: model, mood: mascotMood, accent: accent, size: 26) }
            VStack(alignment: .leading, spacing: 0) {
                Text("OsaCast").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text(watching ? "En direct" : "Partage d'écran").font(.system(size: 9)).foregroundColor(watching ? .red : .white.opacity(0.4))
            }
            Spacer()
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
    }

    var chooseView: some View {
        HStack(spacing: 14) {
            optionCard("Créer", "Diffuser", "plus") { bridge.host(); mode = .hosting }
            OsaCharacter(model: model, mood: .idle, accent: accent, size: 64)
            optionCard("Rejoindre", "Regarder", "arrow.right") { mode = .joining }
        }.padding(.horizontal, 18).padding(.top, 10)
    }

    var hostingView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.black).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.red.opacity(0.55), lineWidth: 1.5))
                VStack(spacing: 10) {
                    HStack(spacing: 6) { Circle().fill(.red).frame(width: 8, height: 8); Text(bridge.phase == .connected || bridge.phase == .live ? "EN DIRECT" : "EN ATTENTE").font(.system(size: 10, weight: .bold)).foregroundColor(.red).tracking(1.5) }
                    Text(bridge.code.isEmpty ? "······" : bridge.code).font(.system(size: 32, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(6)
                    Text(bridge.phase == .error ? "Capture d'écran refusée" : "Donne ce code pour te regarder").font(.system(size: 10.5)).foregroundColor(bridge.phase == .error ? .red : .white.opacity(0.5))
                }
            }.frame(height: 150)
        }.padding(.horizontal, 22).padding(.top, 2)
    }

    var joiningView: some View {
        VStack(spacing: 14) {
            Text("Entre le code de la room").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            TextField("", text: $entry)
                .textFieldStyle(.plain).font(.system(size: 28, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).foregroundColor(.white).tracking(6)
                .frame(height: 56).background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
                .onChange(of: entry) { _, v in entry = String(v.uppercased().prefix(6)) }
            Button { bridge.join(entry) } label: {
                Text(bridge.phase == .connecting ? "Connexion…" : (entry.count == 6 ? "Regarder" : "Code à 6 lettres")).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(entry.count == 6 ? .black : .white.opacity(0.4)).frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 13).fill(entry.count == 6 ? accent : .white.opacity(0.08)))
            }.buttonStyle(.plain).disabled(entry.count != 6 || bridge.phase == .connecting)
            if bridge.phase == .error { Text("Session introuvable").font(.system(size: 10)).foregroundColor(.red) }
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
