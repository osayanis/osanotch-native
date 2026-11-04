import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct IslandShape: Shape {
    var bottom: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.maxX - bottom, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bottom), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Waveform: View {
    var color: Color; var active: Bool
    @State private var on = false
    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(color).frame(width: 2.5, height: active ? (on ? [10.0,16,8,13][i] : [5.0,8,13,6][i]) : 4)
                    .animation(.easeInOut(duration: 0.42 + Double(i) * 0.07).repeatForever(autoreverses: true), value: on)
            }
        }.frame(height: 16).onAppear { on = active }.onChange(of: active) { _, v in on = v }
    }
}

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var data: SystemData
    @ObservedObject var castBridge: CastBridge
    @ObservedObject var updater = AutoUpdater.shared

    var playing: Bool { data.music?.playing ?? false }
    var lowBat: Bool { if let b = data.battery { return b.percent <= 15 && !b.charging } else { return false } }
    var mood: Mood {
        if !model.expanded { return .sleeping }
        if model.dropHover { return .happy }
        if lowBat { return .worried }
        if playing { return .dancing }
        return .idle
    }
    var size: CGSize { model.shape }

    var body: some View {
        let exp = model.expanded
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(bottom: exp ? 28 : 12).fill(Color.black)
                if exp { content.transition(.opacity) }
                else if model.view == .notification && model.showNotifBanner { notifBanner.transition(.opacity) }
                else { collapsedView.transition(.opacity) }
                castLayer   // moteur OsaCast persistant : reste monté même notch replié
                bridgesLayer // ponts OsaDrop / OsaParty : idem, invisibles
                if model.dropHover { IslandShape(bottom: exp ? 28 : 12).stroke(data.accent, lineWidth: 2) }
            }
            .opacity(!exp && !hudActive && !playing && model.huisClosUnread == 0 && !model.showNotifBanner && !model.dropHover ? 0 : 1)
            .frame(width: size.width, height: size.height)
            .clipShape(IslandShape(bottom: exp ? 28 : 12))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: model.view)
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: model.viewHeight)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.sysObs.showVolumeHUD)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.sysObs.showBrightnessHUD)
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: playing)
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: model.huisClosUnread > 0)
        .animation(.spring(response: 0.44, dampingFraction: 0.8), value: model.showNotifBanner)
        .ignoresSafeArea()
        .onAppear { generateGreeting() }
        .onChange(of: friendBridge.myName) { _, _ in generateGreeting() }
    }

    // ── OsaCast : le WKWebView doit rester attaché à la fenêtre même quand le notch
    // se replie, sinon WebKit suspend la capture d'écran et le spectateur perd le flux.
    // On le garde donc monté en permanence ici (1×1 invisible hors visionnage).
    var castHosting: Bool { !castBridge.code.isEmpty }
    var castWatching: Bool { castBridge.code.isEmpty && (castBridge.phase == .connected || castBridge.phase == .live) }
    var castMounted: Bool { castHosting || castWatching || castBridge.phase == .connecting }
    var castShowsVideo: Bool { model.expanded && model.view == .cast && castWatching }

    @ViewBuilder var castLayer: some View {
        if castMounted {
            ZStack(alignment: .topTrailing) {
                HiddenWeb(webView: castBridge.webView)
                    .allowsHitTesting(castShowsVideo)
                if castShowsVideo {
                    // Barre de contrôle flottante : agrandir / réduire + quitter.
                    HStack(spacing: 8) {
                        Button { model.theater.toggle() } label: {
                            Image(systemName: model.theater ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                .frame(width: 30, height: 30).background(.black.opacity(0.55), in: Circle())
                        }.buttonStyle(.plain)
                        Button {
                            model.theater = false
                            castBridge.stop()
                            model.view = .home
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                .frame(width: 30, height: 30).background(.black.opacity(0.55), in: Circle())
                        }.buttonStyle(.plain)
                    }
                    .padding(14)
                }
            }
            .frame(width: castShowsVideo ? size.width : 1, height: castShowsVideo ? size.height : 1)
            .clipShape(IslandShape(bottom: model.expanded ? 28 : 12))
            .opacity(castShowsVideo ? 1 : 0.001)
        }
    }

    // Les WKWebView des ponts doivent rester attachés à la fenêtre quand le notch se replie
    // (sinon WebKit peut les suspendre) : un seul point de montage, permanent, 1×1 invisible.
    var bridgesLayer: some View {
        ZStack {
            HiddenWeb(webView: model.dropBridge.webView).frame(width: 1, height: 1)
            if let party = model.partyBridgeIfCreated {
                HiddenWeb(webView: party.webView).frame(width: 1, height: 1)
            }
        }
        .frame(width: 1, height: 1)
        .opacity(0.001)
        .allowsHitTesting(false)
    }

    @ViewBuilder var content: some View {
        switch model.view {
        case .home:         homeView
        case .dashboard:    DashboardView(model: model, accent: data.accent, back: { model.view = .home }).frame(width: 480, height: size.height)
        case .choice:       ChoiceView(model: model, accent: data.accent).frame(width: 380, height: size.height)
        case .notification: notifCenterView.frame(width: size.width, height: size.height)
        case .drop:         OsaDropView(model: model, accent: data.accent, back: { model.view = .home }, bridge: model.dropBridge).frame(width: 480, height: size.height)
        case .cast:         OsaCastView(model: model, accent: data.accent, back: { model.view = .home }, bridge: model.castBridge).frame(width: 520, height: size.height)
        case .party:        OsaPartyView(model: model, accent: data.accent, back: { model.view = .home }, bridge: model.partyBridge).frame(width: 500, height: size.height)
        case .onboarding:   OnboardingView(model: model, accent: data.accent).frame(width: 480, height: size.height)
        }
    }

    var hudActive: Bool { model.hudActive }

    // Bannière de notification : apparaît sous l'encoche sans survol. Si le son ou la
    // luminosité bougent en même temps, la barre se range dessous au lieu de la cacher.
    var notifBanner: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: model.notchH)
            if let n = model.notifications.first {
                HStack(spacing: 11) {
                    notifIcon(n, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(n.title).font(.system(size: 12, weight: .bold)).foregroundColor(.white).lineLimit(1)
                            if n.count > 1 {
                                Text("+\(n.count - 1)").font(.system(size: 9.5, weight: .bold)).foregroundColor(.black)
                                    .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(data.accent))
                            }
                        }
                        Text(n.body).font(.system(size: 11)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(Rectangle())
                .onTapGesture { model.open(n) }
                .id(n.id)
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
            if hudActive { hudRow.frame(height: 28).transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .frame(width: 360, height: size.height, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: model.notifications.first?.id)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: hudActive)
    }

    /// Icône de l'appli d'origine (Messages, Mail, Huis clos) ; la mascotte pour l'IA.
    @ViewBuilder func notifIcon(_ n: OsaNotif, size: CGFloat) -> some View {
        if let id = n.bundleID, let icon = AppIcons.icon(id) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else if n.source == .huisClos || n.source == .huisClosPoke {
            Image(systemName: "lock.fill").font(.system(size: size * 0.42, weight: .bold)).foregroundColor(.white)
                .frame(width: size, height: size).background(RoundedRectangle(cornerRadius: size * 0.25).fill(Color(white: 0.18)))
        } else {
            OsaCharacter(model: model, mood: .happy, accent: data.accent, size: size)
        }
    }

    /// Ligne d'une notification dans les listes (accueil, centre de notifications).
    func notifRow(_ n: OsaNotif, titleSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            notifIcon(n, size: 18).padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(n.count > 1 ? "\(n.title) · \(n.count)" : n.title).font(.system(size: titleSize, weight: .bold)).foregroundColor(.white).lineLimit(1)
                if n.source != .ai || n.body != n.title {
                    Text(n.body).font(.system(size: titleSize - 1.5)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                }
                Text(relTime(n.date)).font(.system(size: 9.5, weight: .medium)).foregroundColor(.white.opacity(0.35))
            }
            Spacer(minLength: 0)
            DismissButton { withAnimation(.easeOut(duration: 0.2)) { model.dismiss(n) } }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.open(n) }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    /// « Dernières notifications » + « Tout effacer ».
    func notifHeader(size: CGFloat) -> some View {
        HStack {
            Text("Dernières notifications").font(.system(size: size, weight: .bold)).foregroundColor(.white.opacity(0.45))
            Spacer(minLength: 4)
            if !model.notifications.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.2)) { model.clearNotifications() } } label: {
                    Text("Tout effacer").font(.system(size: size - 1, weight: .semibold)).foregroundColor(.white.opacity(0.5))
                }.buttonStyle(.plain).help("Effacer toutes les notifications")
            }
        }
    }

    /// Section Amis (accueil et centre de notifications) : ton nom et ton code, les demandes et
    /// invitations reçues, l'ajout par code, et la liste avec les invitations OsaParty / OsaCast.
    func friendsPanel(compact: Bool) -> some View {
        let fs: CGFloat = compact ? 9 : 10
        return VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 4) {
                Text("Amis").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.45))
                if !friendBridge.myName.isEmpty {
                    Circle().fill(friendBridge.online ? Color.green : Color.white.opacity(0.25)).frame(width: 5, height: 5)
                        .help(friendBridge.online ? "Connecté" : "Hors ligne : reconnexion…")
                }
                Spacer()
                if !friendBridge.myName.isEmpty {
                    Text(friendBridge.myCode).font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.35))
                        .textSelection(.enabled).help("Ton code ami : donne-le à tes amis")
                }
            }
            if friendBridge.myName.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Ton nom...", text: $friendCodeInput)
                        .textFieldStyle(.plain).font(.system(size: 11))
                        .padding(4).background(Color.white.opacity(0.1)).cornerRadius(4)
                        .onSubmit { saveFriendName() }
                    Button("Configurer") { saveFriendName() }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .bold)).foregroundColor(data.accent)
                }
            } else if let req = friendBridge.incomingRequests.first {
                invitation("\(req.name) veut être ton ami", ok: "Accepter", fs: fs,
                           yes: { friendBridge.accept(req) }, no: { friendBridge.decline(req) })
            } else if let req = friendBridge.incomingCast.first {
                invitation("\(req.friendName) partage son écran", ok: "Regarder", fs: fs, yes: {
                    model.castBridge.join(req.castCode)
                    model.view = .cast
                    friendBridge.incomingCast.removeFirst()
                }, no: { friendBridge.incomingCast.removeFirst() })
            } else if let req = friendBridge.incomingParty.first {
                invitation("\(req.friendName) lance une OsaParty", ok: "Écouter", fs: fs, yes: {
                    model.partyBridge.join(req.partyCode)
                    model.view = .party
                    friendBridge.incomingParty.removeFirst()
                }, no: { friendBridge.incomingParty.removeFirst() })
            } else {
                HStack(spacing: 4) {
                    TextField("Code ami", text: $friendCodeInput).textFieldStyle(.plain).font(.system(size: 10))
                        .padding(4).background(Color.white.opacity(0.1)).cornerRadius(4)
                        .onSubmit { addFriendCode() }
                    Button { addFriendCode() } label: { Image(systemName: "plus.circle.fill").foregroundColor(data.accent) }
                        .buttonStyle(.plain).help("Envoyer une demande d'ami")
                }
                if let st = friendBridge.status {
                    Text(st).font(.system(size: fs)).foregroundColor(.white.opacity(0.6)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                        if friendBridge.friends.isEmpty && friendBridge.status == nil {
                            Text("Entre le code d'un ami pour l'ajouter.").font(.system(size: fs)).foregroundColor(.white.opacity(0.35))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(friendBridge.friends, id: \.code) { f in
                            HStack {
                                Text(f.name).font(.system(size: 11)).foregroundColor(.white).lineLimit(1)
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        model.partyBridge.host()
                                        model.view = .party
                                        whenReady({ model.partyBridge.code }) { friendBridge.sendPartyRequest(to: f.code, partyCode: $0) }
                                    } label: { Image(systemName: "music.note").font(.system(size: 10)).foregroundColor(.white.opacity(0.6)) }
                                        .buttonStyle(.plain).help("Inviter à une OsaParty")
                                    Button {
                                        model.castBridge.host()
                                        model.view = .cast
                                        whenReady({ model.castBridge.code }) { friendBridge.sendCastRequest(to: f.code, castCode: $0) }
                                    } label: { Image(systemName: "play.display").font(.system(size: 10)).foregroundColor(.white.opacity(0.6)) }
                                        .buttonStyle(.plain).help("Partager ton écran avec cet ami")
                                }
                            }
                            .contextMenu { Button("Retirer \(f.name)", role: .destructive) { friendBridge.removeFriend(f) } }
                        }
                    }
                }
            }
        }
        .frame(width: compact ? 120 : 130, alignment: .topLeading)
    }

    private func invitation(_ text: String, ok: String, fs: CGFloat, yes: @escaping () -> Void, no: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text).font(.system(size: fs)).foregroundColor(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(ok, action: yes).buttonStyle(.plain).foregroundColor(data.accent).font(.system(size: fs, weight: .bold))
                Button("Refuser", action: no).buttonStyle(.plain).foregroundColor(.white.opacity(0.5)).font(.system(size: fs, weight: .bold))
            }
        }.padding(5).background(Color.white.opacity(0.1)).cornerRadius(5)
    }

    private func saveFriendName() {
        let n = friendCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        friendBridge.saveName(n); friendCodeInput = ""
    }

    private func addFriendCode() {
        guard !friendCodeInput.isEmpty else { return }
        friendBridge.sendFriendRequest(to: friendCodeInput); friendCodeInput = ""
    }

    /// Attend qu'un code de salon (OsaCast, OsaParty) soit attribué par le serveur, 10 s au plus.
    private func whenReady(_ code: @escaping () -> String, tries: Int = 20, _ go: @escaping (String) -> Void) {
        let c = code()
        if !c.isEmpty { return go(c) }
        guard tries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { whenReady(code, tries: tries - 1, go) }
    }

    /// Sans « Accès complet au disque », Messages et Mail restent invisibles : bouton direct.
    @ViewBuilder var accessHint: some View {
        if model.feed.needsAccess {
            Button { NSWorkspace.shared.open(NotificationFeed.settingsURL) } label: {
                Label("Messages et Mail : autoriser", systemImage: "lock.open.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(data.accent)
            }.buttonStyle(.plain)
        }
    }

    @ObservedObject var friendBridge = FriendBridge.shared
    @State private var friendCodeInput = ""
    @State private var greeting = "Salut !"
    @State private var waving = false
    @State private var waveTask: DispatchWorkItem?

    // Déclenche un petit « coucou » de la mascotte sur l'accueil.
    private func triggerWave() {
        waveTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { waving = true }
        let t = DispatchWorkItem { withAnimation(.easeIn(duration: 0.25)) { waving = false } }
        waveTask = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: t)
    }

    private func generateGreeting() {
        let name = friendBridge.myName.isEmpty ? "l'ami" : friendBridge.myName
        let msgs = [
            "Hey \(name) !",
            "Salut \(name) !",
            "Yo \(name) !",
            "Bonjour \(name) 👋",
            "Prêt \(name) ?",
            "Coucou \(name)",
            "En forme \(name) ?",
            "Quoi de neuf \(name) ?",
            "Au rapport \(name) 🫡",
            "Toujours là \(name) !",
            "Opérationnel \(name) ✨"
        ]
        greeting = msgs.randomElement()!
    }

    // Écran de notifications : mascotte à gauche, notifications récentes à droite + Amis.
    var notifCenterView: some View {
        HStack(spacing: 16) {
            VStack {
                OsaCharacter(model: model, mood: .happy, accent: data.accent, size: 58)
                Button { model.view = .home } label: {
                    Label("Accueil", systemImage: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.6))
                }.buttonStyle(.plain).help("Revenir à l'accueil")
            }
            .frame(width: 90)
            .transition(.move(edge: .leading).combined(with: .opacity))

            VStack(alignment: .leading, spacing: 8) {
                notifHeader(size: 11)
                if model.notifications.isEmpty {
                    Text("Aucune notification").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                } else {
                    ForEach(model.notifications.prefix(3)) { n in notifRow(n, titleSize: 12) }
                }
                Spacer(minLength: 0)
                accessHint
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            
            friendsPanel(compact: false)
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 14)
    }

    func relTime(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "à l'instant" }
        if s < 3600 { return "il y a \(s / 60) min" }
        return "il y a \(s / 3600) h"
    }

    @ViewBuilder var collapsedView: some View {
        if hudActive { hudView }
        else if playing || model.huisClosUnread > 0 {
            // Pochette et égaliseur collés aux bords de l'encoche physique. Messages Huis clos
            // non lus : icône à gauche (sans musique) et nombre à droite, jusqu'à la lecture.
            HStack(spacing: 0) {
                if playing { artwork(18, 5) } else { huisClosIcon }
                Spacer(minLength: model.notchW)
                if model.huisClosUnread > 0 { unreadBadge } else { Waveform(color: data.accent, active: true) }
            }
            .padding(.horizontal, 7)
            .frame(width: model.notchW + 56, height: model.notchH)
        }
        else if model.dropHover {
            HStack(spacing: 0) { Spacer(); OsaCharacter(model: model, mood: .idle, accent: data.accent, size: 28).offset(y: 5); Spacer() }
                .frame(width: model.notchW, height: model.notchH)
        } else {
            // Notch au repos : l'île est invisible, inutile d'y animer la mascotte (30 images/s).
            Color.clear.frame(width: model.notchW, height: model.notchH)
        }
    }

    var huisClosIcon: some View {
        notifIcon(OsaNotif(source: .huisClos, title: "", body: ""), size: 18)
    }

    var unreadBadge: some View {
        Text(model.huisClosUnread > 99 ? "99+" : "\(model.huisClosUnread)")
            .font(.system(size: 10.5, weight: .heavy, design: .rounded)).monospacedDigit()
            .foregroundColor(.black)
            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 16)
            .background(Capsule().fill(data.accent))
            .contentTransition(.numericText())
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.huisClosUnread)
            .help("Messages non lus dans Huis clos")
    }

    func volumeIcon(_ v: Float) -> String {
        if v <= 0.001 { return "speaker.slash.fill" }
        if v < 0.34 { return "speaker.wave.1.fill" }
        if v < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // HUD volume / luminosité : pastille blanche qui descend sous l'encoche.
    var hudView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: model.notchH)
            hudRow.frame(height: 30)
        }
        .frame(width: model.notchW, height: model.notchH + 30)
    }

    var hudRow: some View {
        let isVol = model.sysObs.showVolumeHUD
        let value = CGFloat(isVol ? model.sysObs.volume : model.sysObs.brightness)
        let icon = isVol ? volumeIcon(model.sysObs.volume) : "sun.max.fill"
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 16)
                .contentTransition(.symbolEffect(.replace))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(Color.white)
                        .frame(width: max(5, g.size.width * value))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.sysObs.volume)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.sysObs.brightness)
    }

    // ── Home ──
    var homeView: some View {
        VStack(spacing: 0) {
            TabBarView(model: model, accent: data.accent, dropHover: model.dropHover, battery: data.battery, lowBat: lowBat)
            if playing && !model.dropHover {
                playerView.transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                idleHome.transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear { triggerWave() }
    }

    // Accueil au repos : mascotte + raccourcis (et notifications si présentes).
    var idleHome: some View {
        VStack(spacing: 0) {
            if (!model.notifications.isEmpty || friendBridge.hasIncoming) && !model.dropHover {
                HStack(spacing: 16) {
                    VStack(spacing: -2) {
                        OsaCharacter(model: model, mood: mood, accent: data.accent, size: 54, wave: waving)
                        Text(greeting).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                    }
                    .frame(width: 80)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        notifHeader(size: 11)
                        ForEach(model.notifications.prefix(2)) { n in notifRow(n, titleSize: 11) }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    friendsPanel(compact: true)
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 4)
            } else {
                OsaCharacter(model: model, mood: mood, accent: data.accent, size: 60, wave: waving)
                    .padding(.top, 4)
                    .padding(.bottom, -2)
                Text(model.dropHover ? "Dépose ton fichier" : "OsaLabs")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1).padding(.horizontal, 24)
                Text(greeting)
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
            }
            
            Spacer(minLength: 4)
            if let newVer = updater.updateAvailable {
                HStack {
                    Text("Une mise à jour (v\(newVer)) est disponible !")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(updater.isUpdating ? "Installation..." : "Mettre à jour") {
                        updater.installUpdate()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(data.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(data.accent.opacity(0.15))
                    .cornerRadius(6)
                }
                .padding(.horizontal, 22).padding(.bottom, 6)
            }
        }
    }

    // ── Lecteur musique : pochette à gauche, paroles + barre + contrôles à droite ──
    var playerView: some View {
        HStack(alignment: .center, spacing: 14) {
            artwork(92, 13)
                .shadow(color: data.accent.opacity(0.5), radius: 11, y: 4)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(data.music?.title ?? "")
                        .font(.system(size: 13.5, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text(data.music?.artist ?? "")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
                }

                Spacer(minLength: 5)
                lyricsBlock
                Spacer(minLength: 5)

                HStack(spacing: 12) {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        playerScrubber(now: ctx.date)
                    }
                    HStack(spacing: 16) {
                        ctrl("backward.fill", 13) { SystemData.controlMusic("previous track") }
                        Button { SystemData.controlMusic("playpause") } label: {
                            ZStack {
                                Circle().fill(.white).frame(width: 30, height: 30).shadow(color: data.accent.opacity(0.6), radius: 6, y: 1)
                                Image(systemName: "pause.fill").font(.system(size: 12)).foregroundColor(.black)
                            }
                        }.buttonStyle(.plain)
                        ctrl("forward.fill", 13) { SystemData.controlMusic("next track") }
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 12)
    }

    // Position lue + temps écoulé depuis la lecture → progression fluide entre deux sondages.
    func livePosition(_ now: Date) -> Double {
        guard let m = data.music else { return 0 }
        var p = m.position
        if m.playing { p += now.timeIntervalSince(data.positionSampledAt) }
        return m.duration > 0 ? min(p, m.duration) : p
    }

    @ViewBuilder var lyricsBlock: some View {
        if data.lyrics.isEmpty {
            // Pas de paroles trouvées : petit égaliseur discret pour ne pas laisser de vide.
            HStack { Waveform(color: data.accent, active: true); Spacer() }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let idx = currentLyric(at: livePosition(ctx.date))
                // Style Apple Music : la ligne active glisse vers le haut, la suivante monte à sa place.
                VStack(alignment: .leading, spacing: 2) {
                    lyricLine(idx, active: true)
                    lyricLine(idx + 1, active: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: idx)
            }
        }
    }

    @ViewBuilder func lyricLine(_ i: Int, active: Bool) -> some View {
        let text = (i >= 0 && i < data.lyrics.count) ? data.lyrics[i].text : (active && i < 0 ? "♪" : " ")
        Text(text)
            .font(.system(size: active ? 15 : 11.5, weight: active ? .semibold : .regular))
            .foregroundColor(.white.opacity(active ? 1 : 0.3))
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("\(active ? "a" : "b")-\(i)")
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)))
    }

    func currentLyric(at pos: Double) -> Int {
        var idx = -1
        for (i, l) in data.lyrics.enumerated() { if l.t <= pos + 0.2 { idx = i } else { break } }
        return idx
    }

    func timeStr(_ s: Double) -> String {
        let t = max(0, Int(s)); return String(format: "%d:%02d", t / 60, t % 60)
    }

    func playerScrubber(now: Date) -> some View {
        let dur = data.music?.duration ?? 0
        let pos = livePosition(now)
        let prog = dur > 0 ? min(1, pos / dur) : 0
        return VStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(data.accent).frame(width: max(0, g.size.width * prog))
                }
            }.frame(height: 4)
            HStack {
                Text(timeStr(pos)).font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("-" + timeStr(dur - pos)).font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundColor(.white.opacity(0.4))
            }
        }
    }


    @ViewBuilder func artwork(_ s: CGFloat, _ radius: CGFloat) -> some View {
        if let a = data.artwork { Image(nsImage: a).resizable().frame(width: s, height: s).clipShape(RoundedRectangle(cornerRadius: radius)) }
        else { RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.08)).frame(width: s, height: s) }
    }

    func ctrl(_ icon: String, _ sz: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: sz)).foregroundColor(.white.opacity(0.65)) }.buttonStyle(.plain)
    }

    func handleAirDrop(_ providers: [NSItemProvider]) -> Bool {
        print("📥 DROP RECEIVED! Providers count: \(providers.count)")
        guard let p = providers.first else { return false }
        print("📥 Loading provider: \(p.registeredTypeIdentifiers)")
        
        _ = p.loadObject(ofClass: URL.self) { url, error in
            print("📥 Loaded URL: \(String(describing: url)), Error: \(String(describing: error))")
            guard let url else { return }
            DispatchQueue.main.async {
                model.droppedURL = url
                model.view = .drop
            }
        }
        return true
    }
}

/// Petit × pour effacer une notification : discret, plus visible au survol.
struct DismissButton: View {
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(hover ? 0.9 : 0.35))
                .frame(width: 16, height: 16)
                .background(Circle().fill(.white.opacity(hover ? 0.16 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Effacer")
    }
}
