import Foundation
import CoreAudio
import AudioToolbox
import CoreGraphics
import AppKit
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
    // Fenêtre pendant laquelle un changement de luminosité est considéré comme volontaire
    // (touche F1/F2 pressée récemment) → on affiche le HUD seulement dans ce cas, jamais
    // pour l'ajustement automatique par le capteur de lumière.
    private var brightnessKeyUntil: TimeInterval = 0

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let getBrightness: GetBrightnessFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetBrightnessFn.self)
    }()

    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let setBrightness: SetBrightnessFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let sym = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetBrightnessFn.self)
    }()

    init() {
        setupAudio()
        suppressNativeOSD()
        startBrightnessKeyWatch()
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

    func setVolumeValue(_ val: Float) {
        var v = Float32(max(0, min(1, val)))
        var propertySize: UInt32 = UInt32(MemoryLayout<Float32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(defaultOutputDeviceID, &propertyAddress, 0, nil, propertySize, &v)
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
            // HUD seulement si l'utilisateur vient d'appuyer sur F1/F2 — pas pour l'auto-réglage.
            if Date().timeIntervalSinceReferenceDate < brightnessKeyUntil {
                showBrightnessHUDNow()
            }
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private func startBrightnessKeyWatch() {
        let mask = (1 << 14) // CGEventType.systemDefined
        let observerPtr = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon in
                if type.rawValue == 14 {
                    if let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
                        let data1 = nsEvent.data1
                        let keyCode = Int((data1 & 0xFFFF0000) >> 16)
                        let keyFlags = Int(data1 & 0x0000FFFF)
                        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
                        
                        // 0=volUp, 1=volDown, 7=mute, 2=brightUp, 3=brightDown
                        if [0,1,7,2,3].contains(keyCode) {
                            if keyDown, let ref = refcon {
                                let obs = Unmanaged<SystemObserver>.fromOpaque(ref).takeUnretainedValue()
                                DispatchQueue.main.async {
                                    if keyCode == 0 { obs.setVolumeValue(obs.volume + 0.0625) }
                                    else if keyCode == 1 { obs.setVolumeValue(obs.volume - 0.0625) }
                                    else if keyCode == 7 { obs.setVolumeValue(obs.volume > 0 ? 0 : 0.1) }
                                    else if keyCode == 2 {
                                        obs.brightnessKeyUntil = Date().timeIntervalSinceReferenceDate + 0.9
                                        let nb = min(1, obs.brightness + 0.0625)
                                        obs.brightness = nb
                                        obs.showBrightnessHUDNow()
                                        if let fn = obs.setBrightness { _ = fn(CGMainDisplayID(), nb) }
                                    }
                                    else if keyCode == 3 {
                                        obs.brightnessKeyUntil = Date().timeIntervalSinceReferenceDate + 0.9
                                        let nb = max(0, obs.brightness - 0.0625)
                                        obs.brightness = nb
                                        obs.showBrightnessHUDNow()
                                        if let fn = obs.setBrightness { _ = fn(CGMainDisplayID(), nb) }
                                    }
                                }
                            }
                            return nil // swallow event, disables native macOS OSD!
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: observerPtr
        )
        
        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            print("WARNING: OsaNotch requires Accessibility permissions to swallow native OSD.")
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

    // Native OSD suppression is now handled by the CGEventTap intercepting the keys.
    func suppressNativeOSD() {}
    func restoreNativeOSD() {}
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
