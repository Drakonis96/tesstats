import Foundation

/// Registers this device's APNs token with the optional Tesstats push microservice,
/// so it can deliver immediate alerts (Sentry/security) when the app is closed.
/// No-op unless the user configures a push service URL in Settings.
final class PushService: Sendable {
    private let baseURL: String
    private let secret: String
    private let session: URLSession

    init(baseURL: String, secret: String, trust: TrustConfig, basicAuth: BasicAuth?) {
        self.baseURL = baseURL
        self.secret = secret
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: cfg, delegate: PushTrustDelegate(trust: trust), delegateQueue: nil)
        self.basicAuth = basicAuth
    }

    private let basicAuth: BasicAuth?

    func register(token: String) async {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty, base.lowercased().hasPrefix("https://"),
              let url = URL(string: base + "/register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let basicAuth { req.setValue(basicAuth.headerValue, forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token, "secret": secret])
        _ = try? await session.data(for: req)
    }
}

private final class PushTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let trust: TrustConfig
    init(trust: TrustConfig) { self.trust = trust }
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        if TrustEvaluator.evaluate(serverTrust, config: trust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
