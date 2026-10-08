import SwiftUI
import WebKit

final class FriendBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    static let shared = FriendBridge()
    
    let webView: WKWebView
    
    @Published var myName: String = ""
    @Published var myCode: String = ""
    
    // Un ami : nom + code
    struct Friend: Codable, Equatable, Hashable {
        let name: String
        let code: String
    }
    @Published var friends: [Friend] = []
    
    struct FriendRequest: Equatable, Identifiable {
        let id = UUID()
        let name: String
        let code: String
    }
    @Published var incomingRequests: [FriendRequest] = []
    
    struct CastRequest: Equatable, Identifiable {
        let id = UUID()
        let friendName: String
        let castCode: String
    }
    @Published var incomingCast: [CastRequest] = []
    
    struct PartyRequest: Equatable, Identifiable {
        let id = UUID()
        let friendName: String
        let partyCode: String
    }
    @Published var incomingParty: [PartyRequest] = []
    
    override init() {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        cfg.userContentController = ucc
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        ucc.add(self, name: "osaFriend")
        
        myName = UserDefaults.standard.string(forKey: "OsaMyName") ?? ""
        myCode = UserDefaults.standard.string(forKey: "OsaMyCode") ?? ""
        if myCode.isEmpty {
            myCode = String(Int.random(in: 100000...999999))
            UserDefaults.standard.set(myCode, forKey: "OsaMyCode")
        }
        
        if let d = UserDefaults.standard.data(forKey: "OsaFriendsList"),
           let f = try? JSONDecoder().decode([Friend].self, from: d) {
            friends = f
        }
        
        loadHTML()
    }
    
    func saveName(_ name: String) {
        myName = name
        UserDefaults.standard.set(myName, forKey: "OsaMyName")
        reload()
    }
    
    func addFriend(_ f: Friend) {
        if !friends.contains(f) {
            friends.append(f)
            if let d = try? JSONEncoder().encode(friends) {
                UserDefaults.standard.set(d, forKey: "OsaFriendsList")
            }
        }
    }
    
    private func reload() {
        loadHTML()
    }
    
    private func loadHTML() {
        guard !myName.isEmpty else { return }
        // On crée un script HTML complet avec Socket.io
        let html = """
        <!doctype html>
        <html>
        <head><script src="https://osadrop.osalabs.fr/socket.io/socket.io.js"></script></head>
        <body>
        <script>
        const myName = "\(myName)";
        const myCode = "\(myCode)";
        
        let socket = io("https://osadrop.osalabs.fr", { transports: ["websocket", "polling"] });
        let pcs = {}; // peerId -> RTCPeerConnection
        
        function post(msg) {
            window.webkit.messageHandlers.osaFriend.postMessage(msg);
        }
        
        socket.on("connect", () => {
            // Join my own permanent room to listen for incoming WebRTC offers
            socket.emit("join-room", "signal_" + myCode);
            post({type: "log", msg: "Connected to signal_" + myCode});
        });
        
        socket.on("offer", async (p) => {
            const peerId = p.caller;
            if (!pcs[peerId]) {
                const pc = new RTCPeerConnection({ iceServers: [{ urls: "stun:stun1.l.google.com:19302" }] });
                pcs[peerId] = pc;
                pc.onicecandidate = (e) => { if (e.candidate) socket.emit("ice-candidate", { target: peerId, candidate: e.candidate }); };
                pc.ondatachannel = (e) => setupDC(e.channel);
            }
            const pc = pcs[peerId];
            await pc.setRemoteDescription(p.sdp);
            const ans = await pc.createAnswer();
            await pc.setLocalDescription(ans);
            socket.emit("answer", { target: peerId, sdp: ans });
        });
        
        socket.on("answer", async (p) => {
            if (pcs[p.caller]) await pcs[p.caller].setRemoteDescription(p.sdp);
        });
        socket.on("ice-candidate", async (p) => {
            if (pcs[p.caller]) try { await pcs[p.caller].addIceCandidate(p.candidate); } catch (e) {}
        });
        
        function setupDC(dc) {
            dc.onmessage = (e) => {
                try {
                    const data = JSON.parse(e.data);
                    post(data);
                } catch(err) {}
            };
        }
        
        // Commandes envoyées depuis Swift
        window.sendToTarget = async (targetCode, msgObj) => {
            // On rejoint temporairement la room de la cible
            const tempSocket = io("https://osadrop.osalabs.fr", { transports: ["websocket", "polling"] });
            tempSocket.on("connect", () => {
                tempSocket.emit("join-room", "signal_" + targetCode);
            });
            tempSocket.on("room-joined", async () => {
                // Dès qu'on a rejoint sa room, on va recevoir "peer-connected" du serveur s'il est là.
                // S'il est seul (il n'y a que nous), on attend qu'il se connecte. S'il est là, on lance l'offre.
            });
            tempSocket.on("peer-connected", async (peerId) => {
                const pc = new RTCPeerConnection({ iceServers: [{ urls: "stun:stun1.l.google.com:19302" }] });
                pcs[peerId] = pc;
                pc.onicecandidate = (e) => { if (e.candidate) tempSocket.emit("ice-candidate", { target: peerId, candidate: e.candidate }); };
                const dc = pc.createDataChannel("osa-signal");
                setupDC(dc);
                
                dc.onopen = () => {
                    dc.send(JSON.stringify(msgObj));
                    setTimeout(() => tempSocket.disconnect(), 5000); // déconnexion après envoi
                };
                
                const offer = await pc.createOffer();
                await pc.setLocalDescription(offer);
                tempSocket.emit("offer", { target: peerId, sdp: offer });
            });
            
            // On gère les answer et ice de ce tempSocket
            tempSocket.on("answer", async (p) => {
                if (pcs[p.caller]) await pcs[p.caller].setRemoteDescription(p.sdp);
            });
            tempSocket.on("ice-candidate", async (p) => {
                if (pcs[p.caller]) try { await pcs[p.caller].addIceCandidate(p.candidate); } catch(e) {}
            });
        };
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    func sendFriendRequest(to targetCode: String) {
        let msg = ["type": "friend_request", "name": myName, "code": myCode]
        runJS(targetCode: targetCode, msg: msg)
    }
    
    func sendCastRequest(to targetCode: String, castCode: String) {
        let msg = ["type": "cast_request", "name": myName, "castCode": castCode]
        runJS(targetCode: targetCode, msg: msg)
    }
    
    func sendPartyRequest(to targetCode: String, partyCode: String) {
        let msg = ["type": "party_request", "name": myName, "partyCode": partyCode]
        runJS(targetCode: targetCode, msg: msg)
    }
    
    private func runJS(targetCode: String, msg: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("window.sendToTarget('\(targetCode)', \(json))", completionHandler: nil)
        }
    }
    
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let type = d["type"] as? String else { return }
        DispatchQueue.main.async {
            if type == "friend_request" {
                if let name = d["name"] as? String, let code = d["code"] as? String {
                    // Ignore if already friends
                    if !self.friends.contains(where: { $0.code == code }) {
                        self.incomingRequests.append(FriendRequest(name: name, code: code))
                    }
                }
            } else if type == "cast_request" {
                if let name = d["name"] as? String, let castCode = d["castCode"] as? String {
                    self.incomingCast.append(CastRequest(friendName: name, castCode: castCode))
                }
            } else if type == "party_request" {
                if let name = d["name"] as? String, let partyCode = d["partyCode"] as? String {
                    self.incomingParty.append(PartyRequest(friendName: name, partyCode: partyCode))
                }
            } else if type == "log" {
                print("FriendBridge: \(d["msg"] ?? "")")
            }
        }
    }
}
