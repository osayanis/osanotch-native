import SwiftUI
import AppKit
import AVFoundation
import EventKit

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var accent: Color

    @State private var camAuth = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var screenAuth = CGPreflightScreenCaptureAccess()
    @State private var axAuth = AXIsProcessTrusted()
    @State private var calAuth = EKEventStore.authorizationStatus(for: .event) == .fullAccess || EKEventStore.authorizationStatus(for: .event) == .authorized
    
    @State private var checkTimer: Timer?
    
    var allGranted: Bool { camAuth && screenAuth && axAuth && calAuth }

    var body: some View {
        VStack(spacing: 16) {
            Text("Configuration Initiale")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 52)
            
            Text("OsaNotch a besoin de ces permissions pour fonctionner.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            VStack(spacing: 8) {
                PermissionRow(
                    icon: "calendar",
                    title: "Calendrier",
                    desc: "Pour afficher tes prochains évènements.",
                    isGranted: calAuth,
                    accent: accent
                ) {
                    let store = EKEventStore()
                    if #available(macOS 14.0, *) {
                        store.requestFullAccessToEvents { granted, _ in
                            DispatchQueue.main.async { self.calAuth = granted }
                        }
                    } else {
                        store.requestAccess(to: .event) { granted, _ in
                            DispatchQueue.main.async { self.calAuth = granted }
                        }
                    }
                }
                
                PermissionRow(
                    icon: "video.fill",
                    title: "Caméra",
                    desc: "Pour le miroir vidéo du Dashboard.",
                    isGranted: camAuth,
                    accent: accent
                ) {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async { self.camAuth = granted }
                    }
                }
                
                PermissionRow(
                    icon: "display",
                    title: "Capture d'écran",
                    desc: "Pour OsaCast.",
                    isGranted: screenAuth,
                    accent: accent
                ) {
                    CGRequestScreenCaptureAccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.screenAuth = CGPreflightScreenCaptureAccess()
                    }
                }
                
                PermissionRow(
                    icon: "figure.arms.open",
                    title: "Accessibilité",
                    desc: "Pour lire le statut des IA.",
                    isGranted: axAuth,
                    accent: accent
                ) {
                    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    let trusted = AXIsProcessTrustedWithOptions(options)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.axAuth = AXIsProcessTrusted()
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer(minLength: 0)
            
            Button {
                if allGranted {
                    model.view = .home
                }
            } label: {
                Text("Commencer")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(allGranted ? .black : .white.opacity(0.3))
                    .frame(width: 160, height: 40)
                    .background(RoundedRectangle(cornerRadius: 20).fill(allGranted ? accent : Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!allGranted)
            .padding(.bottom, 24)
        }
        .onAppear {
            let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                let newCam = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
                let newScreen = CGPreflightScreenCaptureAccess()
                let newAx = AXIsProcessTrusted()
                let newCal = EKEventStore.authorizationStatus(for: .event) == .fullAccess || EKEventStore.authorizationStatus(for: .event) == .authorized
                
                if newCam != camAuth { camAuth = newCam }
                if newScreen != screenAuth { screenAuth = newScreen }
                if newAx != axAuth { axAuth = newAx }
                if newCal != calAuth { calAuth = newCal }
            }
            RunLoop.main.add(t, forMode: .common)
            checkTimer = t
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }
}

struct PermissionRow: View {
    var icon: String
    var title: String
    var desc: String
    var isGranted: Bool
    var accent: Color
    var action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isGranted ? accent : .white.opacity(0.5))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(desc).font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(accent)
                    .font(.system(size: 20))
            } else {
                Button(action: action) {
                    Text("Autoriser")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}
