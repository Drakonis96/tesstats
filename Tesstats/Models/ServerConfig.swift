import Foundation

/// Identifies a vehicle discovered in TeslaMate (`teslamate/cars/<id>/display_name`).
struct CarSummary: Identifiable, Sendable, Codable, Hashable {
    let id: Int            // car_id
    var displayName: String
    var model: String?

    var title: String { displayName.isEmpty ? L("Car \(id)") : displayName }
}

/// Non-secret connection + preference configuration. Passwords are NEVER stored here —
/// they live in the Keychain (`KeychainStore`). This struct is persisted as JSON in
/// UserDefaults; secrets are referenced by account name only.
struct ServerConfig: Codable, Equatable, Sendable {

    // MARK: Server addressing (IP or domain / reverse proxy)
    var serverHost: String = ""          // informational base host (domain or IP)

    // MARK: MQTT
    var mqttHost: String = ""
    var mqttPort: Int = 8883
    var mqttTransport: MQTTTransport = .tls
    var mqttWebsocketPath: String = "/mqtt"
    var mqttUsername: String = ""
    var topicNamespace: String = ""      // optional topic prefix configured in TeslaMate
    var mqttClientID: String = "tesstats-ios"

    // MARK: Reverse proxy Basic Auth (applies to wss handshake and the REST API)
    var usesBasicAuth: Bool = false
    var basicAuthUsername: String = ""

    // MARK: History API (TeslaMateApi)
    var apiBaseURL: String = ""          // e.g. https://teslamate.example.com/api

    // MARK: TLS trust
    /// Trust a self-signed / custom-CA certificate that the user has explicitly accepted.
    var trustCustomCertificate: Bool = false
    /// Optional certificate pinning — base64 SHA-256 of the server cert's public key.
    var pinnedPublicKeySHA256: String = ""
    /// Explicit, user-confirmed opt-in to use a plaintext (non-TLS) channel. Default OFF.
    var allowInsecureTransport: Bool = false

    // MARK: Preferences
    var units: UnitsPreference = .metric
    var temperatureUnit: TempUnit = .celsius
    var rangeKind: RangeKind = .rated
    var currencyCode: String = "EUR"
    var fuelPricePerLiter: Double = 1.70
    var fuelConsumptionLPer100km: Double = 7.0
    /// Average electricity price you pay to charge, per kWh (used when TeslaMate has no cost).
    var chargePricePerKwh: Double = 0.15

    // MARK: Push (optional microservice for immediate alerts)
    var pushEnabled: Bool = false
    var pushServiceURL: String = ""        // e.g. https://push.example.com

    /// Show a Live Activity (Lock Screen + Dynamic Island) during a charging session.
    /// Off by default — it's an opt-in convenience.
    var liveActivityEnabled: Bool = false

    var selectedCarID: Int?
    var demoMode: Bool = false

    /// In-app language override: "" (system), "es", or "en".
    var languageCode: String = ""
    /// User-defined order of the Summary (dashboard) cards. Empty = default order.
    var dashboardCardOrder: [String] = []

    // MARK: Derived

    var mqttScheme: String { mqttTransport == .websocket ? "wss" : "mqtts" }

    var hasMQTTConfigured: Bool { !mqttHost.isEmpty }
    var hasAPIConfigured: Bool { !normalizedAPIBaseURL.isEmpty }

    /// Topic root, honoring an optional namespace prefix.
    var topicRoot: String {
        let ns = topicNamespace.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return ns.isEmpty ? "teslamate/cars" : "\(ns)/teslamate/cars"
    }

    var normalizedAPIBaseURL: String {
        var s = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// True when every configured channel is encrypted (or insecure has been explicitly allowed).
    var transportIsSecure: Bool {
        if allowInsecureTransport { return true } // user explicitly accepted the risk
        let apiSecure = normalizedAPIBaseURL.isEmpty || normalizedAPIBaseURL.lowercased().hasPrefix("https://")
        return apiSecure // MQTT path always uses TLS/wss in this app
    }

    static let demo: ServerConfig = {
        var c = ServerConfig()
        c.demoMode = true
        c.serverHost = "demo.teslamate.local"
        c.selectedCarID = 1
        return c
    }()
}
