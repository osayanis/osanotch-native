import Foundation
import MultipeerConnectivity

// Transfert de fichier P2P natif, local, sans serveur (même réseau / Bluetooth).
// Appairage par code à 6 lettres via discoveryInfo.
final class MPCManager: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, waiting, connecting, transferring(Double), done(String), failed }
    @Published var phase: Phase = .idle

    private let serviceType = "osadrop"
    private let myPeer = MCPeerID(displayName: (Host.current().localizedName ?? "Mac").prefix(60).description)
    private lazy var session: MCSession = {
        let s = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required); s.delegate = self; return s
    }()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var fileURL: URL?
    private var code = ""
    private var progressObs: NSKeyValueObservation?

    // Côté envoyeur : on annonce le code, on attend un receveur.
    func send(file: URL, code: String) {
        reset(); self.fileURL = file; self.code = code; phase = .waiting
        advertiser = MCNearbyServiceAdvertiser(peer: myPeer, discoveryInfo: ["code": code], serviceType: serviceType)
        advertiser?.delegate = self; advertiser?.startAdvertisingPeer()
    }
    // Côté receveur : on cherche l'annonce qui porte ce code.
    func receive(code: String) {
        reset(); self.code = code; phase = .waiting
        browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: serviceType)
        browser?.delegate = self; browser?.startBrowsingForPeers()
    }
    func reset() {
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        session.disconnect(); fileURL = nil; progressObs = nil
        DispatchQueue.main.async { self.phase = .idle }
    }

    private func set(_ p: Phase) { DispatchQueue.main.async { self.phase = p } }
}

extension MPCManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session); set(.connecting)
    }
}

extension MPCManager: MCNearbyServiceBrowserDelegate {
    func browser(_ b: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        if info?["code"] == code { set(.connecting); b.invitePeer(peerID, to: session, withContext: nil, timeout: 30) }
    }
    func browser(_ b: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

extension MPCManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            if let url = fileURL {   // envoyeur → on envoie
                let prog = session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peerID) { [weak self] err in
                    self?.set(err == nil ? .done("Envoyé ✓") : .failed)
                }
                if let prog { progressObs = prog.observe(\.fractionCompleted) { [weak self] p, _ in self?.set(.transferring(p.fractionCompleted)) } }
            }
        case .notConnected:
            if case .transferring = phase {} else if case .done = phase {} else { set(.idle) }
        default: break
        }
    }
    func session(_ s: MCSession, didStartReceivingResourceWithName name: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        progressObs = progress.observe(\.fractionCompleted) { [weak self] p, _ in self?.set(.transferring(p.fractionCompleted)) }
    }
    func session(_ s: MCSession, didFinishReceivingResourceWithName name: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard error == nil, let localURL else { set(.failed); return }
        let dest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.moveItem(at: localURL, to: dest); set(.done("Reçu dans Téléchargements ✓")) }
        catch { set(.failed) }
    }
    func session(_ s: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ s: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
}
