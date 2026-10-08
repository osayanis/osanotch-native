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
    @State private var entry: String = ""
    @State private var dropActive = false
    @ObservedObject var bridge: DropBridge

    static func gen() -> String { String((0..<4).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! }) }

    var transferring: Bool { if case .transferring = bridge.phase { return true }; return false }
    var progress: Double { if case .transferring(let p) = bridge.phase { return p }; return 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if bridge.lastReceivedURL != nil { receivedView }
                else {
                    switch mode {
                    case .choose:  chooseView
                    case .send:    sendView
                    case .receive: receiveView
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .background(HiddenWeb(webView: bridge.webView).frame(width: 1, height: 1).opacity(0.02))
        .onAppear { if model.droppedURL != nil { mode = .send }; applyHeight() }
        .onChange(of: mode) { _, _ in applyHeight() }
        .onChange(of: model.droppedURL) { _, v in if v != nil { mode = .send }; applyHeight() }
        .onChange(of: bridge.phase) { _, _ in applyHeight() }
        .onChange(of: bridge.lastReceivedURL) { _, _ in applyHeight() }
    }

    func applyHeight() {
        let h: CGFloat
        if bridge.lastReceivedURL != nil { h = 224 }
        else {
            switch mode {
            case .choose:  h = 188
            case .send:    h = model.droppedURL == nil ? 236 : (code.isEmpty ? 262 : 300)
            case .receive: h = transferring ? 236 : 244
            }
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { model.viewHeight = h }
    }

    // ── En-tête ──
    var header: some View {
        HStack(spacing: 9) {
            Button {
                if mode == .choose { back() } else { mode = .choose; code = ""; entry = ""; bridge.reset() }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.8)).padding(8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if mode != .choose { OsaCharacter(model: model, mood: model.droppedURL != nil ? .happy : .idle, accent: accent, size: 26) }
            VStack(alignment: .leading, spacing: 0) {
                Text("OsaDrop").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text(mode == .send ? "Envoyer un fichier" : (mode == .receive ? "Recevoir un fichier" : "Transfert de fichiers")).font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
    }

    // ── Choix : Envoyer / Recevoir ──
    var chooseView: some View {
        HStack(spacing: 14) {
            optionCard("Envoyer", "Partager un fichier", "paperplane.fill") { mode = .send }
            OsaCharacter(model: model, mood: .idle, accent: accent, size: 64)
            optionCard("Recevoir", "Entrer un code", "tray.and.arrow.down.fill") { mode = .receive }
        }.padding(.horizontal, 18).padding(.top, 6)
    }

    // ── Envoi ──
    var sendView: some View {
        VStack(spacing: 12) {
            fileDropCard
            if model.droppedURL != nil {
                if code.isEmpty {
                    HStack(spacing: 10) {
                        primaryButton("Générer un code", "number") {
                            if let url = model.droppedURL { code = Self.gen(); bridge.send(fileURL: url, code: code) }
                        }
                        iconButton("airplayaudio", "AirDrop") {
                            if let url = model.droppedURL {
                                let svc = NSSharingService(named: .sendViaAirDrop) ?? NSSharingService(named: NSSharingService.Name("com.apple.share.AirDrop.send"))
                                svc?.perform(withItems: [url])
                            }
                        }
                    }
                } else {
                    codeCard
                }
            }
        }.padding(.horizontal, 20).padding(.top, 2)
    }

    // Carte fichier : zone de dépôt propre (sans pointillés) ou fichier présent.
    var fileDropCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(dropActive ? accent.opacity(0.14) : .white.opacity(0.05))
            RoundedRectangle(cornerRadius: 16).strokeBorder(dropActive ? accent : .white.opacity(0.08), lineWidth: 1)
            if let url = model.droppedURL {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.18)).frame(width: 46, height: 46)
                        Image(systemName: "doc.fill").font(.system(size: 20)).foregroundColor(accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                        Text("Prêt à envoyer · glisse-le où tu veux").font(.system(size: 10)).foregroundColor(.white.opacity(0.4)).lineLimit(1)
                    }
                    Spacer()
                    Button { model.droppedURL = nil; code = ""; bridge.reset() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.8))
                            .frame(width: 20, height: 20).background(Circle().fill(.white.opacity(0.1)))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 14)
                .onDrag { makeDragProvider() }
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22)).foregroundColor(.white.opacity(0.35))
                    Text("Glisse un fichier ici").font(.system(size: 11.5, weight: .medium)).foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(height: 92)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropActive) { providers in
            providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { DispatchQueue.main.async { model.droppedURL = url } }
            }
            return true
        }
    }

    // Carte code (après génération) : code + statut d'envoi.
    var codeCard: some View {
        VStack(spacing: 10) {
            Text("CODE À PARTAGER").font(.system(size: 9.5, weight: .bold)).foregroundColor(accent).tracking(2)
            Text(code).font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(8)
            if transferring {
                ProgressView(value: progress).progressViewStyle(.linear).tint(accent).frame(width: 150)
                Text("Envoi \(Int(progress * 100)) %").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.55))
            } else {
                Text("En attente du destinataire…").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(accent.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.4), lineWidth: 1))
    }

    // ── Réception ──
    var receiveView: some View {
        VStack(spacing: 14) {
            if transferring {
                ProgressView(value: progress).progressViewStyle(.linear).tint(accent).frame(width: 180)
                Text("Réception \(Int(progress * 100)) %").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            } else {
                Text("Entre le code à 4 caractères").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                TextField("", text: $entry)
                    .textFieldStyle(.plain).font(.system(size: 28, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center).foregroundColor(.white).tracking(6)
                    .frame(height: 56).background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
                    .onChange(of: entry) { _, v in entry = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(4)) }
                Button { if entry.count == 4 { bridge.receive(code: entry) } } label: {
                    Text(entry.count == 4 ? "Recevoir" : "Code à 4 caractères").font(.system(size: 13, weight: .semibold))
                        .foregroundColor(entry.count == 4 ? .black : .white.opacity(0.4)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 13).fill(entry.count == 4 ? accent : .white.opacity(0.08)))
                }.buttonStyle(.plain).disabled(entry.count != 4)
            }
        }.padding(.horizontal, 26).padding(.top, 2)
    }

    // ── Reçu ──
    var receivedView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(.green.opacity(0.18)).frame(width: 60, height: 60)
                Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundColor(.green)
            }
            Text("Fichier reçu").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            if let u = bridge.lastReceivedURL { Text(u.lastPathComponent).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.55)).lineLimit(1) }
            HStack(spacing: 12) {
                Button { bridge.reset(); entry = ""; mode = .choose } label: {
                    Text("Nouveau").font(.system(size: 13, weight: .semibold)).foregroundColor(.white).frame(width: 108, height: 38)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                }.buttonStyle(.plain)
                Button {
                    if let u = bridge.lastReceivedURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                    bridge.reset(); entry = ""; mode = .choose
                } label: {
                    Text("Ouvrir").font(.system(size: 13, weight: .semibold)).foregroundColor(.black).frame(width: 108, height: 38)
                        .background(RoundedRectangle(cornerRadius: 12).fill(accent))
                }.buttonStyle(.plain)
            }.padding(.top, 2)
        }.padding(.top, 10)
    }

    // ── Composants ──
    func makeDragProvider() -> NSItemProvider {
        guard let url = model.droppedURL else { return NSItemProvider() }
        let provider = NSItemProvider()
        let typeID = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
        provider.suggestedName = url.lastPathComponent
        provider.registerFileRepresentation(forTypeIdentifier: typeID, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            DispatchQueue.main.async { model.droppedURL = nil; code = ""; bridge.reset() }
            return nil
        }
        return provider
    }

    func optionCard(_ title: String, _ sub: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [accent.lighter(0.16), accent], startPoint: .top, endPoint: .bottom)).frame(width: 48, height: 48).shadow(color: accent.opacity(0.55), radius: 9, y: 3)
                    Image(systemName: icon).font(.system(size: 19, weight: .bold)).foregroundColor(.white)
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

    func primaryButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }.foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 13).fill(accent))
        }.buttonStyle(.plain)
    }

    func iconButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(label).font(.system(size: 9))
            }.foregroundColor(.white).frame(width: 64).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.08)))
        }.buttonStyle(.plain)
    }
}
