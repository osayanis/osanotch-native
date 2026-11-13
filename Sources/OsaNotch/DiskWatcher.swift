import AppKit
import DiskArbitration
import IOKit

/// Type de disque branché : choisit le logo et le libellé de la notification.
enum DiskKind: Equatable {
    case usbStick, sdCard, ssd, hdd, external

    var label: String {
        switch self {
        case .usbStick: return "Clé USB"
        case .sdCard: return "Carte SD"
        case .ssd: return "SSD externe"
        case .hdd: return "Disque dur externe"
        case .external: return "Disque externe"
        }
    }

    /// Accord des participes : « Clé USB éjectée », « SSD externe éjecté ».
    var feminine: Bool { self == .usbStick || self == .sdCard }
    func past(_ verb: String) -> String { verb + (feminine ? "e" : "") }

    var symbol: String {
        switch self {
        case .usbStick: return "mediastick"
        case .sdCard: return "sdcard.fill"
        case .ssd: return "bolt.horizontal.fill"
        case .hdd: return "externaldrive.fill"
        case .external: return "externaldrive.fill"
        }
    }
}

/// Surveille les volumes (clé USB, disque dur, SSD, carte SD) : une notification au branchement et
/// une au retrait. Ignorés : disques internes, images disque (.dmg…), volumes réseau, volumes système.
final class DiskWatcher {
    var onDisk: ((OsaNotif) -> Void)?
    /// Volume retiré : la notification de son branchement n'a plus lieu d'être dans la liste.
    var onGone: ((URL) -> Void)?

    private let session = DASessionCreate(kCFAllocatorDefault)
    private var observers: [NSObjectProtocol] = []
    /// Un même disque peut monter / démonter plusieurs volumes d'un coup : une notification par appareil.
    private var recent: [String: Date] = [:]
    private var recentGone: [String: Date] = [:]
    /// Infos de chaque volume branché (par chemin) : une fois le disque parti, macOS ne les donne plus.
    private var known: [String: Info] = [:]
    /// Démontages demandés (Finder, menu « Éjecter », diskutil) : macOS prévient avant. Un disque
    /// arraché, lui, disparaît sans prévenir.
    private var requested: [String: Date] = [:]
    /// Tests : les images disque comptent comme des disques externes.
    static var allowImages = false

    func start() {
        // Disques déjà branchés au lancement : retenus sans notification, pour annoncer leur retrait.
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [] {
            if let info = Self.describe(url, session: session) { known[url.path] = info }
        }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self?.announce(url)
        })
        observers.append(nc.addObserver(forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self?.requested[url.path] = Date()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self?.removed(url)
        })
    }

    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    func announce(_ url: URL) {
        guard let info = Self.describe(url, session: session) else { return }
        known[url.path] = info
        recentGone[info.device] = nil
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < 10 }
        if recent[info.device] != nil { return }
        recent[info.device] = now
        onDisk?(OsaNotif(source: .disk, title: info.name, body: info.detail, disk: info.kind, url: url))
    }

    /// Volume démonté. Démontage demandé, ou appareil encore là : éjecté proprement (« tu peux la retirer »).
    /// Sinon (aucun préavis et l'appareil a disparu) : arraché sans être éjecté.
    func removed(_ url: URL) {
        guard let info = known.removeValue(forKey: url.path) else { return }
        let asked = requested.removeValue(forKey: url.path).map { Date().timeIntervalSince($0) < 120 } ?? false
        onGone?(url)
        recent[info.device] = nil
        let now = Date()
        recentGone = recentGone.filter { now.timeIntervalSince($0.value) < 10 }
        if recentGone[info.device] != nil { return }
        recentGone[info.device] = now
        // Laisser à IOKit le temps de retirer l'appareil s'il a été débranché
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            let present = asked || Self.devicePresent(info.device)
            let k = info.kind
            let body = present ? "\(k.label) \(k.past("éjecté")) · tu peux \(k.feminine ? "la" : "le") retirer"
                               : "\(k.label) \(k.past("retiré")) sans être \(k.past("éjecté"))"
            self?.onDisk?(OsaNotif(source: .disk, title: info.name, body: body, disk: k, diskGone: true))
        }
    }

    /// L'appareil (chemin IOKit) existe-t-il encore ?
    static func devicePresent(_ path: String) -> Bool {
        guard path.hasPrefix("IOService:") else { return false }
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return false }
        IOObjectRelease(entry)
        return true
    }

    struct Info { let name: String; let detail: String; let kind: DiskKind; let device: String }

    static func describe(_ url: URL, session: DASession?) -> Info? {
        guard url.path.hasPrefix("/Volumes/"), let session,
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let d = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        let bool = { (k: CFString) in (d[k as String] as? Bool) ?? ((d[k as String] as? NSNumber)?.boolValue ?? false) }
        let str = { (k: CFString) in d[k as String] as? String ?? "" }

        let proto = str(kDADiskDescriptionDeviceProtocolKey)
        let model = str(kDADiskDescriptionDeviceModelKey)
        let mediaPath = str(kDADiskDescriptionMediaPathKey)
        // Disque interne, réseau, image disque (installation d'une appli, coffre chiffré…) : pas de bannière
        if bool(kDADiskDescriptionDeviceInternalKey) || bool(kDADiskDescriptionVolumeNetworkKey) { return nil }
        if !allowImages, proto == "Virtual Interface" || model.localizedCaseInsensitiveContains("Disk Image")
            || mediaPath.contains("IOHDIX") { return nil }

        let medium = mediumType(disk)
        let icon = (d[kDADiskDescriptionMediaIconKey as String] as? [String: Any])?["IOBundleResourceFile"] as? String ?? ""
        let kind: DiskKind
        if proto == "Secure Digital" || icon.hasPrefix("SD") || model.localizedCaseInsensitiveContains("SD Card")
            || model.localizedCaseInsensitiveContains("SDXC") { kind = .sdCard }
        else if medium == "Solid State" { kind = .ssd }
        else if bool(kDADiskDescriptionMediaRemovableKey) { kind = .usbStick }
        else if medium == "Rotational" { kind = .hdd }
        else { kind = .external }

        let name = str(kDADiskDescriptionVolumeNameKey).isEmpty ? url.lastPathComponent : str(kDADiskDescriptionVolumeNameKey)
        var detail = kind.label
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = v.volumeTotalCapacity, total > 0 {
            if let free = v.volumeAvailableCapacity { detail += " · \(size(free)) libres sur \(size(total))" }
            else { detail += " · \(size(total))" }
        }
        let device = str(kDADiskDescriptionDevicePathKey).isEmpty ? url.path : str(kDADiskDescriptionDevicePathKey)
        return Info(name: name, detail: detail, kind: kind, device: device)
    }

    /// Taille à la française (Go, To, virgule) : l'appli n'a pas de traduction, le formateur
    /// du système écrivait « GB ».
    static func size(_ bytes: Int) -> String {
        let units = ["octets", "Ko", "Mo", "Go", "To"]
        var v = Double(bytes), i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.maximumFractionDigits = v < 10 ? 1 : 0
        f.minimumFractionDigits = 0
        return "\(f.string(from: NSNumber(value: v)) ?? "\(Int(v))") \(units[i])"
    }

    /// « Solid State » / « Rotational », lu dans les caractéristiques de l'appareil (IOKit), si le
    /// boîtier le dit (beaucoup de clés USB ne le disent pas).
    private static func mediumType(_ disk: DADisk) -> String? {
        var entry = DADiskCopyIOMedia(disk)
        defer { if entry != 0 { IOObjectRelease(entry) } }
        for _ in 0..<40 where entry != 0 {
            if let ch = IORegistryEntryCreateCFProperty(entry, "Device Characteristics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                return ch["Medium Type"] as? String
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(entry)
            entry = parent
        }
        return nil
    }
}
