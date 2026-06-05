import Foundation

// DTOs modeled after the real TeslaMateApi JSON (github.com/tobiasehlert/teslamateapi).
// Decoding uses `.convertFromSnakeCase`; fields are optional so partial/version-divergent
// responses degrade gracefully. The drive/charge payloads are nested (odometer_details,
// battery_details, range_rated, …), reflected here.

// MARK: - Cars

struct CarsEnvelope: Decodable {
    let data: CarsData?
    struct CarsData: Decodable { let cars: [CarDTO]? }
}

struct CarDTO: Decodable {
    let carId: Int?
    let name: String?
    let carDetails: CarDetails?
    let carExterior: CarExterior?
    let teslamateStats: Stats?

    struct CarDetails: Decodable {
        let model: String?
        let trimBadging: String?
        let vin: String?
        let efficiency: Double?
    }
    struct CarExterior: Decodable {
        let exteriorColor: String?
        let wheelType: String?
        let spoilerType: String?
    }
    struct Stats: Decodable {
        let totalCharges: Int?
        let totalDrives: Int?
        let totalUpdates: Int?
    }

    func toDomain() -> CarSummary? {
        guard let id = carId else { return nil }
        return CarSummary(id: id, displayName: name ?? "Car \(id)", model: carDetails?.model)
    }

    func toInfo() -> CarInfo? {
        guard let id = carId else { return nil }
        return CarInfo(
            id: id,
            name: name ?? "Car \(id)",
            model: carDetails?.model,
            trimBadging: carDetails?.trimBadging,
            vin: carDetails?.vin,
            exteriorColor: carExterior?.exteriorColor,
            wheelType: carExterior?.wheelType,
            efficiencyKwhPerKm: carDetails?.efficiency,
            totalDrives: teslamateStats?.totalDrives,
            totalCharges: teslamateStats?.totalCharges,
            totalUpdates: teslamateStats?.totalUpdates)
    }
}

// MARK: - Shared nested objects

struct OdometerDetails: Decodable {
    let odometerStart: Double?
    let odometerEnd: Double?
    let odometerDistance: Double?
}

struct BatteryLevels: Decodable {
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let startUsableBatteryLevel: Int?
    let endUsableBatteryLevel: Int?
}

struct RangeDetail: Decodable {
    let startRange: Double?
    let endRange: Double?
    let rangeDiff: Double?
}

// MARK: - Drives

struct DrivesEnvelope: Decodable {
    let data: DrivesData?
    struct DrivesData: Decodable { let drives: [DriveDTO]? }
}

struct DriveDTO: Decodable {
    let driveId: Int?
    let startDate: String?
    let endDate: String?
    let startAddress: String?
    let endAddress: String?
    let durationMin: Int?
    let speedMax: Double?
    let speedAvg: Double?
    let powerMax: Double?
    let outsideTempAvg: Double?
    let insideTempAvg: Double?
    let consumptionNet: Double?          // Wh/km
    let odometerDetails: OdometerDetails?
    let batteryDetails: BatteryLevels?
    let rangeRated: RangeDetail?
    let rangeIdeal: RangeDetail?

    func toDomain(index: Int) -> DriveRecord? {
        guard let start = startDate.flatMap(VehicleState.parseDate) else { return nil }
        return DriveRecord(
            id: driveId ?? index,
            startDate: start,
            endDate: endDate.flatMap(VehicleState.parseDate),
            startAddress: startAddress,
            endAddress: endAddress,
            startGeofence: nil,
            endGeofence: nil,
            distanceKm: odometerDetails?.odometerDistance ?? 0,
            durationMin: durationMin ?? 0,
            startBattery: batteryDetails?.startBatteryLevel,
            endBattery: batteryDetails?.endBatteryLevel,
            startRangeKm: rangeRated?.startRange,
            endRangeKm: rangeRated?.endRange,
            avgSpeedKmh: speedAvg,
            maxSpeedKmh: speedMax,
            maxPowerKw: powerMax,
            outsideTempAvg: outsideTempAvg,
            insideTempAvg: insideTempAvg,
            startCoord: nil,
            endCoord: nil,
            path: [],
            consumptionWhPerKm: consumptionNet,
            elevationProfile: []
        )
    }
}

// MARK: - Charges

struct ChargesEnvelope: Decodable {
    let data: ChargesData?
    struct ChargesData: Decodable { let charges: [ChargeDTO]? }
}

struct ChargeDTO: Decodable {
    let chargeId: Int?
    let startDate: String?
    let endDate: String?
    let address: String?
    let geofence: String?
    let chargeEnergyAdded: Double?
    let cost: Double?
    let durationMin: Int?
    let batteryDetails: BatteryLevels?
    let rangeRated: RangeDetail?
    let rangeIdeal: RangeDetail?
    let latitude: Double?
    let longitude: Double?

    func toDomain(index: Int) -> ChargeRecord? {
        guard let start = startDate.flatMap(VehicleState.parseDate) else { return nil }
        let energy = chargeEnergyAdded ?? 0
        let dur = durationMin ?? 0
        // No explicit peak-power field; estimate average power to classify AC vs DC.
        let avgPower = dur > 0 ? energy / (Double(dur) / 60.0) : 0
        return ChargeRecord(
            id: chargeId ?? index,
            startDate: start,
            endDate: endDate.flatMap(VehicleState.parseDate),
            address: address,
            geofence: geofence,
            energyAddedKwh: energy,
            startBattery: batteryDetails?.startBatteryLevel,
            endBattery: batteryDetails?.endBatteryLevel,
            startRangeKm: rangeRated?.startRange,
            endRangeKm: rangeRated?.endRange,
            durationMin: dur,
            cost: cost,
            avgPowerKw: avgPower > 0 ? avgPower : nil,
            coord: Coordinate(latitude: latitude, longitude: longitude),
            isFastCharger: avgPower > 25
        )
    }
}

// MARK: - Charge detail (per-point curve) — /v1/cars/{id}/charges/{chargeId}

struct ChargeDetailEnvelope: Decodable {
    let data: ChargeDetailData?
    struct ChargeDetailData: Decodable {
        let charge: ChargeWithDetails?
    }
    struct ChargeWithDetails: Decodable {
        let chargeDetails: [ChargeDetailPointDTO]?
    }
}

struct ChargeDetailPointDTO: Decodable {
    let date: String?
    let batteryLevel: Int?
    let chargerDetails: ChargerDetailDTO?

    struct ChargerDetailDTO: Decodable {
        let chargerPower: Int?       // kW (TeslaMate stores it as an integer)
        let chargerVoltage: Int?
        let chargerActualCurrent: Int?
    }

    func toDomain() -> ChargeCurvePoint? {
        guard let date = date.flatMap(VehicleState.parseDate),
              let soc = batteryLevel,
              let power = chargerDetails?.chargerPower else { return nil }
        return ChargeCurvePoint(date: date, soc: soc, powerKw: Double(power),
                                voltage: chargerDetails?.chargerVoltage,
                                current: chargerDetails?.chargerActualCurrent)
    }
}
