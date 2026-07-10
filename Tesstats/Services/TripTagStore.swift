import Foundation

/// Local, device-only label for a drive (e.g. to separate business mileage for expenses).
/// Read-only towards TeslaMate: tags never leave the device except inside user exports.
enum TripTag: String, Codable, CaseIterable, Identifiable, Sendable {
    case work, personal

    var id: String { rawValue }
    var label: String {
        switch self {
        case .work: L("Work")
        case .personal: L("Personal")
        }
    }
    var icon: String {
        switch self {
        case .work: "briefcase.fill"
        case .personal: "person.fill"
        }
    }
}

/// Persists the drive-ID → tag map as JSON in UserDefaults. Drive IDs are TeslaMate's
/// own serial IDs, so they are stable across re-downloads and unique per install.
@MainActor
@Observable
final class TripTagStore {
    private(set) var tags: [Int: TripTag] = [:]

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "tesstats.triptags") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let raw = try? JSONDecoder().decode([String: TripTag].self, from: data) {
            tags = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
        }
    }

    func tag(for driveID: Int) -> TripTag? { tags[driveID] }

    /// Assign or clear (nil) the tag for a drive.
    func setTag(_ tag: TripTag?, for driveID: Int) {
        if let tag {
            tags[driveID] = tag
        } else {
            tags.removeValue(forKey: driveID)
        }
        persist()
    }

    func clear() {
        tags = [:]
        persist()
    }

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: tags.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: key)
        }
    }
}
