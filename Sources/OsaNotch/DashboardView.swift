import SwiftUI
import AVFoundation

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 16) {
                // Colonne de gauche (Caméra)
                CameraMirrorView(accent: accent)
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 1))

                // Colonne de droite (Calendrier + Musique)
                VStack(spacing: 12) {
                    // Calendrier
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "calendar").font(.system(size: 12)).foregroundColor(accent)
                                Text("Prochain événement").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                            }
                            if let ev = model.data.event {
                                Text(ev.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                                Text(ev.when).font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                            } else {
                                Text("Rien de prévu").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.5))
                            }
                        }.padding(12)
                    }.frame(height: 74)

                    // Musique
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06))
                        HStack(spacing: 12) {
                            if let art = model.data.artwork {
                                Image(nsImage: art).resizable().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)).frame(width: 48, height: 48)
                                    .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.3)))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.data.music?.title ?? "Aucune lecture").font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
                                Text(model.data.music?.artist ?? "Music / Spotify").font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                            }
                        }.padding(12)
                    }.frame(height: 74)
                }
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
            Spacer(minLength: 0)
        }
    }

    var header: some View {
        TabBarView(model: model, accent: accent, dropHover: false, battery: model.data.battery, lowBat: (model.data.battery?.percent ?? 100) < 20)
    }
}

class CameraController: ObservableObject {
    let session = AVCaptureSession()
    private var isSetup = false

    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.isSetup {
                self.session.beginConfiguration()
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device) {
                    if self.session.canAddInput(input) { self.session.addInput(input) }
                }
                self.session.commitConfiguration()
                self.isSetup = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func stop() {
        let s = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            if s.isRunning { s.stopRunning() }
        }
    }

    deinit { 
        let s = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            if s.isRunning { s.stopRunning() }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    var session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer as? AVCaptureVideoPreviewLayer { layer.session = session }
    }
}

struct CameraMirrorView: View {
    @StateObject private var camera = CameraController()
    @State private var isActive = false
    var accent: Color

    var body: some View {
        ZStack {
            if isActive {
                CameraPreview(session: camera.session)
                    .scaleEffect(x: -1, y: 1) // Effet miroir
                    .onAppear { camera.start() }
                    .onDisappear { camera.stop() }
            } else {
                Button {
                    isActive = true
                } label: {
                    ZStack {
                        Color.white.opacity(0.06)
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill").font(.system(size: 24)).foregroundColor(accent)
                            Text("Activer le miroir").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}

struct ChoiceView: View {
    @ObservedObject var model: AppModel
    var accent: Color

    var body: some View {
        VStack(spacing: 16) {
            Text("Partager le fichier").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            
            HStack(spacing: 16) {
                Button {
                    shareAirDrop(model.droppedURL)
                    model.view = .home
                    model.droppedURL = nil
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi").font(.system(size: 24)).foregroundColor(.white)
                        Text("AirDrop").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    }.frame(width: 120, height: 80)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
                }.buttonStyle(.plain)

                Button {
                    model.view = .drop
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "paperplane.fill").font(.system(size: 24)).foregroundColor(accent)
                        Text("OsaDrop").font(.system(size: 12, weight: .semibold)).foregroundColor(accent)
                    }.frame(width: 120, height: 80)
                    .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.12)))
                }.buttonStyle(.plain)
            }
        }.frame(width: 380, height: 160)
    }

    func shareAirDrop(_ url: URL?) {
        guard let url = url else { return }
        let svc = NSSharingService(named: .sendViaAirDrop) ?? NSSharingService(named: NSSharingService.Name("com.apple.share.AirDrop.send"))
        svc?.perform(withItems: [url])
    }
}

struct NotificationView: View {
    @ObservedObject var model: AppModel
    var accent: Color

    var body: some View {
        HStack(spacing: 16) {
            OsaCharacter(model: model, mood: .happy, accent: accent, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Assistant IA").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text(model.notification ?? "Tâche terminée").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(width: 320, height: 80)
    }
}
