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
    @State private var sendingURL: URL?
    @ObservedObject var bridge: DropBridge

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
        .onAppear { shelf.prune() }
        .onChange(of: shelf.items) { _, _ in syncSend() }
        .onChange(of: shelf.selected) { _, _ in syncSend() }
        // Un fichier reçu via OsaDrop atterrit aussi dans le presse-papier.
        .onChange(of: bridge.lastReceivedURL) { _, u in if let u { shelf.add([u]) } }
    }

    var shelf: FileShelf { model.shelf }

    // Fichier qu'OsaDrop enverra : uniquement une sélection explicite
    // (sans sélection, la boîte reste en mode réception).
    var sendURL: URL? { sendingURL ?? shelf.selected }
    var sendMode: Bool { !code.isEmpty || shelf.selected != nil }

    // ── Boîte AirDrop ──
    var airdropBox: some View {
        Button { FileShelf.airdrop(shelf.shareSet) } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(.white.opacity(0.1)).frame(width: 48, height: 48)
                    Image(systemName: "wifi").font(.system(size: 20)).foregroundColor(.white)
                }
                VStack(spacing: 2) {
                    Text("AirDrop").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    if !shelf.items.isEmpty {
                        Text(shelf.selected != nil ? "Sélection" : (shelf.items.count == 1 ? "1 fichier" : "Tout (\(shelf.items.count))"))
                            .font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45))
                    }
                }
            }
            .frame(width: 100, height: 140)
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundColor(.white.opacity(0.2)))
            .contentShape(Rectangle())
            .opacity(shelf.items.isEmpty ? 0.55 : 1)
        }.buttonStyle(.plain).disabled(shelf.items.isEmpty)
    }

    // ── Boîte Presse-papier de fichiers ──
    var clipboardBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundColor(dropActive ? .white.opacity(0.45) : .white.opacity(0.2))
                .background(RoundedRectangle(cornerRadius: 16).fill(dropActive ? Color.white.opacity(0.08) : Color.clear))

            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).foregroundColor(.white.opacity(0.3))
                    Text("Glisse des fichiers ici").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                    Text("Ils t'attendent jusqu'à ce que tu les re-glisses")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                        .multilineTextAlignment(.center).padding(.horizontal, 12)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(shelf.items.count == 1 ? "1 FICHIER" : "\(shelf.items.count) FICHIERS")
                            .font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.5)).tracking(1.2)
                        Spacer()
                        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { shelf.clear() } } label: {
                            Text("Vider").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.45))
                        }.buttonStyle(.plain).help("Vider le presse-papier")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(shelf.items, id: \.self) { url in
                                ShelfItemView(url: url, shelf: shelf)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.top, 5).padding(.horizontal, 3)   // place pour la pastille ×
                    }
                    Spacer(minLength: 0)
                    Text(shelf.dragging != nil ? "Lâche-le où tu veux ↗" : "Glisse pour déposer · double-clic pour ouvrir")
                        .font(.system(size: 8.5, weight: shelf.dragging != nil ? .semibold : .regular))
                        .foregroundColor(.white.opacity(shelf.dragging != nil ? 0.7 : 0.28)).lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: shelf.dragging)
                }
                .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 140)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: shelf.items)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropActive) { providers in
            for p in providers where p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { shelf.add([url]) } }
                }
            }
            return true
        }
    }

    // ── Boîte OsaDrop ──
    var osadropBox: some View {
        Button {
            if code.isEmpty, let url = shelf.selected {
                code = Self.gen()
                sendingURL = url
                bridge.send(fileURL: url, code: code)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(.white.opacity(0.2))

                if sendMode {
                    // Mode Envoi (fichier sélectionné dans le presse-papier)
                    VStack(spacing: 8) {
                        Text("OSADROP").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6)).tracking(1.5)
                        if code.isEmpty {
                            Image(systemName: "paperplane.fill").font(.system(size: 22)).foregroundColor(.white)
                            Text("Générer").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                        } else {
                            Text(code).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(4)
                            switch bridge.phase {
                            case .transferring(let p):
                                ProgressView(value: p).progressViewStyle(.linear).tint(.white).frame(width: 80)
                            case .done(let msg):
                                Text(msg).font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                            case .failed:
                                Text("Échec").font(.system(size: 11)).foregroundColor(.red)
                            default:
                                Text("En attente").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                            }
                        }
                        if let u = sendURL {
                            Text(u.lastPathComponent).font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                                .lineLimit(1).truncationMode(.middle).padding(.horizontal, 10)
                        }
                    }
                } else {
                    // Mode Réception
                    VStack(spacing: 12) {
                        Text("OSADROP").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6)).tracking(1.5)

                        if case .transferring(let p) = bridge.phase {
                            ProgressView(value: p).progressViewStyle(.linear).tint(.white).frame(width: 80)
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
                            Text(shelf.items.isEmpty ? "Entrer le code" : "Code, ou choisis un fichier")
                                .font(.system(size: 9.5)).foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
            .frame(width: 130, height: 140)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // Réinitialise l'envoi OsaDrop si son fichier a quitté le presse-papier,
    // ou si on choisit un autre fichier alors que le transfert n'a pas commencé.
    func syncSend() {
        guard !code.isEmpty, let s = sendingURL else { return }
        let gone = !shelf.items.contains(s)
        var idle = true
        if case .transferring = bridge.phase { idle = false }
        if gone || (idle && shelf.selected != s) {
            code = ""; sendingURL = nil; bridge.reset()
        }
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
                        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                }.buttonStyle(.plain)
            }.padding(.top, 8)
        }.padding(.top, 20).frame(height: 200)
    }
}

// Vignette d'un fichier du presse-papier : aperçu Quick Look, nom, sélection au clic,
// double-clic pour ouvrir, glisser pour déposer ailleurs, clic droit pour les actions.
struct ShelfItemView: View {
    let url: URL
    @ObservedObject var shelf: FileShelf
    @State private var img: NSImage?
    @State private var hover = false

    var isSel: Bool { shelf.selected == url }
    var lifted: Bool { shelf.dragging == url }   // en cours de glisser → emplacement fantôme

    var thumb: some View {
        Group {
            if let img { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit) }
            else { Image(systemName: "doc.fill").font(.system(size: 20)).foregroundColor(.white.opacity(0.6)) }
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                thumb
                    .frame(width: 40, height: 44)
                    .padding(4)
                    // Fantôme : la vignette se « détache », il ne reste qu'une trace pâle.
                    .opacity(lifted ? 0.22 : 1)
                    .scaleEffect(lifted ? 0.8 : 1)
                    .saturation(lifted ? 0 : 1)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(lifted ? 0.02 : (isSel ? 0.16 : (hover ? 0.09 : 0.05)))))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(isSel && !lifted ? 0.85 : 0), lineWidth: 1.2))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        .foregroundColor(.white.opacity(lifted ? 0.4 : 0)))

                if hover && !lifted {
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { shelf.remove(url) } } label: {
                        Image(systemName: "xmark").font(.system(size: 6.5, weight: .bold)).foregroundColor(.white)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(Color.black.opacity(0.8)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain).offset(x: 4, y: -4).transition(.opacity)
                }
            }
            Text(url.lastPathComponent)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.white.opacity(lifted ? 0.25 : (isSel ? 1 : 0.65)))
                .lineLimit(1).truncationMode(.middle)
                .frame(width: 52)
        }
        // petit « pop » au survol, comme si on pouvait l'attraper
        .scaleEffect(hover && !lifted ? 1.06 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { shelf.toggleSelect(url) } }
        .onDrag {
            shelf.beginDrag(url)
            return shelf.dragProvider(for: url)
        } preview: {
            DragCard(thumb: AnyView(thumb), name: url.lastPathComponent)
        }
        .contextMenu {
            Button("Ouvrir") { NSWorkspace.shared.open(url) }
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copier") { FileShelf.copyToPasteboard([url]) }
            Button("AirDrop") { FileShelf.airdrop([url]) }
            Divider()
            Button("Retirer du presse-papier") { shelf.remove(url) }
        }
        .help(url.lastPathComponent)
        .onAppear { shelf.thumbnail(for: url, size: CGSize(width: 96, height: 96)) { img = $0 } }
    }
}

// Aperçu qui suit le curseur pendant le glisser : carte inclinée avec ombre.
struct DragCard: View {
    let thumb: AnyView
    let name: String
    var body: some View {
        VStack(spacing: 6) {
            thumb.frame(width: 64, height: 70)
            Text(name)
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 96)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .rotationEffect(.degrees(-5))
        .padding(12)   // marge pour que la rotation ne soit pas rognée
    }
}
