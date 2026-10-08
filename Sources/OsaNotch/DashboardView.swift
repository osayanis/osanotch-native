import SwiftUI
import AVFoundation

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void

    var playing: Bool { model.data.music?.playing ?? false }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 16) {
                // Colonne de gauche (Caméra)
                CameraMirrorView(accent: accent)
                    .frame(width: 160, height: 172)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 1))

                // Colonne de droite (Calendrier + Musique)
                VStack(spacing: 12) {
                    calendarCard
                    musicCard
                }
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)

            // Raccourcis services
            HStack(spacing: 12) {
                serviceButton("OsaDrop", "paperplane.fill", model.data.services.drop) { model.view = .drop }
                serviceButton("OsaCast", "play.rectangle.fill", model.data.services.cast) { model.view = .cast }
                serviceButton("OsaParty", "music.note.list", model.data.services.party) { model.view = .party }
            }.padding(.horizontal, 20).padding(.bottom, 18)

            Spacer(minLength: 0)
        }
    }

    var calendarCard: some View {
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
    }

    var musicCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06))
            VStack(spacing: 9) {
                HStack(spacing: 12) {
                    if let art = model.data.artwork {
                        Image(nsImage: art).resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)).frame(width: 44, height: 44)
                            .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.3)))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.data.music?.title ?? "Aucune lecture").font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Text(model.data.music?.artist ?? "Music / Spotify").font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                    }
                    Spacer()
                    if playing {
                        Button { SystemData.controlMusic("playpause") } label: {
                            ZStack {
                                Circle().fill(.white).frame(width: 30, height: 30)
                                Image(systemName: "pause.fill").font(.system(size: 12)).foregroundColor(.black)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if playing {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let dur = model.data.music?.duration ?? 0
                        let pos = livePos(ctx.date)
                        let prog = dur > 0 ? min(1, pos / dur) : 0
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.14))
                                Capsule().fill(accent).frame(width: max(0, g.size.width * prog))
                            }
                        }.frame(height: 3)
                    }
                }
            }.padding(12)
        }.frame(height: 86)
    }

    func livePos(_ now: Date) -> Double {
        guard let m = model.data.music else { return 0 }
        var p = m.position
        if m.playing { p += now.timeIntervalSince(model.data.positionSampledAt) }
        return m.duration > 0 ? min(p, m.duration) : p
    }

    func serviceButton(_ label: String, _ icon: String, _ online: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(accent)
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Circle().fill(online ? .green : Color.white.opacity(0.2)).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        }.buttonStyle(.plain)
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
