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
struct EventInfo: Equatable { var title: String; var start: Date; var end: Date }
struct ServicesInfo: Equatable { var party = false; var drop = false; var cast = false }
struct LyricLine: Equatable { var t: Double; var text: String }

final class SystemData: ObservableObject {
    @Published var battery: BatteryInfo?
    @Published var music: MusicInfo?
    @Published var airpods: AirpodsInfo?
    @Published var event: EventInfo?
    @Published var events: [EventInfo] = []    // évènements de la fenêtre (−3 j … +14 j)
    @Published var services = ServicesInfo()
    @Published var artwork: NSImage?
    @Published var accent: Color = Color(red: 0.42, green: 0.55, blue: 1.0)
    @Published var lyrics: [LyricLine] = []
    @Published var positionSampledAt = Date()   // instant où `music.position` a été lu → interpolation fluide

    private let q = DispatchQueue(label: "osa.system", qos: .utility)
    private var timers: [Timer] = []
    private var musicBusy = false, apBusy = false, calBusy = false
    private var lastArtKey = ""

    func start() {
        schedule(20) { [weak self] in self?.pollBattery() }
        schedule(2)  { [weak self] in self?.pollMusic() }
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
            // AppleScript sort les décimales avec la virgule en locale FR → remplacer avant parsing.
            func num(_ s: String) -> Double { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0 }
            
            let artRaw = p.count > 6 ? p[6] : ""
            var info = MusicInfo(playing: p[0] == "playing", title: p[1], artist: p[2], source: p[3],
                                 artworkURL: artRaw, position: num(p[4]), duration: num(p[5]))
            let key = "\(info.artist)|\(info.title)"
            DispatchQueue.main.async { self.music = info; self.positionSampledAt = Date() }
            if key != self.lastArtKey {
                self.lastArtKey = key
                DispatchQueue.main.async { self.lyrics = []; self.artwork = nil }
                
                if artRaw.hasPrefix("local:") {
                    let path = artRaw.replacingOccurrences(of: "local:", with: "")
                    if let img = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                        let col = Self.vibrantColor(img)
                        DispatchQueue.main.async {
                            guard self.lastArtKey == key else { return }
                            self.artwork = img; if let col { self.accent = col }
                        }
                    }
                } else if artRaw.hasPrefix("http") {
                    if let iurl = URL(string: artRaw) {
                        URLSession.shared.dataTask(with: iurl) { data, _, _ in
                            guard self.lastArtKey == key, let data, let img = NSImage(data: data) else { return }
                            let col = Self.vibrantColor(img)
                            DispatchQueue.main.async {
                                guard self.lastArtKey == key else { return }
                                self.artwork = img; if let col { self.accent = col }
                            }
                        }.resume()
                    }
                } else {
                    self.fetchArtwork(artist: info.artist, title: info.title)
                }
                
                self.fetchLyrics(artist: info.artist, title: info.title, duration: info.duration)
            }
            _ = info
        }
    }

    private func fetchArtwork(artist: String, title: String) {
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "" }
        // Chaîne de repli : la recherche "artiste titre" exacte échoue souvent → essayer plus large.
        let queries = [
            "https://itunes.apple.com/search?term=\(enc("\(artist) \(title)"))&entity=song&limit=1",
            "https://itunes.apple.com/search?term=\(enc(title))&entity=song&limit=1",
            "https://itunes.apple.com/search?term=\(enc(artist))&entity=musicArtist&attribute=artistTerm&limit=1",
            "https://itunes.apple.com/search?term=\(enc(artist))&entity=album&limit=1",
        ]
        let wantKey = "\(artist)|\(title)"

        func artURL(_ data: Data?) -> String? {
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return nil }
            return results.first?["artworkUrl100"] as? String
        }
        func tryQuery(_ i: Int) {
            guard i < queries.count, let url = URL(string: queries[i]) else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard self.lastArtKey == wantKey else { return }   // morceau changé entre-temps
                guard let art = artURL(data) else { tryQuery(i + 1); return }
                let big = art.replacingOccurrences(of: "100x100bb", with: "400x400bb")
                guard let iurl = URL(string: big), let img = NSImage(contentsOf: iurl) else { tryQuery(i + 1); return }
                let col = Self.vibrantColor(img)
                DispatchQueue.main.async {
                    guard self.lastArtKey == wantKey else { return }
                    self.artwork = img; if let col { self.accent = col }
                }
            }.resume()
        }
        tryQuery(0)
    }

    // MARK: Paroles synchronisées (LRCLIB, gratuit, sans clé)
    private func fetchLyrics(artist: String, title: String, duration: Double) {
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "" }
        // /get exige une durée proche ; on retombe sur /search sinon.
        let getURL = "https://lrclib.net/api/get?artist_name=\(enc(artist))&track_name=\(enc(title))&duration=\(Int(duration.rounded()))"
        let searchURL = "https://lrclib.net/api/search?track_name=\(enc(title))&artist_name=\(enc(artist))"
        let myKey = "\(artist)|\(title)"

        func parseAndSet(_ synced: String) {
            let lines = Self.parseLRC(synced)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                // N'applique que si le morceau courant est toujours le même.
                if self.lastArtKey == myKey { self.lyrics = lines }
            }
        }
        func req(_ s: String) -> URLRequest {
            var r = URLRequest(url: URL(string: s)!)
            r.setValue("OsaNotch (https://osalabs.fr)", forHTTPHeaderField: "User-Agent")
            return r
        }

        URLSession.shared.dataTask(with: req(getURL)) { data, resp, _ in
            if let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let synced = j["syncedLyrics"] as? String, !synced.isEmpty {
                parseAndSet(synced); return
            }
            // fallback recherche
            URLSession.shared.dataTask(with: req(searchURL)) { data, _, _ in
                guard let data, let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
                if let synced = arr.compactMap({ $0["syncedLyrics"] as? String }).first(where: { !$0.isEmpty }) {
                    parseAndSet(synced)
                }
            }.resume()
        }.resume()
    }

    // Parse le format LRC : "[mm:ss.xx] texte" (plusieurs horodatages possibles par ligne).
    static func parseLRC(_ raw: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for line in raw.components(separatedBy: .newlines) {
            guard let close = line.firstIndex(of: "]") else { continue }
            let text = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            var rest = Substring(line)
            while let open = rest.firstIndex(of: "["), let end = rest.firstIndex(of: "]"), open < end {
                let stamp = rest[rest.index(after: open)..<end]
                let comps = stamp.split(separator: ":")
                if comps.count == 2, let m = Double(comps[0]), let s = Double(comps[1]) {
                    out.append(LyricLine(t: m * 60 + s, text: text))
                }
                rest = rest[rest.index(after: end)...]
            }
        }
        return out.filter { !$0.text.isEmpty }.sorted { $0.t < $1.t }
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
            let cal = Calendar.current
            let now = Date()
            let weekStart = cal.startOfDay(for: now.addingTimeInterval(-3 * 86400))
            let end = now.addingTimeInterval(14 * 86400)
            let cals = self.store.calendars(for: .event)
            guard !cals.isEmpty else { return }
            let pred = self.store.predicateForEvents(withStart: weekStart, end: end, calendars: cals)
            let evs = self.store.events(matching: pred).sorted { $0.startDate < $1.startDate }
            let all = evs.map { EventInfo(title: $0.title ?? "Évènement", start: $0.startDate, end: $0.endDate) }
            // Prochain évènement (à venir).
            let next = all.first { $0.end >= now }
            DispatchQueue.main.async { self.event = next; self.events = all }
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
                    set artFlag to ""
                    try
                      set pos to player position
                      set dur to duration of current track
                    end try
                    try
                      if exists (artwork 1 of current track) then
                        set artData to raw data of artwork 1 of current track
                        set f to open for access (POSIX file "/tmp/osa_art.jpg") with write permission
                        set eof of f to 0
                        write artData to f
                        close access f
                        set artFlag to "local:/tmp/osa_art.jpg"
                      end if
                    end try
                    set out to (player state as string) & "||" & (name of current track) & "||" & (artist of current track) & "||Music||" & pos & "||" & dur & "||" & artFlag
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
                  set artUrl to ""
                  try
                    set pos to player position
                    set dur to (duration of current track) / 1000
                  end try
                  try
                    set artUrl to artwork url of current track
                  end try
                  set out to (player state as string) & "||" & (name of current track) & "||" & (artist of current track) & "||Spotify||" & pos & "||" & dur & "||" & artUrl
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
