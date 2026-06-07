import Foundation

/// Self-contained, offline sample data so the full UI is reviewable without a live
/// TeslaMate server. Clearly surfaced as "Demo" in the UI — it never contacts a network.
struct DemoDataProvider: Sendable {

    static let car = CarSummary(id: 1, displayName: "Tesla", model: "3")

    static let carInfo = CarInfo(
        id: 1, name: "Tesla", model: "3", trimBadging: "Performance",
        vin: "5YJ3E1EA7KF000000", exteriorColor: "DeepBlue", wheelType: "Performance",
        efficiencyKwhPerKm: 0.152, totalDrives: 142, totalCharges: 44, totalUpdates: 5)

    static let batteryHealthSummary = BatteryHealthSummary(
        healthPercentage: 94.0,
        currentCapacityKwh: 73.2, maxCapacityKwh: 78.0,
        currentRangeKm: 451, maxRangeKm: 480, ratedEfficiency: 0.152)

    static func updates() -> [SoftwareUpdate] {
        let cal = Calendar.current
        let now = Date()
        let versions = ["2024.20.9", "2024.14.10", "2024.8.9", "2023.44.30.4", "2023.38.6"]
        return versions.enumerated().map { idx, v in
            let start = cal.date(byAdding: .day, value: -(idx * 47 + 5), to: now) ?? now
            return SoftwareUpdate(id: 3000 + idx, version: v, startDate: start,
                                  endDate: start.addingTimeInterval(35 * 60))
        }
    }

    // Madrid-ish coordinates for a believable map.
    private static let home = Coordinate(latitude: 40.4168, longitude: -3.7038)
    private static let work = Coordinate(latitude: 40.4530, longitude: -3.6883)
    private static let supercharger = Coordinate(latitude: 40.4900, longitude: -3.6900)
    private static let gym = Coordinate(latitude: 40.3900, longitude: -3.6700)

    static func baseState() -> VehicleState {
        var s = VehicleState(carID: 1)
        s.state = .charging
        s.since = Date().addingTimeInterval(-1800)
        s.healthy = true
        s.version = "2024.20.9"
        s.updateAvailable = false
        s.displayName = "Tesla"
        s.model = "3"
        s.trimBadging = "p"
        s.exteriorColor = "DeepBlue"
        s.wheelType = "Performance"
        s.batteryLevel = 64
        s.usableBatteryLevel = 63
        s.ratedBatteryRangeKm = 312
        s.estBatteryRangeKm = 286
        s.idealBatteryRangeKm = 340
        s.pluggedIn = true
        s.chargingState = .charging
        s.chargeEnergyAdded = 12.4
        s.chargeLimitSoc = 80
        s.chargePortDoorOpen = true
        s.chargerPower = 11
        s.chargerVoltage = 232
        s.chargerActualCurrent = 16
        s.chargerPhases = 3
        s.chargeCurrentRequest = 16
        s.chargeCurrentRequestMax = 16
        s.timeToFullCharge = 1.5
        s.isClimateOn = true
        s.insideTemp = 21.5
        s.outsideTemp = 14.0
        s.isPreconditioning = false
        s.speed = nil
        s.power = -11
        s.heading = 90
        s.elevation = 667
        s.shiftState = .park
        s.odometer = 28450
        s.latitude = home.latitude
        s.longitude = home.longitude
        s.geofence = "Home"
        s.locked = true
        s.sentryMode = true
        s.centerDisplayState = 0
        s.windowsOpen = false
        s.doorsOpen = false
        s.frunkOpen = false
        s.trunkOpen = false
        s.isUserPresent = false
        s.tpmsPressureFL = 2.9
        s.tpmsPressureFR = 2.9
        s.tpmsPressureRL = 2.8
        s.tpmsPressureRR = 2.1
        s.tpmsSoftWarningFL = false
        s.tpmsSoftWarningFR = false
        s.tpmsSoftWarningRL = false
        s.tpmsSoftWarningRR = true   // showcase the low-pressure warning UI
        s.lastUpdated = Date()
        return s
    }

    /// Live stream that nudges the charging session forward, then loops — to demonstrate
    /// real-time updates, charge completion notifications and the battery ring animating.
    func liveStream() -> AsyncStream<VehicleState> {
        AsyncStream { continuation in
            let task = Task {
                var s = Self.baseState()
                continuation.yield(s)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    if Task.isCancelled { break }
                    if s.chargingState == .charging, let level = s.batteryLevel, level < (s.chargeLimitSoc ?? 80) {
                        s.batteryLevel = level + 1
                        s.usableBatteryLevel = (s.usableBatteryLevel ?? level) + 1
                        s.ratedBatteryRangeKm = (s.ratedBatteryRangeKm ?? 0) + 4.6
                        s.estBatteryRangeKm = (s.estBatteryRangeKm ?? 0) + 4.2
                        s.chargeEnergyAdded = (s.chargeEnergyAdded ?? 0) + 0.7
                        s.timeToFullCharge = max(0, (s.timeToFullCharge ?? 0) - 0.05)
                        s.chargerPower = 11 + Double((level % 3)) * 0.3
                    } else if s.chargingState == .charging {
                        s.chargingState = .complete
                        s.state = .online
                        s.chargerPower = 0
                        s.power = 0
                        s.timeToFullCharge = 0
                    }
                    s.insideTemp = 21.5 + Double((Int(Date().timeIntervalSince1970) % 4)) * 0.1
                    s.lastUpdated = Date()
                    continuation.yield(s)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - History

    static func drives() -> [DriveRecord] {
        let cal = Calendar.current
        let now = Date()
        let routes: [(String, Coordinate, String, Coordinate, Double, Int, Double)] = [
            ("Home", home, "Work", work, 14.2, 26, 158),
            ("Work", work, "Home", home, 13.9, 24, 149),
            ("Home", home, "Gym", gym, 8.6, 17, 171),
            ("Gym", gym, "Home", home, 8.9, 19, 162),
            ("Home", home, "Supercharger Madrid", supercharger, 19.4, 28, 145),
            ("Supercharger Madrid", supercharger, "Home", home, 19.1, 30, 139),
            ("Home", home, "Work", work, 14.6, 31, 167),
            ("Work", work, "Gym", gym, 11.2, 22, 155),
            ("Gym", gym, "Work", work, 11.0, 21, 151),
            ("Home", home, "Work", work, 14.0, 25, 143),
            ("Work", work, "Home", home, 14.3, 27, 148),
            ("Home", home, "Gym", gym, 8.7, 18, 176)
        ]
        return routes.enumerated().map { idx, r in
            let (oName, oCoord, dName, dCoord, dist, dur, wh) = r
            let start = cal.date(byAdding: .hour, value: -idx * 22 - 3, to: now) ?? now
            return DriveRecord(
                id: 1000 + idx,
                startDate: start,
                endDate: start.addingTimeInterval(Double(dur) * 60),
                startAddress: oName, endAddress: dName,
                startGeofence: oName, endGeofence: dName,
                distanceKm: dist, durationMin: dur,
                startBattery: 78 - idx, endBattery: 70 - idx,
                startUsableBattery: 77 - idx, endUsableBattery: 69 - idx,
                startRangeKm: 300 - Double(idx), endRangeKm: 280 - Double(idx),
                avgSpeedKmh: dist / (Double(dur) / 60),
                maxSpeedKmh: 90 + Double(idx % 5) * 6,
                maxPowerKw: 120 + Double(idx % 4) * 18,
                minPowerKw: -(38 + Double(idx % 5) * 11),
                outsideTempAvg: 13 + Double(idx % 6),
                insideTempAvg: 21,
                energyConsumedKwh: wh * dist / 1000.0,
                startCoord: oCoord, endCoord: dCoord,
                path: interpolate(from: oCoord, to: dCoord, steps: 8, seed: idx),
                consumptionWhPerKm: wh,
                elevationProfile: elevation(steps: 12, seed: idx)
            )
        }
    }

    static func charges() -> [ChargeRecord] {
        let cal = Calendar.current
        let now = Date()
        let sessions: [(String, Coordinate, Double, Int, Int, Int, Double, Double, Bool)] = [
            ("Home", home, 34.2, 42, 80, 320, 4.10, 11, false),
            ("Supercharger Madrid", supercharger, 41.5, 18, 78, 32, 22.30, 168, true),
            ("Home", home, 28.0, 51, 85, 290, 3.36, 11, false),
            ("Home", home, 30.5, 48, 82, 300, 3.66, 11, false),
            ("Supercharger Madrid", supercharger, 38.9, 22, 75, 28, 20.10, 150, true),
            ("Home", home, 26.4, 55, 80, 270, 3.17, 7, false),
            ("Work", work, 18.2, 60, 78, 180, 5.40, 11, false),
            ("Home", home, 33.1, 44, 84, 310, 3.97, 11, false),
            ("Supercharger Madrid", supercharger, 45.0, 12, 80, 26, 24.75, 172, true),
            ("Home", home, 29.8, 49, 82, 295, 3.58, 11, false),
            ("Home", home, 31.2, 46, 83, 305, 3.74, 11, false),
            ("Gym", gym, 12.5, 64, 74, 90, 3.20, 7, false),
            ("Home", home, 27.6, 52, 80, 280, 3.31, 11, false),
            ("Supercharger Madrid", supercharger, 40.1, 20, 79, 30, 21.05, 158, true)
        ]
        return sessions.enumerated().map { idx, s in
            // (the 8th tuple field was a peak hint; average is derived like the real DTO does)
            let (name, coord, energy, startB, endB, dur, cost, _, fast) = s
            let start = cal.date(byAdding: .hour, value: -idx * 30 - 6, to: now) ?? now
            // Grid energy = battery energy ÷ efficiency (DC fast loses a bit less proportionally).
            let used = energy / (fast ? 0.94 : 0.89)
            return ChargeRecord(
                id: 2000 + idx,
                startDate: start,
                endDate: start.addingTimeInterval(Double(dur) * 60),
                address: name, geofence: name,
                energyAddedKwh: energy,
                startBattery: startB, endBattery: endB,
                startRangeKm: Double(startB) * 4.6, endRangeKm: Double(endB) * 4.6,
                durationMin: dur, cost: cost,
                energyUsedKwh: used,
                outsideTempAvg: 11 + Double(idx % 8),
                odometerKm: 28450 - Double(idx) * 120,
                avgPowerKw: dur > 0 ? energy / (Double(dur) / 60.0) : nil,
                coord: coord, isFastCharger: fast
            )
        }
    }

    /// Realistic per-point charge curve for a demo session, so the detail view shows the real
    /// (per-point) curve path rather than the modeled fallback. DC tapers with rising SoC.
    static func chargeCurve(for charge: ChargeRecord) -> [ChargeCurvePoint] {
        guard let start = charge.startBattery, let end = charge.endBattery, end > start else { return [] }
        let avg = charge.avgPowerKw ?? (charge.isFastCharger ? 80 : 7)
        let peak = charge.isFastCharger ? min(195, max(120, avg / 0.55)) : avg
        let base = charge.startDate
        let totalSecs = Double(charge.durationMin) * 60
        let steps = max(2, end - start)
        return (0...steps).map { i -> ChargeCurvePoint in
            let soc = start + Int(Double(i) / Double(steps) * Double(end - start))
            let kw = peak * curveFraction(soc: Double(soc), isFast: charge.isFastCharger)
            let jitter = 1 + sin(Double(i) * 1.3) * 0.03
            return ChargeCurvePoint(
                date: base.addingTimeInterval(totalSecs * Double(i) / Double(steps)),
                soc: soc, powerKw: (kw * jitter).rounded(), voltage: charge.isFastCharger ? 400 : 232, current: nil)
        }
    }

    private static func curveFraction(soc: Double, isFast: Bool) -> Double {
        if !isFast { return soc < 88 ? 1.0 : max(0.3, 1.0 - (soc - 88) / 12 * 0.7) }
        switch soc {
        case ..<20: return 0.65 + soc / 20 * 0.35
        case ..<55: return 1.0 - (soc - 20) / 35 * 0.20
        default:    return max(0.16, 0.80 - (soc - 55) / 45 * 0.64)
        }
    }

    static func batteryHealth() -> [BatteryHealthPoint] {
        let cal = Calendar.current
        let now = Date()
        var points: [BatteryHealthPoint] = []
        let originalRange = 491.0
        for month in stride(from: 17, through: 0, by: -1) {
            let date = cal.date(byAdding: .month, value: -month, to: now) ?? now
            let odo = 4000.0 + Double(17 - month) * 1450
            // gentle, realistic degradation curve (~6% over the period)
            let degradation = (1 - exp(-Double(17 - month) / 9.0)) * 0.062
            let maxRange = originalRange * (1 - degradation)
            points.append(BatteryHealthPoint(
                date: date,
                odometerKm: odo,
                maxRangeKm: maxRange,
                usableCapacityKwh: 57.5 * (1 - degradation)
            ))
        }
        return points
    }

    // MARK: - Helpers

    private static func interpolate(from: Coordinate, to: Coordinate, steps: Int, seed: Int) -> [Coordinate] {
        var path: [Coordinate] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let jitter = sin(Double(i) + Double(seed)) * 0.0016
            path.append(Coordinate(
                latitude: from.latitude + (to.latitude - from.latitude) * t + jitter,
                longitude: from.longitude + (to.longitude - from.longitude) * t + jitter * 0.7
            ))
        }
        return path
    }

    private static func elevation(steps: Int, seed: Int) -> [Double] {
        (0...steps).map { i -> Double in
            let x = Double(i)
            return 640 + sin(x / 2 + Double(seed)) * 30 + x * 2
        }
    }
}
