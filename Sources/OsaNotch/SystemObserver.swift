import Foundation
import CoreAudio
import AudioToolbox
import Combine

class SystemObserver: ObservableObject {
    @Published var volume: Float = 0.5
    @Published var showVolumeHUD: Bool = false

    private var defaultOutputDeviceID: AudioDeviceID = 0
    private var volumeTimer: Timer?

    init() {
        setupAudio()
    }

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
        showVolumeHUD = true
        volumeTimer?.invalidate()
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.showVolumeHUD = false
        }
    }
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
