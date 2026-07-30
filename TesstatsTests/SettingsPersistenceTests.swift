import XCTest
@testable import Tesstats

/// `ServerConfig` decodes leniently field by field, so a property that is added but not wired
/// into that decoder silently reverts to its default on every launch. These pin the newer
/// display preferences and the per-screen layouts to a real save/reload cycle.
@MainActor
final class SettingsPersistenceTests: XCTestCase {
    func testSettingsStoreRoundTripsDisplayUnitsAndLayouts() throws {
        let suite = "tesstats.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        store.config.consumptionUnit = .kwhPer100km
        store.config.pressureIsPsi = true
        store.config.setLayout(SectionLayoutState(order: ["map", "list"], hidden: ["totals"]), for: .trips)
        store.save()

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.config.consumptionUnit, .kwhPer100km)
        XCTAssertEqual(reloaded.config.pressureIsPsi, true)
        XCTAssertEqual(reloaded.config.layout(for: .trips).order, ["map", "list"])
        XCTAssertEqual(reloaded.config.layout(for: .trips).hidden, ["totals"])
    }
}
