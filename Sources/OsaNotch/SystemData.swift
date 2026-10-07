import SwiftUI
import AppKit
import IOKit.ps
import EventKit

struct MusicInfo: Equatable {
    var playing: Bool; var title: String; var artist: String; var source: String
    var artworkURL: String?; var position: Double; var duration: Double
}
struct BatteryInfo: Equatable { var percent: Int; var charging: Bool }
struct AirpodsInfo: Equatable { var name: String; var left: Int?; var right: Int?; var caseLvl: Int?; var single: Int? }
struct EventInfo: Equatable { var title: String; var when: String }
struct ServicesInfo: Equatable { var party = false; var drop = false; var cast = false }

final class SystemData: ObservableObject {
    @Published var battery: BatteryInfo?
    @Published var music: MusicInfo?
    @Published var airpods: AirpodsInfo?
    @Published var event: EventInfo?
    @Published var services = ServicesInfo()
    @Published var artwork: NSImage?
    @Published var accent: Color = Color(red: 0.42, green: 0.55, blue: 1.0)

    private let q = DispatchQueue(label: "osa.system", qos: .utility)
    private var timers: [Timer] = []
    private var musicBusy = false, apBusy = false, calBusy = false
    private var lastArtKey = ""

    func start() {
        schedule(20) { [weak self] in self?.pollBattery() }
        schedule(5)  { [weak self] in self?.pollMusic() }
        schedule(60) { [weak self] in self?.pollAirpods() }
        schedule(300){ [weak self] in self?.pollCalendar() }
        schedule(60) { [weak self] in self?.pollServices() }
        requestCalendarAccess()
    }

    private func schedule(_ interval: TimeInterval, _ block: @escaping () -> Void) {
        block()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in block() }
        timers.append(t)
    }

    // MARK: Batterie (IOKit, aucune permission)
    private func pollBattery() {
        q.async {
            guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return }
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
                      let cap = d[kIOPSCurrentCapacityKey as String] as? Int else { continue }
                let state = d[kIOPSPowerSourceStateKey as String] as? String
                let info = BatteryInfo(percent: cap, charging: state == (kIOPSACPowerValue as String))
                DispatchQueue.main.async { self.battery = info }
                return
            }
        }
    }

    // MARK: Musique (sous-processus osascript, file série + timeout + anti-accumulation)
    private func pollMusic() {
        if musicBusy { return }
        musicBusy = true
        q.async {
            defer { self.musicBusy = false }
            let out = Self.runOsa(Self.buildMusicScript(), timeout: 4)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let out, !out.isEmpty, out != "none" else {
                DispatchQueue.main.async { self.music = nil; self.artwork = nil }
                return
            }
            let p = out.components(separatedBy: "||")
            guard p.count >= 6 else { return }
            var info = MusicInfo(playing: p[0] == "playing", title: p[1], artist: p[2], source: p[3],
                                 artworkURL: nil, position: Double(p[4]) ?? 0, duration: Double(p[5]) ?? 0)
            let key = "\(info.artist)|\(info.title)"
            DispatchQueue.main.async { self.music = info }
            if key != self.lastArtKey {
                self.lastArtKey = key
                self.fetchArtwork(artist: info.artist, title: info.title)
            }
            _ = info
        }
    }

    private func fetchArtwork(artist: String, title: String) {
        let term = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(term)&entity=song&limit=1") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let art = results.first?["artworkUrl100"] as? String else { return }
            let big = art.replacingOccurrences(of: "100x100bb", with: "400x400bb")
            guard let iurl = URL(string: big), let img = NSImage(contentsOf: iurl) else { return }
            let col = Self.vibrantColor(img)
            DispatchQueue.main.async { self.artwork = img; if let col { self.accent = col } }
        }.resume()
    }

    // MARK: AirPods / casque (system_profiler)
    private func pollAirpods() {
        if apBusy { return }; apBusy = true
        q.async {
            defer { self.apBusy = false }
            guard let out = Self.runShell("/usr/sbin/system_profiler", ["SPBluetoothDataType"], timeout: 9) else { return }
            let ap = Self.parseBluetooth(out)
            DispatchQueue.main.async { self.airpods = ap }
        }
    }

    // MARK: Agenda (EventKit)
    private let store = EKEventStore()
    private func requestCalendarAccess() {
        store.requestFullAccessToEvents { granted, _ in if granted { self.pollCalendar() } }
    }
    private func pollCalendar() {
        if calBusy { return }; calBusy = true
        q.async {
            defer { self.calBusy = false }
            let now = Date(); let end = now.addingTimeInterval(14 * 86400)
            let cals = self.store.calendars(for: .event)
            guard !cals.isEmpty else { return }
            let pred = self.store.predicateForEvents(withStart: now, end: end, calendars: cals)
            let evs = self.store.events(matching: pred).sorted { $0.startDate < $1.startDate }
            guard let e = evs.first else { DispatchQueue.main.async { self.event = nil }; return }
            let fmt = DateFormatter(); fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateFormat = "EEE d MMM · HH:mm"
            let info = EventInfo(title: e.title ?? "Évènement", when: fmt.string(from: e.startDate))
            DispatchQueue.main.async { self.event = info }
        }
    }

    // MARK: Services en ligne
    private func pollServices() {
        q.async {
            let check: (String) -> Bool = { urlStr in
                guard let url = URL(string: urlStr) else { return false }
                var req = URLRequest(url: url); req.httpMethod = "HEAD"; req.timeoutInterval = 4
                let sem = DispatchSemaphore(value: 0); var ok = false
                URLSession.shared.dataTask(with: req) { _, resp, _ in
                    if let h = resp as? HTTPURLResponse { ok = h.statusCode < 500 }
                    sem.signal()
                }.resume()
                _ = sem.wait(timeout: .now() + 5)
                return ok
            }
            let s = ServicesInfo(party: check("https://osaparty.osalabs.fr"),
                                 drop: check("https://osadrop.osalabs.fr"),
                                 cast: check("https://osacast.osalabs.fr"))
            DispatchQueue.main.async { self.services = s }
        }
    }

    // MARK: Helpers process
    static func runShell(_ launch: String, _ args: [String], timeout: TimeInterval) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: launch); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(40_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL); return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
    static func runOsa(_ script: String, timeout: TimeInterval) -> String? {
        runShell("/usr/bin/osascript", ["-e", script], timeout: timeout)
    }

    // On ne référence une app que si elle est RÉELLEMENT installée,
    // sinon macOS affiche « Où est <app> ? » en boucle.
    static var hasMusic: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") != nil }
    static var hasSpotify: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil }

    static func buildMusicScript() -> String {
        var s = "set out to \"none\"\n"
        if hasMusic {
            s += """
            if (running of application "Music") then
              tell application "Music"
                try
                  if player state is not stopped then
                    set pos to 0
                    set dur to 0
                    try
                      set pos to player position
                      set dur to duration of current track
                    end try
                    set out to (player state as string) & "||" & (name of current track) & "||" & (artist of current track) & "||Music||" & pos & "||" & dur
                  end if
                end try
              end tell
            end if
            """ + "\n"
        }
        if hasSpotify {
            s += """
            if out is "none" and (running of application "Spotify") then
              tell application "Spotify"
                try
                  set pos to 0
                  set dur to 0
                  try
                    set pos to player position
                    set dur to (duration of current track) / 1000
                  end try
                  set out to (player state as string) & "||" & (name of current track) & "||" & (artist of current track) & "||Spotify||" & pos & "||" & dur
                end try
              end tell
            end if
            """ + "\n"
        }
        s += "return out"
        return s
    }

    static func controlMusic(_ verb: String) {
        var s = ""
        if hasMusic { s += "if (running of application \"Music\") then\n  tell application \"Music\" to \(verb)\n" }
        if hasSpotify {
            s += s.isEmpty ? "if (running of application \"Spotify\") then\n  tell application \"Spotify\" to \(verb)\nend if"
                           : "else if (running of application \"Spotify\") then\n  tell application \"Spotify\" to \(verb)\nend if"
        } else if !s.isEmpty {
            s += "end if"
        }
        guard !s.isEmpty else { return }
        let script = s
        DispatchQueue.global(qos: .userInitiated).async { _ = runOsa(script, timeout: 4) }
    }

    static func parseBluetooth(_ out: String) -> AirpodsInfo? {
        var devices: [AirpodsInfo] = []
        var cur: AirpodsInfo?
        for raw in out.components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " }.count
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") && !line.contains("Bluetooth") && indent >= 10 && indent <= 14 {
                if let c = cur, c.left != nil || c.right != nil || c.single != nil { devices.append(c) }
                cur = AirpodsInfo(name: String(line.dropLast()), left: nil, right: nil, caseLvl: nil, single: nil)
            } else if cur != nil {
                func num(_ key: String) -> Int? {
                    guard line.hasPrefix(key) else { return nil }
                    return Int(line.replacingOccurrences(of: key, with: "").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
                }
                if let v = num("Left Battery Level:") { cur!.left = v }
                else if let v = num("Right Battery Level:") { cur!.right = v }
                else if let v = num("Case Battery Level:") { cur!.caseLvl = v }
                else if let v = num("Battery Level:") { cur!.single = v }
            }
        }
        if let c = cur, c.left != nil || c.right != nil || c.single != nil { devices.append(c) }
        return devices.first
    }

    static func vibrantColor(_ img: NSImage) -> Color? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }
        var best: (r: Int, g: Int, b: Int)? = nil; var bestScore = -1.0
        let stepX = max(1, w / 16), stepY = max(1, h / 16)
        for x in stride(from: 0, to: w, by: stepX) {
            for y in stride(from: 0, to: h, by: stepY) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let r = Int(c.redComponent * 255), g = Int(c.greenComponent * 255), b = Int(c.blueComponent * 255)
                let mx = Double(max(r, g, b)), mn = Double(min(r, g, b))
                let sat = mx == 0 ? 0 : (mx - mn) / mx
                let score = sat * mx
                if score > bestScore && mx > 70 { bestScore = score; best = (r, g, b) }
            }
        }
        guard let b = best else { return nil }
        return Color(red: Double(b.r)/255, green: Double(b.g)/255, blue: Double(b.b)/255)
    }
}
