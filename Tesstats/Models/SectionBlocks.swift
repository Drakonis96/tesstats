import Foundation

// The `allCases` order of each enum below is the out-of-the-box layout, ordered for someone
// who opens the app to answer "how is my car / how much did it cost", with the enthusiast
// blocks further down. Anyone can reorder or hide them from the section's ▦ button.

enum TripsBlock: String, SectionBlock {
    case filters, totals, list, map

    var title: String {
        switch self {
        case .filters: String(localized: "Search & filters")
        case .totals: String(localized: "Totals")
        case .list: String(localized: "Trip list")
        case .map: String(localized: "Route map")
        }
    }
    var icon: String {
        switch self {
        case .filters: "line.3.horizontal.decrease.circle"
        case .totals: "sum"
        case .list: "list.bullet"
        case .map: "map"
        }
    }
    var blurb: String {
        switch self {
        case .filters: String(localized: "Search, tag filter and date range.")
        case .totals: String(localized: "Energy, efficiency and trip count for the current filter.")
        case .list: String(localized: "Your drives, newest first, grouped by day.")
        case .map: String(localized: "All filtered drives drawn on one map.")
        }
    }
    var canHide: Bool { self != .list }
}

enum ChargingBlock: String, SectionBlock {
    case filters, totals, list, map, places

    var title: String {
        switch self {
        case .filters: String(localized: "Search & filters")
        case .totals: String(localized: "Totals")
        case .list: String(localized: "Session list")
        case .map: String(localized: "Charging map")
        case .places: String(localized: "Costs & places")
        }
    }
    var icon: String {
        switch self {
        case .filters: "line.3.horizontal.decrease.circle"
        case .totals: "sum"
        case .list: "list.bullet"
        case .map: "map"
        case .places: "eurosign"
        }
    }
    var blurb: String {
        switch self {
        case .filters: String(localized: "Search, charger type and date range.")
        case .totals: String(localized: "Energy, cost and AC/DC split for the current filter.")
        case .list: String(localized: "Your charging sessions, newest first.")
        case .map: String(localized: "Where you charged, on one map.")
        case .places: String(localized: "Shortcut to per-location costs and prices.")
        }
    }
    var canHide: Bool { self != .list }
}

enum BatteryBlock: String, SectionBlock {
    case current, timeline, health, degradation, efficiency, updates

    var title: String {
        switch self {
        case .current: String(localized: "Current")
        case .timeline: String(localized: "Battery over time")
        case .health: String(localized: "Battery health")
        case .degradation: String(localized: "Degradation")
        case .efficiency: String(localized: "Efficiency & totals")
        case .updates: String(localized: "Software updates")
        }
    }
    var icon: String {
        switch self {
        case .current: "battery.100percent"
        case .timeline: "waveform.path.ecg"
        case .health: "cross.case"
        case .degradation: "chart.line.downtrend.xyaxis"
        case .efficiency: "leaf.fill"
        case .updates: "cpu"
        }
    }
    var blurb: String {
        switch self {
        case .current: String(localized: "Charge, usable capacity and range right now.")
        case .timeline: String(localized: "State of charge over the last days.")
        case .health: String(localized: "Capacity now versus when new.")
        case .degradation: String(localized: "Max range trend across months.")
        case .efficiency: String(localized: "Lifetime efficiency and charging totals.")
        case .updates: String(localized: "Firmware versions installed over time.")
        }
    }
}

enum StatsBlock: String, SectionBlock {
    case comparison, cost, trends, charging, usage, heatmap, records, temperature, drain, eco

    var title: String {
        switch self {
        case .comparison: String(localized: "Month comparison")
        case .cost: String(localized: "Cost")
        case .trends: String(localized: "Trends over time")
        case .charging: String(localized: "Where you charge")
        case .usage: String(localized: "When you drive")
        case .heatmap: String(localized: "Activity")
        case .records: String(localized: "Records")
        case .temperature: String(localized: "Consumption vs temperature")
        case .drain: String(localized: "Phantom drain")
        case .eco: String(localized: "Environmental impact")
        }
    }
    var icon: String {
        switch self {
        case .comparison: "arrow.left.arrow.right"
        case .cost: "creditcard"
        case .trends: "chart.line.uptrend.xyaxis"
        case .charging: "bolt.badge.clock"
        case .usage: "clock.arrow.circlepath"
        case .heatmap: "square.grid.3x3"
        case .records: "trophy"
        case .temperature: "thermometer.medium"
        case .drain: "drop"
        case .eco: "leaf"
        }
    }
    var blurb: String {
        switch self {
        case .comparison: String(localized: "This month against last month.")
        case .cost: String(localized: "What charging costs you, per 100 km and projected.")
        case .trends: String(localized: "Distance, energy and cost month by month.")
        case .charging: String(localized: "Sessions and spend per location.")
        case .usage: String(localized: "Which weekdays and hours you drive.")
        case .heatmap: String(localized: "A calendar of driving activity.")
        case .records: String(localized: "Longest trip, top speed, biggest charge…")
        case .temperature: String(localized: "How cold weather changes consumption.")
        case .drain: String(localized: "Standby battery loss while parked.")
        case .eco: String(localized: "CO₂ and petrol avoided versus a combustion car.")
        }
    }
}
