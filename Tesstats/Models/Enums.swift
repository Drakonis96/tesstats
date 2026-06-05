import SwiftUI

// MARK: - Vehicle state (`state` topic)

enum CarState: String, Sendable, CaseIterable, Codable {
    case online, asleep, offline, charging, driving, updating, suspended, start, unknown

    init(raw: String) {
        self = CarState(rawValue: raw.lowercased()) ?? .unknown
    }

    var label: String {
        switch self {
        case .online: L("Online")
        case .asleep: L("Asleep")
        case .offline: L("Offline")
        case .charging: L("Charging")
        case .driving: L("Driving")
        case .updating: L("Updating")
        case .suspended: L("Suspended")
        case .start: L("Waking")
        case .unknown: L("Unknown")
        }
    }

    var color: Color {
        switch self {
        case .online: Brand.online
        case .charging: Brand.charging
        case .driving: Brand.driving
        case .asleep, .suspended: Brand.asleep
        case .updating, .start: Brand.warning
        case .offline, .unknown: Brand.offline
        }
    }

    var symbol: String {
        switch self {
        case .online: "checkmark.circle.fill"
        case .charging: "bolt.fill"
        case .driving: "steeringwheel"
        case .asleep, .suspended: "moon.zzz.fill"
        case .updating: "arrow.down.circle.fill"
        case .start: "sunrise.fill"
        case .offline, .unknown: "wifi.slash"
        }
    }
}

// MARK: - Charging (`charging_state` topic)

enum ChargingState: String, Sendable, Codable {
    case charging = "Charging"
    case complete = "Complete"
    case stopped = "Stopped"
    case disconnected = "Disconnected"
    case noPower = "NoPower"
    case starting = "Starting"
    case unknown

    init(raw: String) {
        self = ChargingState(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .charging: L("Charging")
        case .complete: L("Complete")
        case .stopped: L("Stopped")
        case .disconnected: L("Disconnected")
        case .noPower: L("No power")
        case .starting: L("Starting")
        case .unknown: L("—")
        }
    }
}

// MARK: - Shift state (`shift_state` topic)

enum ShiftState: String, Sendable, Codable {
    case park = "P"
    case reverse = "R"
    case neutral = "N"
    case drive = "D"
    case unknown

    init(raw: String) {
        let v = raw.uppercased()
        self = ShiftState(rawValue: v) ?? .unknown
    }

    var label: String {
        switch self {
        case .park: L("Park")
        case .reverse: L("Reverse")
        case .neutral: L("Neutral")
        case .drive: L("Drive")
        case .unknown: "—"
        }
    }
}

// MARK: - Connection status (UI surface)

enum ConnectionStatus: Equatable, Sendable {
    case notConfigured
    case disconnected
    case connecting
    case connected
    case demo
    case failed(String)

    var label: String {
        switch self {
        case .notConfigured: L("Not configured")
        case .disconnected: L("Disconnected")
        case .connecting: L("Connecting…")
        case .connected: L("Live")
        case .demo: L("Demo")
        case .failed: L("Connection error")
        }
    }

    var color: Color {
        switch self {
        case .connected: Brand.online
        case .connecting: Brand.warning
        case .demo: Brand.driving
        case .failed: Brand.danger
        case .notConfigured, .disconnected: Brand.offline
        }
    }

    var isLive: Bool { self == .connected }
}

// MARK: - Preferences

enum MQTTTransport: String, Codable, Sendable, CaseIterable, Identifiable {
    case tls          // mqtts, typically 8883
    case websocket    // wss, behind reverse proxy with optional Basic Auth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tls: L("MQTT over TLS (mqtts)")
        case .websocket: L("WebSocket Secure (wss)")
        }
    }
}

enum UnitsPreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var label: String {
        switch self {
        case .metric: L("Kilometers")
        case .imperial: L("Miles")
        }
    }
}

enum TempUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }
}

enum RangeKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case rated, estimated, ideal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rated: L("Rated")
        case .estimated: L("Estimated")
        case .ideal: L("Ideal")
        }
    }
}
