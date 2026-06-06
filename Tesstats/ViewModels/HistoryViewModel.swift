import Foundation

@MainActor
@Observable
final class HistoryViewModel {
    enum Phase: Equatable {
        case idle, loading, loaded, empty(String), failed(String)
    }

    private(set) var drives: [DriveRecord] = []
    private(set) var charges: [ChargeRecord] = []
    private(set) var battery: [BatteryHealthPoint] = []
    private(set) var carInfo: CarInfo?
    private(set) var phase: Phase = .idle
    private(set) var usingCache = false

    private let settings: SettingsStore
    private let cache: CacheStore
    private var loadedCarID: Int?

    init(settings: SettingsStore, cache: CacheStore) {
        self.settings = settings
        self.cache = cache
    }

    var chargeAggregates: ChargeAggregates { ChargeAggregates.from(charges) }
    var efficiency: EfficiencySummary { EfficiencySummary.from(drives) }

    func loadIfNeeded(carID: Int) async {
        guard loadedCarID != carID || phase == .idle else { return }
        await load(carID: carID)
    }

    /// Drop all in-memory history so the next view re-fetches (used after clearing data/cache).
    func reset() {
        drives = []
        charges = []
        battery = []
        carInfo = nil
        usingCache = false
        loadedCarID = nil
        phase = .idle
    }

    func refresh(carID: Int) async { await load(carID: carID) }

    private func load(carID: Int) async {
        loadedCarID = carID
        usingCache = false

        if settings.config.demoMode {
            drives = DemoDataProvider.drives()
            charges = DemoDataProvider.charges()
            battery = DemoDataProvider.batteryHealth()
            carInfo = DemoDataProvider.carInfo
            phase = .loaded
            return
        }

        guard let api = makeAPI() else {
            // No history API configured — show cached data if any.
            drives = cache.loadDrives(carID: carID)
            charges = cache.loadCharges(carID: carID)
            battery = Self.deriveBattery(charges: charges, drives: drives, efficiency: carInfo?.efficiencyKwhPerKm)
            usingCache = !drives.isEmpty || !charges.isEmpty
            phase = usingCache ? .loaded
                : .empty(L("Add a TeslaMateApi URL in Settings to see drives, charges and battery history."))
            return
        }

        phase = .loading
        do {
            async let d = api.fetchDrives(carID: carID)
            async let c = api.fetchCharges(carID: carID)
            let (dd, cc) = try await (d, c)
            let fetchedInfo = (try? await api.fetchCarInfo(carID: carID)) ?? nil
            if let fetchedInfo { carInfo = fetchedInfo }
            drives = dd
            charges = cc
            battery = Self.deriveBattery(charges: cc, drives: dd, efficiency: carInfo?.efficiencyKwhPerKm)
            cache.saveDrives(dd, carID: carID)
            cache.saveCharges(cc, carID: carID)
            phase = (dd.isEmpty && cc.isEmpty)
                ? .empty(L("No history returned yet."))
                : .loaded
        } catch {
            // Fall back to cache on failure.
            drives = cache.loadDrives(carID: carID)
            charges = cache.loadCharges(carID: carID)
            battery = Self.deriveBattery(charges: charges, drives: drives, efficiency: carInfo?.efficiencyKwhPerKm)
            if !drives.isEmpty || !charges.isEmpty {
                usingCache = true
                phase = .loaded
            } else {
                phase = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Fetch the real GPS trace of a drive so the detail map can draw the actual route
    /// instead of geocoding the ambiguous address text. Returns nil in demo mode (the demo
    /// drives already carry their own path) or when no API is configured.
    func driveTrace(carID: Int, driveID: Int) async -> DriveTrace? {
        if settings.config.demoMode { return nil }
        guard let api = makeAPI() else { return nil }
        return try? await api.fetchDriveDetails(carID: carID, driveID: driveID)
    }

    private func makeAPI() -> HistoryAPIService? {
        let cfg = settings.makeAPIConfig()
        guard !cfg.baseURL.isEmpty else { return nil }
        return HistoryAPIService(config: cfg)
    }

    /// Build the battery degradation curve. Charges are the best signal: each charge gives a
    /// rated range that projects to a max range at 100%, and the energy added across a SoC
    /// delta gives a measured usable capacity (kWh). Falls back to drives when no charges.
    static func deriveBattery(charges: [ChargeRecord], drives: [DriveRecord], efficiency: Double?) -> [BatteryHealthPoint] {
        let cal = Calendar.current
        var buckets: [Date: (range: Double, cap: Double?)] = [:]

        for c in charges {
            guard let endB = c.endBattery, endB >= 50, let endR = c.endRangeKm, endR > 0 else { continue }
            let maxRange = endR / (Double(endB) / 100.0)
            var cap: Double?
            if let startB = c.startBattery, endB - startB >= 20, c.energyAddedKwh > 0 {
                cap = c.energyAddedKwh / (Double(endB - startB) / 100.0)   // measured kWh
            } else if let eff = efficiency, eff > 0 {
                cap = maxRange * eff
            }
            guard let month = cal.date(from: cal.dateComponents([.year, .month], from: c.startDate)) else { continue }
            if let existing = buckets[month] {
                buckets[month] = (max(existing.range, maxRange), cap ?? existing.cap)
            } else {
                buckets[month] = (maxRange, cap)
            }
        }

        if buckets.isEmpty {
            for d in drives {
                guard let level = d.startBattery, level > 20, let range = d.startRangeKm, range > 0 else { continue }
                let full = range / (Double(level) / 100.0)
                guard let month = cal.date(from: cal.dateComponents([.year, .month], from: d.startDate)) else { continue }
                let cap = efficiency.map { full * $0 }
                if let existing = buckets[month] {
                    buckets[month] = (max(existing.range, full), cap ?? existing.cap)
                } else {
                    buckets[month] = (full, cap)
                }
            }
        }

        return buckets
            .map { BatteryHealthPoint(date: $0.key, odometerKm: 0, maxRangeKm: $0.value.range, usableCapacityKwh: $0.value.cap) }
            .sorted { $0.date < $1.date }
    }
}
