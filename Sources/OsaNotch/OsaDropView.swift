import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OsaDropView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void

    @State private var code: String = ""
    @State private var entry: String = ""
    @State private var dropActive = false
    @StateObject private var bridge = DropBridge()

    static func gen() -> String { String((0..<4).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! }) }

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(model: model, accent: accent, dropHover: dropActive, battery: model.data.battery, lowBat: (model.data.battery?.percent ?? 100) < 20)

            if bridge.lastReceivedURL != nil {
                receivedView
            } else {
                HStack(spacing: 12) {
                    airdropBox
                    clipboardBox
                    osadropBox
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
        }
        .background(HiddenWeb(webView: bridge.webView).frame(width: 1, height: 1).opacity(0.02))
    }

    // ── Boîte AirDrop ──
    var airdropBox: some View {
        Button {
            if let url = model.droppedURL {
                let svc = NSSharingService(named: .sendViaAirDrop) ?? NSSharingService(named: NSSharingService.Name("com.apple.share.AirDrop.send"))
                svc?.perform(withItems: [url])
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.1)).frame(width: 48, height: 48)
                    Image(systemName: "wifi").font(.system(size: 20)).foregroundColor(.white)
                }
                Text("AirDrop").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            }
            .frame(width: 100, height: 140)
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundColor(.white.opacity(0.2)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // ── Boîte Presse-papier (Clipboard) ──
    var clipboardBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundColor(dropActive ? accent : .white.opacity(0.2))
                .background(dropActive ? accent.opacity(0.1) : Color.clear)
                .cornerRadius(16)
            
            if let url = model.droppedURL {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)).frame(width: 56, height: 64)
                        Image(systemName: "doc.fill").font(.system(size: 28)).foregroundColor(.white)
                        // Badge pour supprimer
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    model.droppedURL = nil
                                    code = ""
                                    bridge.reset()
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.red)
                                        .background(Circle().fill(.white))
                                }.buttonStyle(.plain).offset(x: 8, y: -8)
                            }
                            Spacer()
                        }
                    }.frame(width: 56, height: 64)
                    
                    Text(url.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).foregroundColor(.white.opacity(0.3))
                    Text("Glisse un fichier ici").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 140)
        .onDrag {
            if let url = model.droppedURL {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropActive) { providers in
            providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async { model.droppedURL = url }
                }
            }
            return true
        }
    }

    // ── Boîte OsaDrop ──
    var osadropBox: some View {
        Button {
            if let url = model.droppedURL, code.isEmpty {
                code = Self.gen()
                bridge.send(fileURL: url, code: code)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(accent.opacity(0.5))
                
                if model.droppedURL != nil {
                    // Mode Envoi
                    VStack(spacing: 10) {
                        Text("OSADROP").font(.system(size: 10, weight: .bold)).foregroundColor(accent).tracking(1.5)
                        if code.isEmpty {
                            Image(systemName: "paperplane.fill").font(.system(size: 24)).foregroundColor(.white)
                            Text("Générer").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                        } else {
                            Text(code).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(4)
                            
                            if case .transferring(let p) = bridge.phase {
                                Text("Envoi...").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                ProgressView(value: p).progressViewStyle(.linear).tint(accent).frame(width: 80).padding(.top, 4)
                            } else {
                                Text("En attente").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                } else {
                    // Mode Réception
                    VStack(spacing: 12) {
                        Text("OSADROP").font(.system(size: 10, weight: .bold)).foregroundColor(accent).tracking(1.5)
                        
                        if case .transferring(let p) = bridge.phase {
                            ProgressView(value: p).progressViewStyle(.linear).tint(accent).frame(width: 80)
                            Text("Réception...").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                        } else {
                            TextField("CODE", text: $entry)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .frame(width: 90, height: 32)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)))
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .onChange(of: entry) { _, new in
                                    entry = new.uppercased().filter { $0.isLetter || $0.isNumber }
                                    if entry.count > 4 { entry = String(entry.prefix(4)) }
                                    if entry.count == 4 {
                                        bridge.receive(code: entry)
                                    }
                                }
                            Text("Entrer le code").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
            .frame(width: 130, height: 140)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var receivedView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.green.opacity(0.2)).frame(width: 64, height: 64)
                Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundColor(.green)
            }
            Text("Fichier reçu avec succès").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            if let u = bridge.lastReceivedURL { Text(u.lastPathComponent).font(.system(size: 12)).foregroundColor(.white.opacity(0.6)) }
            HStack(spacing: 16) {
                Button { bridge.reset(); entry = "" } label: {
                    Text("Fermer").font(.system(size: 13, weight: .semibold)).foregroundColor(.white).frame(width: 100, height: 36)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.1)))
                }.buttonStyle(.plain)
                Button {
                    if let u = bridge.lastReceivedURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                    bridge.reset(); entry = ""
                } label: {
                    Text("Ouvrir").font(.system(size: 13, weight: .semibold)).foregroundColor(.black).frame(width: 100, height: 36)
                        .background(RoundedRectangle(cornerRadius: 18).fill(accent))
                }.buttonStyle(.plain)
            }.padding(.top, 8)
        }.padding(.top, 20).frame(height: 200)
    }
}
