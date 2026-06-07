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
    /// Optional per-location price overrides (location name → €/kWh). Applied to sessions at
    /// that place when TeslaMate has no recorded cost, for more accurate cost estimates.
    var chargePricePerKwhByLocation: [String: Double] = [:]

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

    // MARK: Appearance
    /// Light or dark theme (dark by default).
    var appearance: AppAppearance = .dark
    /// Accent color as a 24-bit RGB hex string without `#` (default brand crimson).
    var accentColorHex: String = AccentPalette.defaultHex

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
        // The API field is a URL — be forgiving and default to https:// if no scheme is given
        // (unlike the MQTT host, which must be a bare hostname).
        if !s.isEmpty, !s.lowercased().hasPrefix("http://"), !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
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

// MARK: - Tolerant decoding

private extension KeyedDecodingContainer {
    /// Decode a value, falling back to `fallback` when the key is missing or its type mismatches.
    /// Keeps older persisted configs (written before a field existed) fully loadable.
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

extension ServerConfig {
    /// Custom decoder so that adding a new field never invalidates a user's saved configuration:
    /// every missing key resolves to its default instead of throwing `keyNotFound`. Defined in an
    /// extension to preserve the synthesized memberwise initializer used elsewhere.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        serverHost = c.lenient(.serverHost, serverHost)
        mqttHost = c.lenient(.mqttHost, mqttHost)
        mqttPort = c.lenient(.mqttPort, mqttPort)
        mqttTransport = c.lenient(.mqttTransport, mqttTransport)
        mqttWebsocketPath = c.lenient(.mqttWebsocketPath, mqttWebsocketPath)
        mqttUsername = c.lenient(.mqttUsername, mqttUsername)
        topicNamespace = c.lenient(.topicNamespace, topicNamespace)
        mqttClientID = c.lenient(.mqttClientID, mqttClientID)
        usesBasicAuth = c.lenient(.usesBasicAuth, usesBasicAuth)
        basicAuthUsername = c.lenient(.basicAuthUsername, basicAuthUsername)
        apiBaseURL = c.lenient(.apiBaseURL, apiBaseURL)
        trustCustomCertificate = c.lenient(.trustCustomCertificate, trustCustomCertificate)
        pinnedPublicKeySHA256 = c.lenient(.pinnedPublicKeySHA256, pinnedPublicKeySHA256)
        allowInsecureTransport = c.lenient(.allowInsecureTransport, allowInsecureTransport)
        units = c.lenient(.units, units)
        temperatureUnit = c.lenient(.temperatureUnit, temperatureUnit)
        rangeKind = c.lenient(.rangeKind, rangeKind)
        currencyCode = c.lenient(.currencyCode, currencyCode)
        fuelPricePerLiter = c.lenient(.fuelPricePerLiter, fuelPricePerLiter)
        fuelConsumptionLPer100km = c.lenient(.fuelConsumptionLPer100km, fuelConsumptionLPer100km)
        chargePricePerKwh = c.lenient(.chargePricePerKwh, chargePricePerKwh)
        chargePricePerKwhByLocation = c.lenient(.chargePricePerKwhByLocation, chargePricePerKwhByLocation)
        pushEnabled = c.lenient(.pushEnabled, pushEnabled)
        pushServiceURL = c.lenient(.pushServiceURL, pushServiceURL)
        liveActivityEnabled = c.lenient(.liveActivityEnabled, liveActivityEnabled)
        selectedCarID = (try? c.decodeIfPresent(Int.self, forKey: .selectedCarID)) ?? selectedCarID
        demoMode = c.lenient(.demoMode, demoMode)
        languageCode = c.lenient(.languageCode, languageCode)
        dashboardCardOrder = c.lenient(.dashboardCardOrder, dashboardCardOrder)
        appearance = c.lenient(.appearance, appearance)
        accentColorHex = c.lenient(.accentColorHex, accentColorHex)
    }
}
