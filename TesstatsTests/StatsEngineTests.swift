import XCTest
@testable import Tesstats

final class StatsEngineTests: XCTestCase {

    func testCalendarHeatmapAggregatesDistanceAndDriveCount() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))!
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let drives = [
            makeDrive(id: 1, start: today.addingTimeInterval(9 * 3600), distance: 12),
            makeDrive(id: 2, start: today.addingTimeInterval(18 * 3600), distance: 8),
            makeDrive(id: 3, start: yesterday.addingTimeInterval(8 * 3600), distance: 30),
            // Outside the window — must be ignored.
            makeDrive(id: 4, start: cal.date(byAdding: .day, value: -400, to: today)!, distance: 99)
        ]

        let days = StatsEngine.calendarHeatmap(drives, weeks: 18, now: now)

        XCTAssertEqual(days.count, 18 * 7)
        let todayCell = days.last
        XCTAssertEqual(todayCell?.day, today)
        XCTAssertEqual(todayCell?.driveCount, 2)
        XCTAssertEqual(todayCell?.distanceKm ?? 0, 20, accuracy: 0.001)

        let yesterdayCell = days[days.count - 2]
        XCTAssertEqual(yesterdayCell.driveCount, 1)
        XCTAssertEqual(yesterdayCell.distanceKm, 30, accuracy: 0.001)

        // Every cell inside the window exists, including empty ones.
        XCTAssertTrue(days.contains { $0.driveCount == 0 && $0.distanceKm == 0 })
        // The out-of-window drive contributed nowhere.
        XCTAssertEqual(days.reduce(0) { $0 + $1.distanceKm }, 50, accuracy: 0.001)
    }

    private func makeDrive(id: Int, start: Date, distance: Double) -> DriveRecord {
        DriveRecord(
            id: id,
            startDate: start,
            endDate: start.addingTimeInterval(1200),
            startAddress: "A", endAddress: "B",
            startGeofence: "A", endGeofence: "B",
            distanceKm: distance, durationMin: 20,
            startBattery: 80, endBattery: 75,
            startUsableBattery: nil, endUsableBattery: nil,
            startRangeKm: 320, endRangeKm: 300,
            avgSpeedKmh: 50, maxSpeedKmh: 80,
            maxPowerKw: nil, minPowerKw: nil,
            outsideTempAvg: 20, insideTempAvg: 22,
            energyConsumedKwh: distance * 0.15,
            startCoord: nil, endCoord: nil,
            path: [],
            consumptionWhPerKm: 150,
            elevationProfile: []
        )
    }
}
