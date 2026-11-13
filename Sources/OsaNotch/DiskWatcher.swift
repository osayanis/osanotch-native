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

/// Surveille les volumes montés (clé USB, disque dur, SSD, carte SD) et annonce chacun une fois.
/// Ignorés : disques internes, images disque (.dmg…), volumes réseau, volumes système.
final class DiskWatcher {
    var onDisk: ((OsaNotif) -> Void)?

    private let session = DASessionCreate(kCFAllocatorDefault)
    private var observer: NSObjectProtocol?
    /// Un même disque peut monter plusieurs volumes d'un coup : une seule notification par appareil.
    private var recent: [String: Date] = [:]

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self?.announce(url)
        }
    }

    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }

    func announce(_ url: URL) {
        guard let info = Self.describe(url, session: session) else { return }
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < 10 }
        if recent[info.device] != nil { return }
        recent[info.device] = now
        onDisk?(OsaNotif(source: .disk, title: info.name, body: info.detail, disk: info.kind, url: url))
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
        if proto == "Virtual Interface" || model.localizedCaseInsensitiveContains("Disk Image")
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
