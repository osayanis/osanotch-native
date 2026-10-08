import Foundation
import CoreAudio
import AudioToolbox
import CoreGraphics
import Combine

class SystemObserver: ObservableObject {
    @Published var volume: Float = 0.5
    @Published var showVolumeHUD: Bool = false
    @Published var brightness: Float = 0.5
    @Published var showBrightnessHUD: Bool = false

    private var defaultOutputDeviceID: AudioDeviceID = 0
    private var volumeTimer: Timer?
    private var brightnessTimer: Timer?
    private var lastBrightness: Float = -1
    private var osdSuppressed = false

    // DisplayServicesGetBrightness (framework privé) chargé dynamiquement → pas de bridging header.
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let getBrightness: GetBrightnessFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetBrightnessFn.self)
    }()

    init() {
        setupAudio()
        suppressNativeOSD()
        startBrightnessPolling()
    }

    deinit { restoreNativeOSD() }

    func setupAudio() {
        var propertySize: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )

        if status == noErr {
            updateVolume()
            
            // Add listener
            propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
            propertyAddress.mScope = kAudioDevicePropertyScopeOutput
            
            AudioObjectAddPropertyListenerBlock(defaultOutputDeviceID, &propertyAddress, nil) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.updateVolume()
                    self?.showHUD()
                }
            }
        }
    }

    func updateVolume() {
        var propertySize: UInt32 = UInt32(MemoryLayout<Float32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var vol: Float32 = 0.0
        let status = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &vol
        )

        if status == noErr {
            self.volume = vol
        }
    }

    func showHUD() {
        suppressNativeOSD()          // au cas où OSDUIHelper serait réapparu
        showBrightnessHUD = false
        showVolumeHUD = true
        volumeTimer?.invalidate()
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            self?.showVolumeHUD = false
        }
    }

    // ── Luminosité ──────────────────────────────────────────────
    private func startBrightnessPolling() {
        guard getBrightness != nil else { return }
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.pollBrightness()
        }
        pollBrightness(initial: true)
    }

    private func pollBrightness(initial: Bool = false) {
        guard let fn = getBrightness else { return }
        var b: Float = 0
        guard fn(CGMainDisplayID(), &b) == 0, b >= 0, b <= 1 else { return }
        if initial { lastBrightness = b; brightness = b; return }
        if abs(b - lastBrightness) > 0.001 {
            lastBrightness = b
            brightness = b
            showBrightnessHUDNow()
        }
    }

    private func showBrightnessHUDNow() {
        suppressNativeOSD()
        showVolumeHUD = false
        showBrightnessHUD = true
        brightnessTimerHide?.invalidate()
        brightnessTimerHide = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            self?.showBrightnessHUD = false
        }
    }
    private var brightnessTimerHide: Timer?

    // ── Supprimer l'OSD natif de macOS (OSDUIHelper) ─────────────
    // On SUSPEND le process (SIGSTOP) : le volume/la luminosité changent toujours,
    // mais l'overlay natif ne se dessine plus. Restauré (SIGCONT) à la fermeture.
    private func osd(_ signal: String) {
        let p = Process()
        p.launchPath = "/usr/bin/killall"
        p.arguments = [signal, "OSDUIHelper"]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
    }
    func suppressNativeOSD() { osd("-STOP"); osdSuppressed = true }
    func restoreNativeOSD() { if osdSuppressed { osd("-CONT"); osdSuppressed = false } }
}

import Network

class LocalServer {
    var listener: NWListener?
    var onNotify: ((String) -> Void)?

    func start() {
        guard let listener = try? NWListener(using: .tcp, on: 8081) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.receive(on: connection)
        }
        listener.start(queue: .global())
        print("🚀 LocalServer AI Notification API listening on port 8081")
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            if let data = data, let req = String(data: data, encoding: .utf8) {
                
                // Generalized AI API:
                // GET /notify?msg=Claude+a+fini
                // POST /notify {"msg": "Claude a fini"}
                
                if req.contains("GET /notify") {
                    let msg = self?.extractMsg(req) ?? "Tâche terminée"
                    DispatchQueue.main.async { self?.onNotify?(msg) }
                } else if req.contains("POST /notify") {
                    let msg = self?.extractJSON(req) ?? "Tâche terminée"
                    DispatchQueue.main.async { self?.onNotify?(msg) }
                }
                
                let resp = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nContent-Length: 2\r\n\r\nOK"
                connection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            }
        }
    }

    private func extractMsg(_ req: String) -> String {
        guard let range = req.range(of: "?msg=") else { return "Tâche terminée" }
        let sub = req[range.upperBound...]
        let end = sub.firstIndex(of: " ") ?? sub.endIndex
        let raw = String(sub[..<end])
        return raw.removingPercentEncoding?.replacingOccurrences(of: "+", with: " ") ?? raw
    }
    
    private func extractJSON(_ req: String) -> String {
        guard let bodyRange = req.range(of: "\r\n\r\n") else { return "Tâche terminée" }
        let body = String(req[bodyRange.upperBound...])
        // Simple regex-free JSON parsing for {"msg": "..."}
        if let msgRange = body.range(of: "\"msg\":\\s*\"([^\"]+)\"", options: .regularExpression) {
            let match = String(body[msgRange])
            if let start = match.firstIndex(of: ":"), let q1 = match[start...].firstIndex(of: "\""), let q2 = match[match.index(after: q1)...].firstIndex(of: "\"") {
                return String(match[match.index(after: q1)..<q2])
            }
        }
        return "Tâche terminée"
    }
}
