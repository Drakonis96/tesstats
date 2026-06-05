import Foundation

enum ConsumptionUnit: CaseIterable {
    case whPerKm, kwhPer100km
    var next: ConsumptionUnit {
        switch self {
        case .whPerKm: .kwhPer100km
        case .kwhPer100km: .whPerKm
        }
    }
}

/// Unit-aware, locale-friendly formatting driven by the user's preferences.
struct Units: Sendable {
    let distance: UnitsPreference
    let temp: TempUnit
    let range: RangeKind
    let currency: String
    let locale: Locale

    init(config: ServerConfig) {
        self.distance = config.units
        self.temp = config.temperatureUnit
        self.range = config.rangeKind
        self.currency = config.currencyCode
        self.locale = config.languageCode.isEmpty ? .current : Locale(identifier: config.languageCode)
    }

    private static let kmPerMile = 1.609344

    private func num(_ value: Double, _ fractionDigits: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
    }

    // Distance
    func distance(km: Double?, digits: Int = 1) -> String {
        guard let km else { return "—" }
        return distance == .imperial
            ? "\(num(km / Self.kmPerMile, digits)) mi"
            : "\(num(km, digits)) km"
    }

    func range(km: Double?) -> String { distance(km: km, digits: 0) }

    func speed(kmh: Double?) -> String {
        guard let kmh else { return "—" }
        return distance == .imperial
            ? "\(num(kmh / Self.kmPerMile, 0)) mph"
            : "\(num(kmh, 0)) km/h"
    }

    var speedUnit: String { distance == .imperial ? "mph" : "km/h" }
    var distanceUnit: String { distance == .imperial ? "mi" : "km" }

    func consumption(whPerKm: Double?) -> String {
        guard let whPerKm else { return "—" }
        return distance == .imperial
            ? "\(num(whPerKm * Self.kmPerMile, 0)) Wh/mi"
            : "\(num(whPerKm, 0)) Wh/km"
    }

    /// Consumption in a chosen unit (the value the user cycles through with a tap).
    func consumption(whPerKm: Double?, unit: ConsumptionUnit) -> String {
        guard let whPerKm else { return "—" }
        let perUnit = distance == .imperial ? whPerKm * Self.kmPerMile : whPerKm  // Wh per km or mi
        let d = distance == .imperial ? "mi" : "km"
        switch unit {
        case .whPerKm: return "\(num(perUnit, 0)) Wh/\(d)"
        case .kwhPer100km: return "\(num(perUnit / 10, 1)) kWh/100\(d)"
        }
    }

    // Temperature
    func temperature(c: Double?) -> String {
        guard let c else { return "—" }
        return temp == .fahrenheit
            ? "\(num(c * 9 / 5 + 32, 0))°F"
            : "\(num(c, 0))°C"
    }

    // Energy / power / electrical
    func energy(kwh: Double?, digits: Int = 1) -> String {
        guard let kwh else { return "—" }
        return "\(num(kwh, digits)) kWh"
    }
    func power(kw: Double?, digits: Int = 1) -> String {
        guard let kw else { return "—" }
        return "\(num(kw, digits)) kW"
    }
    func volts(_ v: Int?) -> String { v.map { "\($0) V" } ?? "—" }
    func amps(_ a: Int?) -> String { a.map { "\($0) A" } ?? "—" }
    func pressure(bar: Double?) -> String {
        guard let bar else { return "—" }
        return "\(num(bar, 1)) bar"
    }

    // Money
    func money(_ value: Double?) -> String {
        guard let value else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = locale
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "\(num(value, 2)) \(currency)"
    }

    // Durations
    func duration(minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    func duration(hours: Double?) -> String {
        guard let hours, hours > 0 else { return "—" }
        return duration(minutes: Int((hours * 60).rounded()))
    }

    // Dates
    func shortDateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter(); f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
    func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter(); f.locale = locale; f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
    func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
    func monthYear(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = locale; f.dateFormat = "MMM yy"
        return f.string(from: date)
    }
}
