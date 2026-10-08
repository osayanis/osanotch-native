import SwiftUI
import AppKit

struct OsaCastView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void
    @ObservedObject var bridge: CastBridge

    @State private var entry: String = ""

    var hosting: Bool { !bridge.code.isEmpty }
    var live: Bool { bridge.phase == .connected || bridge.phase == .live }
    var watching: Bool { entry.count >= 4 && (bridge.phase == .connected || bridge.phase == .live) && bridge.code.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(model: model, accent: accent, dropHover: false, battery: model.data.battery, lowBat: (model.data.battery?.percent ?? 100) < 20)

            ZStack {
                // Moteur WebRTC : caché (1×1) hors visionnage, plein cadre en direct.
                HiddenWeb(webView: bridge.webView)
                    .frame(maxWidth: watching ? .infinity : 1, maxHeight: watching ? .infinity : 1)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .opacity(watching ? 1 : 0.02)

                if !watching {
                    HStack(spacing: 12) {
                        diffuserBox
                        regarderBox
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
                }
            }
            .padding(watching ? 12 : 0)
            Spacer(minLength: 0)
        }
        .onAppear {
            applyHeight()
            if live { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { bridge.resume() } }
        }
        .onChange(of: watching) { _, _ in applyHeight() }
        .onChange(of: bridge.phase) { _, _ in applyHeight() }
    }

    func applyHeight() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { model.viewHeight = watching ? 360 : 210 }
    }

    // ── Boîte Diffuser (comme la boîte OsaDrop) ──
    var diffuserBox: some View {
        Button { if !hosting { bridge.host() } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(hosting ? accent.opacity(0.5) : .white.opacity(0.2))
                if hosting {
                    VStack(spacing: 10) {
                        Text("OSACAST").font(.system(size: 10, weight: .bold)).foregroundColor(accent).tracking(1.5)
                        Text(bridge.code).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(4)
                        HStack(spacing: 5) {
                            Circle().fill(live ? .red : .white.opacity(0.4)).frame(width: 7, height: 7)
                            Text(live ? "EN DIRECT" : "EN ATTENTE").font(.system(size: 9.5, weight: .bold)).foregroundColor(live ? .red : .white.opacity(0.5)).tracking(1)
                        }
                        if bridge.phase == .error {
                            Text("Capture refusée").font(.system(size: 9.5)).foregroundColor(.red)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(.white.opacity(0.1)).frame(width: 48, height: 48)
                            Image(systemName: "rectangle.on.rectangle").font(.system(size: 19)).foregroundColor(.white)
                        }
                        Text("Diffuser").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        Text("Ton écran").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 150)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // ── Boîte Regarder (comme la réception OsaDrop) ──
    var regarderBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundColor(accent.opacity(0.5))
            if bridge.phase == .connecting {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(accent)
                    Text("Connexion…").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                }
            } else {
                VStack(spacing: 12) {
                    Text("REGARDER").font(.system(size: 10, weight: .bold)).foregroundColor(accent).tracking(1.5)
                    TextField("CODE", text: $entry)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 100, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)))
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .onChange(of: entry) { _, new in
                            entry = String(new.uppercased().prefix(6))
                            if entry.count == 6 { bridge.join(entry) }
                        }
                    Text(bridge.phase == .error ? "Session introuvable" : "Entrer le code")
                        .font(.system(size: 10)).foregroundColor(bridge.phase == .error ? .red : .white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 150)
    }
}
