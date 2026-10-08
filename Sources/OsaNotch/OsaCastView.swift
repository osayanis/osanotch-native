import SwiftUI
import AppKit

// Interface OsaCast 100% native, pensée pour le notch.
struct OsaCastView: View {
    var accent: Color
    var back: () -> Void

    enum Mode { case choose, hosting, joining }
    @State private var mode: Mode = .choose
    @State private var code: String = ""
    @State private var entry: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            switch mode {
            case .choose:  chooseView
            case .hosting: hostingView
            case .joining: joiningView
            }
            Spacer(minLength: 0)
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            Button { if mode == .choose { back() } else { mode = .choose } } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
            Image(systemName: "play.rectangle.fill").font(.system(size: 12)).foregroundColor(accent)
            Text("OsaCast").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            Spacer()
        }.padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 6)
    }

    var chooseView: some View {
        VStack(spacing: 10) {
            Text("Partage ton écran en direct").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.4))
            bigButton("Créer une room", "plus.circle.fill") { code = Self.gen(); mode = .hosting }
            bigButton("Rejoindre une room", "arrow.right.circle.fill") { mode = .joining }
        }.padding(.horizontal, 22).padding(.top, 10)
    }

    var hostingView: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.black)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.red.opacity(0.5), lineWidth: 1))
                VStack(spacing: 8) {
                    HStack(spacing: 6) { Circle().fill(.red).frame(width: 8, height: 8); Text("EN DIRECT").font(.system(size: 10, weight: .bold)).foregroundColor(.red).tracking(1) }
                    Text(code).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(5)
                    Text("Ton écran est partagé").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.5))
                }
            }.frame(height: 150)
            Text("Donne ce code à qui veut regarder").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.35))
        }.padding(.horizontal, 22).padding(.top, 6)
    }

    var joiningView: some View {
        VStack(spacing: 14) {
            Text("Entre le code de la room").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            TextField("", text: $entry)
                .textFieldStyle(.plain).font(.system(size: 26, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).foregroundColor(.white).tracking(4)
                .frame(height: 54).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                .onChange(of: entry) { _, v in entry = String(v.uppercased().prefix(6)) }
            Button { } label: {
                Text(entry.count == 6 ? "Regarder" : "6 lettres").font(.system(size: 13, weight: .semibold))
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
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
            }.padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
        }.buttonStyle(.plain)
    }

    static func gen() -> String { String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! }) }
}
