import Foundation

enum APIError: Error, LocalizedError {
    case notConfigured
    case badURL
    case unauthorized
    case http(Int)
    case insecure
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No history API (TeslaMateApi) URL configured."
        case .badURL: "The API URL is invalid."
        case .unauthorized: "Authentication failed (check Basic Auth credentials)."
        case .http(let code): "Server responded with HTTP \(code)."
        case .insecure: "Refusing to send credentials over an unencrypted connection."
        case .underlying(let m): m
        }
    }
}

/// URLSession delegate that applies the TLS trust policy (Let's Encrypt / custom CA / pinning).
private final class APITrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let trust: TrustConfig
    init(trust: TrustConfig) { self.trust = trust }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if TrustEvaluator.evaluate(serverTrust, config: trust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

/// Reads TeslaMate history (drives, charges, cars, live status) from a TeslaMateApi
/// instance over HTTPS. Basic Auth (reverse proxy) is sent as an explicit header, only
/// over TLS. Decoding is lenient so version differences degrade gracefully.
final class HistoryAPIService: Sendable {
    struct Config: Sendable {
        var baseURL: String
        var basicAuth: BasicAuth?
        var trust: TrustConfig
        var allowInsecure: Bool
    }

    private let config: Config
    private let session: URLSession

    init(config: Config) {
        self.config = config
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg,
                                  delegate: APITrustDelegate(trust: config.trust),
                                  delegateQueue: nil)
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func request(path: String) throws -> URLRequest {
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw APIError.notConfigured }
        let lower = base.lowercased()
        let isTLS = lower.hasPrefix("https://")
        if !isTLS && !config.allowInsecure { throw APIError.insecure }
        guard let url = URL(string: base + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let basic = config.basicAuth {
            // Never attach credentials to a plaintext request.
            if isTLS || config.allowInsecure {
                req.setValue(basic.headerValue, forHTTPHeaderField: "Authorization")
            }
        }
        return req
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let req = try request(path: path)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.underlying(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 401, 403: throw APIError.unauthorized
            default: throw APIError.http(http.statusCode)
            }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.underlying("Decoding failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Endpoints

    func fetchCars() async throws -> [CarSummary] {
        let env = try await fetch(CarsEnvelope.self, path: "/v1/cars")
        return (env.data?.cars ?? []).compactMap { $0.toDomain() }
    }

    func fetchCarInfo(carID: Int) async throws -> CarInfo? {
        let env = try await fetch(CarsEnvelope.self, path: "/v1/cars")
        return (env.data?.cars ?? []).compactMap { $0.toInfo() }.first { $0.id == carID }
    }

    private let pageLimit = 100   // TeslaMateApi returns up to 100 rows per page

    func fetchDrives(carID: Int) async throws -> [DriveRecord] {
        var all: [DriveDTO] = []
        var page = 1
        while page <= 50 {
            let env = try await fetch(DrivesEnvelope.self, path: "/v1/cars/\(carID)/drives?page=\(page)")
            let batch = env.data?.drives ?? []
            all.append(contentsOf: batch)
            if batch.count < pageLimit { break }
            page += 1
        }
        return all.enumerated().compactMap { $0.element.toDomain(index: $0.offset) }
            .sorted { $0.startDate > $1.startDate }
    }

    func fetchCharges(carID: Int) async throws -> [ChargeRecord] {
        var all: [ChargeDTO] = []
        var page = 1
        while page <= 50 {
            let env = try await fetch(ChargesEnvelope.self, path: "/v1/cars/\(carID)/charges?page=\(page)")
            let batch = env.data?.charges ?? []
            all.append(contentsOf: batch)
            if batch.count < pageLimit { break }
            page += 1
        }
        return all.enumerated().compactMap { $0.element.toDomain(index: $0.offset) }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Real per-point GPS trace for a single drive, used to draw the route from the actual
    /// recorded positions (no text geocoding). Returns an empty trace if the deployment doesn't
    /// expose `drive_details` or the drive has no positions.
    func fetchDriveDetails(carID: Int, driveID: Int) async throws -> DriveTrace {
        let env = try await fetch(DriveDetailsEnvelope.self, path: "/v1/cars/\(carID)/drives/\(driveID)")
        let points = env.data?.drive?.driveDetails ?? []
        let path = points.compactMap { $0.coordinate }
        // Elevation aligned 1:1 with the path; only meaningful when present on every point.
        let elevations = points.map { $0.elevation }
        let elevationProfile = elevations.allSatisfy { $0 != nil } ? elevations.compactMap { $0 } : []
        return DriveTrace(path: path, elevationProfile: elevationProfile)
    }

    /// Per-point charge curve (kW vs SoC) for a single session. Older / minimal TeslaMateApi
    /// deployments may not expose `charge_details`; callers fall back to the modeled curve.
    func fetchChargeCurve(carID: Int, chargeID: Int) async throws -> [ChargeCurvePoint] {
        let env = try await fetch(ChargeDetailEnvelope.self, path: "/v1/cars/\(carID)/charges/\(chargeID)")
        return (env.data?.charge?.chargeDetails ?? [])
            .compactMap { $0.toDomain() }
            .sorted { $0.date < $1.date }
    }
}
