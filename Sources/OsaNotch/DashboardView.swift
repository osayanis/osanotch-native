import AppKit

import SwiftUI
import AVFoundation

struct ClipboardWidget: View {
    @ObservedObject var clipboard: ClipboardManager
    @State private var copied: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                    Text("Presse-papier").font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.top, 10)
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        if clipboard.items.isEmpty {
                            Text("Vide").font(.system(size: 11)).foregroundColor(.white.opacity(0.3)).padding(.vertical, 10)
                        } else {
                            ForEach(clipboard.items, id: \.self) { item in
                                Button {
                                    clipboard.copy(item)
                                    copied = item
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if copied == item { copied = nil }
                                    }
                                } label: {
                                    HStack {
                                        Text(item.replacingOccurrences(of: "\n", with: " "))
                                            .font(.system(size: 11))
                                            .foregroundColor(copied == item ? .green : .white.opacity(0.8))
                                            .lineLimit(1)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        if copied == item {
                                            Image(systemName: "checkmark").font(.system(size: 9)).foregroundColor(.green)
                                        }
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(copied == item ? Color.green.opacity(0.1) : .white.opacity(0.05)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var back: () -> Void

    var playing: Bool { model.data.music?.playing ?? false }
    @State private var weekOffset: Int = 0
    @State private var swipeDir: Int = 1
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var scrollMonitor: Any? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 16) {
                // Colonne de gauche (Caméra + Presse-papier)
                VStack(spacing: 12) {
                    CameraMirrorView(accent: accent)
                        .frame(height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                    
                    ClipboardWidget(clipboard: model.clipboard)
                }
                .frame(width: 170)

                // Colonne de droite (Calendrier + Musique)
                VStack(spacing: 12) {
                    calendarCard
                    musicCard
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)

            Spacer(minLength: 0)
        }
    }

    var calendarCard: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<5).map { cal.date(byAdding: .day, value: $0 - 2 + (weekOffset * 5), to: today)! }
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(monthStr(selectedDate))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                Button { 
                    swipeDir = -1
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { weekOffset -= 1 }
                } label: { Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.5)).frame(width: 20, height: 20).contentShape(Rectangle()) }.buttonStyle(.plain)
                
                ZStack {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { d in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedDate = d
                                }
                            } label: {
                                dayCell(d, today: today, cal: cal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .id(weekOffset)
                    .transition(.push(from: swipeDir == 1 ? .trailing : .leading))
                }
                .frame(width: 150, height: 44)
                .clipped()
                .onAppear {
                    if scrollMonitor == nil {
                        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
                            if abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) + 2 {
                                if e.phase == .began || e.momentumPhase == .began {
                                    let dir = e.scrollingDeltaX > 0 ? -1 : 1
                                    swipeDir = dir
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                        weekOffset += dir
                                    }
                                }
                            }
                            return e
                        }
                    }
                }
                .onDisappear {
                    if let m = scrollMonitor {
                        NSEvent.removeMonitor(m)
                        scrollMonitor = nil
                    }
                }
                
                Button { 
                    swipeDir = 1
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { weekOffset += 1 }
                } label: { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.5)).frame(width: 20, height: 20).contentShape(Rectangle()) }.buttonStyle(.plain)
            }
            eventCard
        }
    }

    func dayCell(_ d: Date, today: Date, cal: Calendar) -> some View {
        let isToday = cal.isDate(d, inSameDayAs: today)
        let isSelected = cal.isDate(d, inSameDayAs: selectedDate)
        let hasEvent = model.data.events.contains(where: { cal.isDate($0.start, inSameDayAs: d) })
        return VStack(spacing: 3) {
            Text(weekdayLetter(d, isToday: isToday))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
            Text("\(cal.component(.day, from: d))")
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isSelected ? Color.white : .clear))
            Circle().fill(hasEvent ? .white.opacity(0.65) : .clear).frame(width: 3, height: 3)
        }
        .frame(width: 30)
        .contentShape(Rectangle())
    }

    @ViewBuilder var eventCard: some View {
        let cal = Calendar.current
        let todaysEvents = model.data.events.filter { cal.isDate($0.start, inSameDayAs: selectedDate) }
        let nextEvent = todaysEvents.first(where: { $0.start >= Date() }) ?? todaysEvents.first
        
        HStack(spacing: 10) {
            if let ev = nextEvent {
                Text(ev.title).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white)
                    .lineLimit(1).multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Circle().fill(.white.opacity(0.65)).frame(width: 5, height: 5)
                Text("\(timeStr(ev.start))").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundColor(.white.opacity(0.7))
            } else {
                Text("Rien de prévu").font(.system(size: 12.5, weight: .medium)).foregroundColor(.white.opacity(0.45))
                Spacer()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            
            // Flou en arrière plan si artwork
            if let art = model.data.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .blur(radius: 20)
                    .opacity(0.4)
            }
            
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    if let art = model.data.artwork {
                        Image(nsImage: art).resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)).frame(width: 44, height: 44)
                            .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.3)))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.data.music?.title ?? "Aucune lecture").font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Text(model.data.music?.artist ?? "Apple Music / Spotify").font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer()
                    
                    // Toujours afficher les contrôles, même en pause !
                    HStack(spacing: 8) {
                        Button { SystemData.controlMusic("previous track") } label: {
                            Image(systemName: "backward.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                        }.buttonStyle(.plain)
                        
                        Button { SystemData.controlMusic("playpause") } label: {
                            ZStack {
                                Circle().fill(.white).frame(width: 32, height: 32)
                                Image(systemName: playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundColor(.black)
                                    .offset(x: playing ? 0 : 1.5)
                            }
                        }.buttonStyle(.plain)
                        
                        Button { SystemData.controlMusic("next track") } label: {
                            Image(systemName: "forward.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                        }.buttonStyle(.plain)
                    }
                }
                
                // Barre de progression
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let dur = model.data.music?.duration ?? 0
                    let pos = livePos(ctx.date)
                    let prog = dur > 0 ? min(1, pos / dur) : 0
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.2))
                            Capsule().fill(.white).frame(width: max(0, g.size.width * prog))
                        }
                    }.frame(height: 4)
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
                        Color.white.opacity(0.04)
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill").font(.system(size: 20)).foregroundColor(.white.opacity(0.8))
                            Text("Activer").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.5))
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


struct ScrollDetector: NSViewRepresentable {
    var onSwipe: (Int) -> Void
    
    func makeNSView(context: Context) -> ScrollTrackingView {
        let view = ScrollTrackingView()
        view.onSwipe = onSwipe
        return view
    }
    
    func updateNSView(_ nsView: ScrollTrackingView, context: Context) {
        nsView.onSwipe = onSwipe
    }
}

class ScrollTrackingView: NSView {
    var onSwipe: ((Int) -> Void)?
    var accumX: CGFloat = 0
    
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin { accumX = 0 }
        
        // scrollingDeltaX is positive when scrolling left (swiping right)
        accumX += event.scrollingDeltaX
        
        if accumX > 60 {
            onSwipe?(-1)
            accumX = 0
        } else if accumX < -60 {
            onSwipe?(1)
            accumX = 0
        }
    }
}
