import SwiftUI
import AppKit

struct OsaCastView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void

    enum Mode { case choose, hosting, joining }
    @State private var mode: Mode = .choose
    @State private var code: String = ""
    @State private var entry: String = ""

    var mascotMood: Mood { mode == .hosting ? .happy : .idle }

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
        HStack(spacing: 9) {
            Button { if mode == .choose { back() } else { mode = .choose } } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                    .padding(8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if mode != .choose { OsaCharacter(model: model, mood: mascotMood, accent: accent, size: 26) }
            VStack(alignment: .leading, spacing: 0) {
                Text("OsaCast").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text("Partage d'écran").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
    }

    var chooseView: some View {
        HStack(spacing: 14) {
            optionCard("Créer", "Diffuser", "plus") { code = Self.gen(); mode = .hosting }
            OsaCharacter(model: model, mood: .idle, accent: accent, size: 64)
            optionCard("Rejoindre", "Regarder", "arrow.right") { mode = .joining }
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

    var hostingView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.black).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.red.opacity(0.55), lineWidth: 1.5))
                VStack(spacing: 10) {
                    HStack(spacing: 6) { Circle().fill(.red).frame(width: 8, height: 8); Text("EN DIRECT").font(.system(size: 10, weight: .bold)).foregroundColor(.red).tracking(1.5) }
                    Text(code).font(.system(size: 32, weight: .bold, design: .monospaced)).foregroundColor(.white).tracking(6)
                    Text("Ton écran est partagé").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.5))
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
            Button { } label: {
                Text(entry.count == 6 ? "Regarder" : "Code à 6 lettres").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(entry.count == 6 ? .black : .white.opacity(0.4)).frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 13).fill(entry.count == 6 ? accent : .white.opacity(0.08)))
            }.buttonStyle(.plain).disabled(entry.count != 6)
        }.padding(.horizontal, 26).padding(.top, 2)
    }

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
