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
                    .frame(width: 168, height: 196)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1), lineWidth: 1))

                // Colonne de droite (Calendrier + Musique)
                VStack(spacing: 12) {
                    calendarCard
                    musicCard
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 18)

            Spacer(minLength: 0)
        }
    }

    // Calendrier façon NotchNook : mois + bande de 5 jours (aujourd'hui surligné) + prochain évènement.
    var calendarCard: some View {
        let cal = Calendar.current
        let today = Date()
        let days = (-2...2).map { cal.date(byAdding: .day, value: $0, to: today)! }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(monthStr(today)).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in dayCell(d, today: today, cal: cal) }
                }
            }
            eventCard
        }
    }

    func dayCell(_ d: Date, today: Date, cal: Calendar) -> some View {
        let isToday = cal.isDate(d, inSameDayAs: today)
        let hasEvent = model.data.eventDays.contains(cal.startOfDay(for: d))
        return VStack(spacing: 3) {
            Text(weekdayLetter(d, isToday: isToday))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isToday ? .white : .white.opacity(0.4))
            Text("\(cal.component(.day, from: d))")
                .font(.system(size: 14, weight: isToday ? .bold : .medium))
                .foregroundColor(isToday ? .black : .white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isToday ? Color.white : .clear))
            Circle().fill(hasEvent ? .white.opacity(0.65) : .clear).frame(width: 3, height: 3)
        }
        .frame(width: 30)
    }

    @ViewBuilder var eventCard: some View {
        HStack(spacing: 10) {
            if let ev = model.data.event {
                Text(ev.title).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Circle().fill(.white.opacity(0.65)).frame(width: 5, height: 5)
                Text("\(timeStr(ev.start)) – \(timeStr(ev.end))").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundColor(.white.opacity(0.7))
            } else {
                Text("Rien de prévu").font(.system(size: 12.5, weight: .medium)).foregroundColor(.white.opacity(0.45))
                Spacer()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }

    func monthStr(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "MMM"
        return f.string(from: d).capitalized
    }
    func weekdayLetter(_ d: Date, isToday: Bool) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR")
        if isToday { f.dateFormat = "EEE"; return f.string(from: d).uppercased() }
        f.dateFormat = "EEEEE"; return f.string(from: d).uppercased()
    }
    func timeStr(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"
        return f.string(from: d)
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
                                Capsule().fill(.white).frame(width: max(0, g.size.width * prog))
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
                            Image(systemName: "camera.fill").font(.system(size: 24)).foregroundColor(.white)
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
