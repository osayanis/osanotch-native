import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OsaDropView: View {
    var accent: Color
    var back: () -> Void

    enum Mode { case choose, send, receive }
    @State private var mode: Mode = .choose
    @State private var code: String = ""
    @State private var fileName: String?
    @State private var fileURL: URL?
    @State private var entry: String = ""
    @State private var dropActive = false
    @StateObject private var mpc = MPCManager()

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
            Button { mpc.reset(); if mode == .choose { back() } else { mode = .choose } } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.75))
                    .padding(7).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Image(systemName: "paperplane.fill").font(.system(size: 12)).foregroundColor(accent)
            Text("OsaDrop").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            Spacer()
            Text("local").font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
        }.padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 6)
    }

    var chooseView: some View {
        VStack(spacing: 10) {
            Text("Transfert P2P, même réseau, zéro serveur").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
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
            .frame(height: 104)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropActive) { providers in
                providers.first?.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { fileURL = url; fileName = url.lastPathComponent; mpc.send(file: url, code: code) }
                }
                return true
            }
            if fileName != nil {
                VStack(spacing: 3) {
                    Text("Code à partager").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.4))
                    Text(code).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(4)
                    statusText
                }
            }
        }.padding(.horizontal, 22).padding(.top, 6)
    }

    var receiveView: some View {
        VStack(spacing: 12) {
            Text("Entre le code reçu").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            TextField("", text: $entry)
                .textFieldStyle(.plain).font(.system(size: 24, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).foregroundColor(.white).tracking(4)
                .frame(height: 50).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                .onChange(of: entry) { _, v in entry = String(v.uppercased().prefix(6)) }
            Button { mpc.receive(code: entry) } label: {
                Text(entry.count == 6 ? "Se connecter" : "6 lettres").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(entry.count == 6 ? .black : .white.opacity(0.4)).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(entry.count == 6 ? Color.white : .white.opacity(0.08)))
            }.buttonStyle(.plain).disabled(entry.count != 6)
            statusText
        }.padding(.horizontal, 28).padding(.top, 8)
    }

    @ViewBuilder var statusText: some View {
        switch mpc.phase {
        case .idle: EmptyView()
        case .waiting: Text("En attente du correspondant…").font(.system(size: 10.5)).foregroundColor(accent)
        case .connecting: Text("Connexion…").font(.system(size: 10.5)).foregroundColor(accent)
        case .transferring(let p): VStack(spacing: 3) {
            Text("Transfert \(Int(p*100))%").font(.system(size: 10.5)).foregroundColor(accent)
            ProgressView(value: p).frame(width: 160).tint(accent)
        }
        case .done(let msg): Text(msg).font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
        case .failed: Text("Échec — réessaie").font(.system(size: 10.5)).foregroundColor(.red)
        }
    }

    func bigButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(accent)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
            }.padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
        }.buttonStyle(.plain)
    }

    static func gen() -> String { String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! }) }
}
