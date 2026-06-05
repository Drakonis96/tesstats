import SwiftUI
import MapKit
import Charts

struct ChargeDetailView: View {
    let charge: ChargeRecord
    let units: Units

    @Environment(AppEnvironment.self) private var env
    @State private var realCurve: [ChargeCurvePoint] = []

    private var carID: Int { env.live.resolvedCarID ?? 1 }
    private var hasRealCurve: Bool { realCurve.count >= 2 }
    /// Real peak power from the per-point curve, when available.
    private var realPeakKw: Double? { hasRealCurve ? realCurve.map(\.powerKw).max() : nil }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Metrics.cardSpacing) {
                    headerCard
                    statsCard
                    if hasRealCurve {
                        realCurveCard
                    } else if !curvePoints.isEmpty {
                        curveCard
                    }
                    if let coord = charge.coord { mapCard(coord) }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L("Charge"))
        .navigationBarTitleDisplayModeInlineIfAvailable()
        .task(id: charge.id) { await loadRealCurve() }
    }

    // MARK: - Real curve (per-point kW vs SoC from the charge-detail endpoint)

    private func loadRealCurve() async {
        realCurve = []
        if env.settings.config.demoMode {
            withAnimation { realCurve = DemoDataProvider.chargeCurve(for: charge) }
            return
        }
        let cfg = env.settings.makeAPIConfig()
        guard !cfg.baseURL.isEmpty else { return }
        let api = HistoryAPIService(config: cfg)
        if let points = try? await api.fetchChargeCurve(carID: carID, chargeID: charge.id), points.count >= 2 {
            withAnimation { realCurve = points }
        }
    }

    private var socDomain: ClosedRange<Int> {
        let socs = realCurve.map(\.soc)
        let lo = max(0, (socs.min() ?? 0) - 2)
        let hi = min(100, (socs.max() ?? 100) + 2)
        return lo...hi
    }

    private var realCurveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L("Charge curve"), systemImage: "chart.xyaxis.line")
            Chart(realCurve) { p in
                AreaMark(x: .value("SoC", p.soc), y: .value("kW", p.powerKw))
                    .foregroundStyle(LinearGradient(colors: [Brand.crimson.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("SoC", p.soc), y: .value("kW", p.powerKw))
                    .foregroundStyle(Brand.crimson)
                    .interpolationMethod(.monotone)
                if let peak = realPeakKw, p.powerKw == peak {
                    PointMark(x: .value("SoC", p.soc), y: .value("kW", p.powerKw))
                        .foregroundStyle(Brand.crimsonBright)
                        .symbolSize(40)
                        .annotation(position: .top) {
                            Text(units.power(kw: peak, digits: 0)).font(.caption2.weight(.bold)).foregroundStyle(Brand.crimsonBright)
                        }
                }
            }
            .chartXScale(domain: socDomain)
            .chartXAxis { AxisMarks { v in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel { if let s = v.as(Int.self) { Text("\(s)%") } } } }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
            .frame(height: 180)
            Text(L("Real per-point data from TeslaMate · \(realCurve.count) samples. X: state of charge, Y: power."))
                .font(.caption2).foregroundStyle(Brand.textTertiary)
        }
        .card()
    }

    // MARK: - Modeled charge curve (fallback when the detail endpoint isn't available)

    private var curvePoints: [ChargeCurve.Point] {
        ChargeCurve.model(start: charge.startBattery, end: charge.endBattery,
                          isFast: charge.isFastCharger, avgPowerKw: charge.avgPowerKw)
    }

    private var curveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L("Charge curve"), systemImage: "chart.xyaxis.line")
            Chart(curvePoints) { p in
                AreaMark(x: .value("SoC", p.soc), y: .value("kW", p.kw))
                    .foregroundStyle(LinearGradient(colors: [Brand.crimson.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("SoC", p.soc), y: .value("kW", p.kw))
                    .foregroundStyle(Brand.crimson)
                    .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: 0...100)
            .chartXAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel { if let s = v.as(Int.self) { Text("\(s)%") } } } }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Brand.hairline); AxisValueLabel() } }
            .frame(height: 170)
            Text(L("Typical shape modeled from this session's average power — your server didn't return per-point data."))
                .font(.caption2).foregroundStyle(Brand.textTertiary)
        }
        .card()
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: charge.isFastCharger ? "bolt.car.fill" : "house.fill")
                .font(.title)
                .foregroundStyle(Brand.crimson)
            VStack(alignment: .leading, spacing: 4) {
                Text(charge.locationName).font(.title3.weight(.semibold)).foregroundStyle(Brand.textPrimary)
                Text(units.shortDateTime(charge.startDate)).font(.caption).foregroundStyle(Brand.textTertiary)
            }
            Spacer()
            Chip(text: charge.isFastCharger ? L("DC fast") : L("AC / home"),
                 color: charge.isFastCharger ? Brand.crimson : Brand.driving)
        }
        .card()
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Session"), systemImage: "bolt.fill")
            TileGrid(columns: 2) {
                StatTile(title: L("Energy added"), value: units.energy(kwh: charge.energyAddedKwh), tint: Brand.crimson)
                StatTile(title: L("Cost"), value: units.money(charge.cost))
                StatTile(title: realPeakKw != nil ? L("Peak power") : L("Avg power"),
                         value: units.power(kw: realPeakKw ?? charge.avgPowerKw),
                         tint: realPeakKw != nil ? Brand.crimson : Brand.textPrimary)
                StatTile(title: L("Duration"), value: units.duration(minutes: charge.durationMin))
            }
            Divider().overlay(Brand.hairline)
            KeyValueRow(label: L("State of charge"),
                        value: "\(charge.startBattery.map { "\($0)%" } ?? "—") → \(charge.endBattery.map { "\($0)%" } ?? "—")",
                        valueColor: Brand.crimson, systemImage: "battery.75percent")
        }
        .card()
    }

    private func mapCard(_ coord: Coordinate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L("Location"), systemImage: "mappin.and.ellipse")
            MiniMap(coordinate: coord)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.tightRadius))
        }
        .card()
    }
}

/// A *modeled* charge-power curve. TeslaMate keeps only session aggregates, so this renders
/// the characteristic taper shape (DC fast tapers with rising SoC; AC stays roughly flat)
/// scaled to the session's average power. Illustrative, clearly labeled as such in the UI.
enum ChargeCurve {
    struct Point: Identifiable, Sendable {
        var id: Double { soc }
        var soc: Double      // %
        var kw: Double
    }

    static func model(start: Int?, end: Int?, isFast: Bool, avgPowerKw: Double?) -> [Point] {
        guard let start, let end, end > start, end - start >= 2 else { return [] }
        let avg = max(1, avgPowerKw ?? (isFast ? 120 : 11))
        // The average of the modeled taper is ~0.7 of peak (DC) / ~0.95 (AC).
        let peak = isFast ? min(260, avg / 0.7) : avg / 0.95
        return stride(from: Double(start), through: Double(end), by: 2).map { soc in
            Point(soc: soc, kw: peak * fraction(of: soc, isFast: isFast))
        }
    }

    /// Fraction of peak power at a given SoC.
    private static func fraction(of soc: Double, isFast: Bool) -> Double {
        if !isFast {
            return soc < 88 ? 1.0 : max(0.3, 1.0 - (soc - 88) / 12 * 0.7)
        }
        switch soc {
        case ..<20: return 0.6 + soc / 20 * 0.4          // ramp to peak by ~20%
        case ..<55: return 1.0 - (soc - 20) / 35 * 0.18  // gentle hold 1.0 → 0.82
        default:    return max(0.18, 0.82 - (soc - 55) / 45 * 0.64)  // taper to ~18% by 100%
        }
    }
}
