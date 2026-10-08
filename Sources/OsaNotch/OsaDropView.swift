import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Interface OsaDrop 100% native, pensée pour le notch.
struct OsaDropView: View {
    var accent: Color
    var back: () -> Void

    enum Mode { case choose, send, receive }
    @State private var mode: Mode = .choose
    @State private var code: String = ""
    @State private var fileName: String?
    @State private var entry: String = ""
    @State private var dropActive = false

    var body: some View {
        VStack(spacing: 0) {
            header
            switch mode {
            case .choose:  chooseView
            case .send:    sendView
            case .receive: receiveView
            }
            Spacer(minLength: 0)
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            Button { if mode == .choose { back() } else { mode = .choose } } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
            Image(systemName: "paperplane.fill").font(.system(size: 12)).foregroundColor(accent)
            Text("OsaDrop").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            Spacer()
        }.padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 6)
    }

    var chooseView: some View {
        VStack(spacing: 10) {
            Text("Partage P2P, zéro serveur").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.4))
            bigButton("Envoyer un fichier", "arrow.up.circle.fill") { code = Self.gen(); mode = .send }
            bigButton("Recevoir un fichier", "arrow.down.circle.fill") { mode = .receive }
        }.padding(.horizontal, 22).padding(.top, 10)
    }

    var sendView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(dropActive ? 0.12 : 0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundColor(dropActive ? accent : .white.opacity(0.2)))
                VStack(spacing: 6) {
                    Image(systemName: fileName == nil ? "tray.and.arrow.down" : "doc.fill").font(.system(size: 22)).foregroundColor(fileName == nil ? .white.opacity(0.5) : accent)
                    Text(fileName ?? "Glisse ton fichier ici").font(.system(size: 11.5, weight: .medium)).foregroundColor(.white.opacity(0.8)).lineLimit(1).padding(.horizontal, 10)
                }
            }
            .frame(height: 120)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropActive) { providers in
                providers.first?.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { fileName = url.lastPathComponent } }
                }
                return true
            }
            if fileName != nil {
                VStack(spacing: 3) {
                    Text("Code à partager").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.4))
                    Text(code).font(.system(size: 26, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(4)
                    Text("En attente du destinataire…").font(.system(size: 10)).foregroundColor(accent)
                }
            }
        }.padding(.horizontal, 22).padding(.top, 6)
    }

    var receiveView: some View {
        VStack(spacing: 14) {
            Text("Entre le code reçu").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            TextField("", text: $entry)
                .textFieldStyle(.plain).font(.system(size: 26, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).foregroundColor(.white).tracking(4)
                .frame(height: 54).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                .onChange(of: entry) { _, v in entry = String(v.uppercased().prefix(6)) }
            Button { } label: {
                Text(entry.count == 6 ? "Se connecter" : "6 lettres").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(entry.count == 6 ? .black : .white.opacity(0.4)).frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(entry.count == 6 ? Color.white : .white.opacity(0.08)))
            }.buttonStyle(.plain).disabled(entry.count != 6)
        }.padding(.horizontal, 30).padding(.top, 10)
    }

    func bigButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(accent)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
            }.padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
        }.buttonStyle(.plain)
    }

    static func gen() -> String { String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! }) }
}
