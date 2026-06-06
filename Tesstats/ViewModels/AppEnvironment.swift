import Foundation
#if os(iOS)
import UIKit
#endif

/// Dependency-injection container. Built once at app launch and passed down the view tree.
@MainActor
@Observable
final class AppEnvironment {
    let settings: SettingsStore
    let notifications: NotificationEngine
    let cache: CacheStore
    let live: VehicleLiveService
    let history: HistoryViewModel
    let tester = ConnectionTester()

    init() {
        let settings = SettingsStore()
        LanguageManager.apply(settings.config.languageCode)   // apply saved language before any UI
        Brand.setAccent(settings.config.accentColorHex)       // apply saved accent before any UI
        let notifications = NotificationEngine()
        let cache = CacheStore()
        self.settings = settings
        self.notifications = notifications
        self.cache = cache
        self.live = VehicleLiveService(settings: settings, notifications: notifications, cache: cache)
        self.history = HistoryViewModel(settings: settings, cache: cache)
    }

    /// Start the live pipeline and ask for notification permission once configured.
    func bootstrap() {
        // Launch-time affordance for previews/UI verification: `TESSTATS_DEMO=1`.
        // In-memory only (not persisted) so it never overwrites a real saved configuration.
        let isPreview = ProcessInfo.processInfo.environment["TESSTATS_DEMO"] == "1"
        if isPreview, !settings.config.demoMode {
            settings.config = .demo
        }
        let injected = applyEnvOverridesIfPresent()
        guard settings.isConfigured else { return }
        live.start()
        if !isPreview && !injected {
            Task { await notifications.requestAuthorization() }
        }
        enablePushIfNeeded()
    }

    /// Wire up the optional push service: register for APNs and forward the token.
    func enablePushIfNeeded() {
        #if os(iOS)
        guard settings.config.pushEnabled, !settings.config.pushServiceURL.isEmpty else { return }
        let url = settings.config.pushServiceURL
        let secret = settings.pushSecret
        let trust = settings.trustConfig
        let basic = settings.basicAuth
        AppDelegate.onToken = { token in
            let service = PushService(baseURL: url, secret: secret, trust: trust, basicAuth: basic)
            Task { await service.register(token: token) }
        }
        Task { @MainActor in
            await notifications.requestAuthorization()
            UIApplication.shared.registerForRemoteNotifications()
        }
        #endif
    }

    /// Test affordance: inject a real server configuration from launch env vars so the live
    /// connection can be verified end-to-end without filling the form by hand. Returns true
    /// if env config was applied. Secrets go to the Keychain like the normal flow.
    private func applyEnvOverridesIfPresent() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["TESSTATS_MQTT_HOST"], !host.isEmpty else { return false }
        var c = ServerConfig()
        c.demoMode = false
        c.serverHost = host
        c.mqttHost = host
        c.mqttPort = Int(env["TESSTATS_MQTT_PORT"] ?? "443") ?? 443
        c.mqttTransport = (env["TESSTATS_MQTT_TRANSPORT"] == "tls") ? .tls : .websocket
        c.mqttWebsocketPath = env["TESSTATS_WS_PATH"] ?? "/"
        c.mqttUsername = env["TESSTATS_MQTT_USER"] ?? ""
        c.apiBaseURL = env["TESSTATS_API_URL"] ?? ""
        if let basicUser = env["TESSTATS_BASIC_USER"], !basicUser.isEmpty {
            c.usesBasicAuth = true
            c.basicAuthUsername = basicUser
        }
        settings.config = c
        settings.mqttPassword = env["TESSTATS_MQTT_PASS"] ?? ""
        settings.basicAuthPassword = env["TESSTATS_BASIC_PASS"] ?? ""
        if env["TESSTATS_PERSIST"] == "1" { settings.save() }
        return true
    }

    /// Persist edited configuration and reconnect with the new settings.
    func applyConfigChange() {
        settings.save()
        live.restart()
        Task { await notifications.requestAuthorization() }
        enablePushIfNeeded()
        if !settings.config.liveActivityEnabled { WidgetBridge.stopLiveActivities() }
    }

    func enableDemoMode() {
        settings.config = .demo
        settings.save()
        live.restart()
    }

    /// Clear only the offline cache (downloaded history + snapshots). Configuration is kept.
    func clearCache() {
        cache.clearAll()
        history.reset()
    }

    /// Full reset: wipe configuration, every Keychain secret, profiles, notifications and cache.
    /// Afterwards `isConfigured` is false, so the app returns to onboarding.
    func eraseAllData() {
        live.stop()
        settings.eraseAll()
        notifications.resetToDefaults()
        cache.clearAll()
        history.reset()
        WidgetBridge.clearAll()
        live.restart()
    }
}
