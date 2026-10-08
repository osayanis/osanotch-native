import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OsaDropView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void

    enum Mode { case choose, send, receive }
    @State private var mode: Mode = .choose
    @State private var code: String = ""
    @State private var fileName: String?
    @State private var entry: String = ""
    @State private var dropActive = false
    @StateObject private var bridge = DropBridge()

    var mascotMood: Mood {
        switch bridge.phase {
        case .transferring, .done: return .happy
        default: return dropActive ? .happy : .idle
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if bridge.lastReceivedURL != nil {
                receivedView
            } else {
                switch mode {
                case .choose:  chooseView
                case .send:    sendView
                case .receive: receiveView
                }
            }
            Spacer(minLength: 0)
        }
        .background(HiddenWeb(webView: bridge.webView).frame(width: 1, height: 1).opacity(0.02))
        .onAppear { applyHeight() }
        .onChange(of: mode) { _, _ in applyHeight() }
        .onChange(of: bridge.lastReceivedURL) { _, _ in applyHeight() }
    }

    func heightFor() -> CGFloat {
        if bridge.lastReceivedURL != nil { return 214 }
        switch mode { case .choose: return 176; case .send: return 300; case .receive: return 244 }
    }
    func applyHeight() { withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) { model.viewHeight = heightFor() } }

    var receivedView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(.green.opacity(0.15)).frame(width: 60, height: 60)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 42)).foregroundColor(.green)
            }.padding(.top, 2)
            Text("Fichier reçu").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            Text(bridge.lastReceivedURL?.lastPathComponent ?? "").font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).lineLimit(1).padding(.horizontal, 20)
            HStack(spacing: 10) {
                actionBtn("Ouvrir", "folder.fill") { if let u = bridge.lastReceivedURL { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
                actionBtn("Nouveau", "arrow.down.circle.fill") { bridge.reset(); mode = .receive }
            }.padding(.top, 2)
        }.padding(.horizontal, 22).padding(.top, 4)
    }

    func actionBtn(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 12)); Text(title).font(.system(size: 12, weight: .semibold)) }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        }.buttonStyle(.plain)
    }

    var header: some View {
        HStack(spacing: 9) {
            Button {
                switch mode {
                case .choose: back()
                case .send, .receive: bridge.reset(); mode = .choose
                }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                    .padding(8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if mode != .choose { OsaCharacter(model: model, mood: mascotMood, accent: accent, size: 26) }
            VStack(alignment: .leading, spacing: 0) {
                Text("OsaDrop").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text("Transfert P2P").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
    }

    // Envoyer (gauche) — mascotte (centre) — Recevoir (droite)
    var chooseView: some View {
        HStack(spacing: 14) {
            optionCard("Envoyer", "Partager", "arrow.up") { code = Self.gen(); mode = .send }
            OsaCharacter(model: model, mood: dropActive ? .happy : .idle, accent: accent, size: 64)
            optionCard("Recevoir", "Par code", "arrow.down") { mode = .receive }
        }.padding(.horizontal, 18).padding(.top, 10)
    }

    func optionCard(_ title: String, _ sub: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [accent.lighter(0.16), accent], startPoint: .top, endPoint: .bottom)).frame(width: 48, height: 48)
                        .shadow(color: accent.opacity(0.55), radius: 9, y: 3)
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

    var sendView: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(dropActive ? accent.opacity(0.14) : Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7])).foregroundColor(dropActive ? accent : .white.opacity(0.18)))
                VStack(spacing: 8) {
                    Image(systemName: fileName == nil ? "arrow.up.doc" : "doc.fill").font(.system(size: 24)).foregroundColor(fileName == nil ? .white.opacity(0.5) : accent)
                    Text(fileName ?? "Glisse ton fichier ici").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.85)).lineLimit(1).padding(.horizontal, 12)
                }
            }
            .frame(height: 98)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropActive) { providers in
                providers.first?.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { fileName = url.lastPathComponent; bridge.send(fileURL: url, code: code) }
                }
                return true
            }
            if fileName != nil {
                VStack(spacing: 5) {
                    Text("CODE À PARTAGER").font(.system(size: 8.5, weight: .semibold)).foregroundColor(.white.opacity(0.35)).tracking(1.5)
                    Text(code).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundColor(accent).tracking(6)
                    statusRow
                }
            }
        }.padding(.horizontal, 22).padding(.top, 2)
    }

    var receiveView: some View {
        VStack(spacing: 14) {
            Text("Entre le code reçu").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            TextField("", text: $entry)
                .textFieldStyle(.plain).font(.system(size: 28, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).foregroundColor(.white).tracking(6)
                .frame(height: 56).background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
                .onChange(of: entry) { _, v in entry = String(v.uppercased().prefix(6)) }
            Button { bridge.receive(code: entry) } label: {
                Text(entry.count == 6 ? "Se connecter" : "Code à 6 lettres").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(entry.count == 6 ? .black : .white.opacity(0.4)).frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 13).fill(entry.count == 6 ? accent : .white.opacity(0.08)))
            }.buttonStyle(.plain).disabled(entry.count != 6)
            statusRow
        }.padding(.horizontal, 26).padding(.top, 2)
    }

    @ViewBuilder var statusRow: some View {
        switch bridge.phase {
        case .idle, .loading: EmptyView()
        case .waiting: label("En attente du correspondant…", accent)
        case .connecting: label("Connexion…", accent)
        case .connected: label("Connecté", accent)
        case .transferring(let p): VStack(spacing: 4) { label("Transfert \(Int(p*100))%", accent); ProgressView(value: p).frame(width: 150).tint(accent) }
        case .done(let m): label(m, .green)
        case .failed: label("Échec — réessaie", .red)
        }
    }
    func label(_ t: String, _ c: Color) -> some View { Text(t).font(.system(size: 10.5, weight: .medium)).foregroundColor(c) }

    func bigButton(_ title: String, _ icon: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack { Circle().fill(accent).frame(width: 36, height: 36); Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundColor(.white) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    Text(sub).font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                }
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.3))
            }.padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 15).fill(.white.opacity(0.055)))
        }.buttonStyle(.plain)
    }

    static func gen() -> String { String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! }) }
}
