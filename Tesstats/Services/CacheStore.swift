import Foundation

/// Lightweight, crash-proof offline cache. The iPhone is NOT a logger — this only
/// persists the last known live snapshot and most recently downloaded history as JSON
/// files in Application Support, keyed by car_id. Every operation is best-effort and
/// silently degrades if the filesystem is unavailable.
@MainActor
final class CacheStore {
    private let directory: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let fm = FileManager.default
        if let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                  appropriateFor: nil, create: true) {
            let dir = base.appendingPathComponent("TesstatsCache", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            directory = dir
        } else {
            directory = nil
        }
    }

    private func url(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    private func write<T: Encodable>(_ value: T, to name: String) {
        guard let url = url(name), let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    // MARK: Snapshot

    func saveSnapshot(_ state: VehicleState) { write(state, to: "snapshot-\(state.carID).json") }

    func loadSnapshot(carID: Int) -> VehicleState? { read(VehicleState.self, from: "snapshot-\(carID).json") }

    func loadAllSnapshots() -> [VehicleState] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(VehicleState.self, from: $0) }
    }

    // MARK: Drives

    func saveDrives(_ drives: [DriveRecord], carID: Int) { write(drives, to: "drives-\(carID).json") }
    func loadDrives(carID: Int) -> [DriveRecord] { read([DriveRecord].self, from: "drives-\(carID).json") ?? [] }

    // MARK: Charges

    func saveCharges(_ charges: [ChargeRecord], carID: Int) { write(charges, to: "charges-\(carID).json") }
    func loadCharges(carID: Int) -> [ChargeRecord] { read([ChargeRecord].self, from: "charges-\(carID).json") ?? [] }

    // MARK: Maintenance

    /// Delete every cached file (snapshots + downloaded history). Best-effort.
    func clearAll() {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    /// Approximate on-disk size of the cache, in bytes.
    func sizeBytes() -> Int {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
