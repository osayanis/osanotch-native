import SwiftUI

// Amis : chaque OsaNotch a un code à 6 chiffres. Les petits messages (demande d'ami, acceptation,
// invitation OsaCast / OsaParty) passent par le serveur OsaDrop (socket.io), qui les relaie au
// code visé et dit si l'ami était connecté. Client socket.io natif (Engine.IO v4 sur WebSocket) :
// pas de WebView cachée (WebKit la met en veille) ni de WebRTC (qui ne s'établissait jamais).
final class FriendBridge: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    static let shared = FriendBridge()

    @Published var myName: String = ""
    @Published var myCode: String = ""
    /// Petit message sous le champ (« Demande envoyée », « Pas connecté »…), effacé tout seul.
    @Published var status: String?
    @Published private(set) var online = false

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

    var hasIncoming: Bool { !incomingRequests.isEmpty || !incomingCast.isEmpty || !incomingParty.isEmpty }

    /// Bannière dans le notch quand quelque chose arrive (branché par AppModel).
    var onNotice: ((String) -> Void)?

    private static let url = URL(string: "wss://osadrop.osalabs.fr/socket.io/?EIO=4&transport=websocket")!
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var connected = false          // namespace socket.io rejoint (« 40 » reçu)
    private var retry: TimeInterval = 2
    private var reconnectWork: DispatchWorkItem?
    private var statusWork: DispatchWorkItem?
    private var ackID = 0
    private var acks: [Int: (Bool) -> Void] = [:]
    /// Codes à qui on a demandé d'être ami : seule leur acceptation nous ajoute.
    private var pendingOut: Set<String> = []

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
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
        pendingOut = Set(UserDefaults.standard.stringArray(forKey: "OsaFriendsPending") ?? [])
        connect()
    }

    func saveName(_ name: String) {
        myName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        UserDefaults.standard.set(myName, forKey: "OsaMyName")
        connect()
    }

    func addFriend(_ f: Friend) {
        guard !friends.contains(where: { $0.code == f.code }) else { return }
        friends.append(f)
        if let d = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(d, forKey: "OsaFriendsList") }
    }

    func removeFriend(_ f: Friend) {
        friends.removeAll { $0.code == f.code }
        if let d = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(d, forKey: "OsaFriendsList") }
    }

    // MARK: Actions

    func sendFriendRequest(to raw: String) {
        let code = raw.filter(\.isNumber)
        guard code.count == 6 else { return show("Un code ami a 6 chiffres") }
        guard code != myCode else { return show("C'est ton propre code 🙂") }
        guard !friends.contains(where: { $0.code == code }) else { return show("Déjà dans tes amis") }
        pendingOut.insert(code); savePending()
        send(to: code, ["type": "friend_request", "name": myName, "code": myCode]) { [weak self] ok in
            self?.show(ok ? "Demande envoyée" : "Pas connecté : réessaie quand son OsaNotch est ouvert")
        }
    }

    func accept(_ r: FriendRequest) {
        addFriend(Friend(name: r.name, code: r.code))
        incomingRequests.removeAll { $0.id == r.id }
        // Prévient l'autre : il nous ajoute à son tour (sinon l'amitié ne marche que dans un sens)
        send(to: r.code, ["type": "friend_accept", "name": myName, "code": myCode]) { _ in }
    }

    func decline(_ r: FriendRequest) {
        incomingRequests.removeAll { $0.id == r.id }
    }

    func sendCastRequest(to targetCode: String, castCode: String) {
        send(to: targetCode, ["type": "cast_request", "name": myName, "castCode": castCode]) { [weak self] ok in
            self?.show(ok ? "Invitation OsaCast envoyée" : "Ton ami n'est pas connecté")
        }
    }

    func sendPartyRequest(to targetCode: String, partyCode: String) {
        send(to: targetCode, ["type": "party_request", "name": myName, "partyCode": partyCode]) { [weak self] ok in
            self?.show(ok ? "Invitation OsaParty envoyée" : "Ton ami n'est pas connecté")
        }
    }

    private func savePending() { UserDefaults.standard.set(Array(pendingOut), forKey: "OsaFriendsPending") }

    private func show(_ text: String) {
        status = text
        statusWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.status = nil }
        statusWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    // MARK: Messages reçus

    private func received(_ d: [String: Any]) {
        guard let type = d["type"] as? String else { return }
        // N'importe qui connaissant un code peut écrire : textes bornés
        let name = String((d["name"] as? String ?? "").prefix(30))
        let who = name.isEmpty ? "Quelqu'un" : name
        switch type {
        case "friend_request":
            guard let code = d["code"] as? String, code.count == 6, code.allSatisfy(\.isNumber) else { return }
            if friends.contains(where: { $0.code == code }) {
                // Déjà amis (l'autre nous a perdus) : on confirme sans redemander
                send(to: code, ["type": "friend_accept", "name": myName, "code": myCode]) { _ in }
                return
            }
            guard !incomingRequests.contains(where: { $0.code == code }) else { return }
            incomingRequests.append(FriendRequest(name: who, code: code))
            onNotice?("\(who) veut être ton ami")
        case "friend_accept":
            guard let code = d["code"] as? String, pendingOut.contains(code) else { return }
            pendingOut.remove(code); savePending()
            addFriend(Friend(name: who, code: code))
            onNotice?("\(who) a accepté ta demande d'ami")
        case "cast_request":
            guard let c = d["castCode"] as? String, !c.isEmpty, c.count <= 12 else { return }
            incomingCast.append(CastRequest(friendName: who, castCode: c))
            onNotice?("\(who) partage son écran avec toi")
        case "party_request":
            guard let c = d["partyCode"] as? String, !c.isEmpty, c.count <= 12 else { return }
            incomingParty.append(PartyRequest(friendName: who, partyCode: c))
            onNotice?("\(who) t'invite à une OsaParty")
        default: break
        }
    }

    // MARK: socket.io minimal (Engine.IO v4)

    private func connect() {
        guard !myName.isEmpty else { return }
        reconnectWork?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        connected = false
        let t = session.webSocketTask(with: Self.url)
        task = t
        t.resume()
        listen(t)
    }

    private func listen(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self, t === self.task else { return }
            switch result {
            case .success(.string(let s)): self.handle(s); self.listen(t)
            case .success: self.listen(t)
            case .failure: self.dropped()
            }
        }
    }

    private func handle(_ s: String) {
        guard let kind = s.first else { return }
        switch kind {
        case "0": raw("40")                                     // ouvert → rejoint le namespace
        case "2": raw("3")                                      // ping → pong
        case "4": packet(String(s.dropFirst()))
        default: break
        }
    }

    private func packet(_ p: String) {
        guard let kind = p.first else { return }
        let rest = p.dropFirst()
        switch kind {
        case "0":                                               // namespace rejoint
            connected = true; online = true; retry = 2
            emit(["friend-listen", myCode])
        case "2":                                               // évènement
            guard let arr = json(String(rest.drop(while: \.isNumber))) as? [Any],
                  arr.first as? String == "friend-msg", let msg = arr.dropFirst().first as? [String: Any] else { return }
            received(msg)
        case "3":                                               // accusé
            let id = Int(String(rest.prefix(while: \.isNumber))) ?? -1
            let args = json(String(rest.drop(while: \.isNumber))) as? [Any]
            acks.removeValue(forKey: id)?(args?.first as? Bool ?? false)
        case "4": dropped()                                     // connexion refusée
        default: break
        }
    }

    private func send(to code: String, _ msg: [String: String], done: @escaping (Bool) -> Void) {
        guard connected else {
            if task == nil { connect() }
            return done(false)
        }
        ackID += 1
        let id = ackID
        acks[id] = done
        emit(["friend-send", ["to": code, "msg": msg]], ack: id)
        // Pas de réponse : considéré comme non livré
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.acks.removeValue(forKey: id)?(false) }
    }

    private func emit(_ items: [Any], ack: Int? = nil) {
        guard let d = try? JSONSerialization.data(withJSONObject: items), let s = String(data: d, encoding: .utf8) else { return }
        raw("42" + (ack.map(String.init) ?? "") + s)
    }

    private func raw(_ s: String) {
        task?.send(.string(s)) { [weak self] err in if err != nil { DispatchQueue.main.async { self?.dropped() } } }
    }

    private func json(_ s: String) -> Any? { s.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } }

    /// Coupure (réseau, veille, serveur relancé) : on se reconnecte, de plus en plus lentement.
    private func dropped() {
        connected = false; online = false
        acks.values.forEach { $0(false) }; acks.removeAll()
        task?.cancel(); task = nil
        reconnectWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + retry, execute: w)
        retry = min(retry * 2, 60)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if webSocketTask === task { dropped() }
    }
}
