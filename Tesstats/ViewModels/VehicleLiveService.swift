import Foundation

/// Orchestrates the live data path: chooses Demo or real MQTT, applies updates to the
/// observable state map, drives notifications on transitions, caches snapshots offline,
/// and reconnects with backoff. All observable mutation stays on the MainActor.
@MainActor
@Observable
final class VehicleLiveService {
    private(set) var states: [Int: VehicleState] = [:]
    private(set) var cars: [CarSummary] = []
    private(set) var status: ConnectionStatus = .notConfigured
    private(set) var lastError: String?

    private let settings: SettingsStore
    private let notifications: NotificationEngine
    private let cache: CacheStore

    private var client: MQTTClient?
    private var consumeTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var intentionalStop = false
    private var reconnectAttempt = 0
    private var connectionEpoch = 0          // invalidates stale connections/tasks
    private var lastCacheSave: [Int: Date] = [:]

    init(settings: SettingsStore, notifications: NotificationEngine, cache: CacheStore) {
        self.settings = settings
        self.notifications = notifications
        self.cache = cache
    }

    // MARK: - Resolved selection

    var resolvedCarID: Int? {
        if let id = settings.config.selectedCarID, states[id] != nil || cars.contains(where: { $0.id == id }) {
            return id
        }
        return cars.first?.id ?? states.keys.sorted().first
    }

    var currentState: VehicleState? { resolvedCarID.flatMap { states[$0] } }

    func selectCar(_ id: Int) {
        settings.config.selectedCarID = id
        settings.save()
    }

    // MARK: - Lifecycle

    func start() {
        teardownConnection()
        intentionalStop = false
        lastError = nil

        // Warm the UI from cache immediately.
        for snapshot in cache.loadAllSnapshots() {
            states[snapshot.carID] = snapshot
            upsertCar(from: snapshot)
        }

        let config = settings.config
        if config.demoMode {
            startDemo()
        } else if config.hasMQTTConfigured {
            startLive()
        } else {
            status = .notConfigured
        }
    }

    func stop() {
        intentionalStop = true
        teardownConnection()
        if status != .notConfigured { status = .disconnected }
    }

    func restart() {
        stop()
        start()
    }

    private func teardownConnection() {
        connectionEpoch &+= 1   // invalidate any in-flight consume/reconnect tasks
        consumeTask?.cancel(); consumeTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        let c = client
        client = nil
        if let c { Task { await c.disconnect() } }
    }

    // MARK: - Demo

    private func startDemo() {
        status = .demo
        if cars.isEmpty { cars = [DemoDataProvider.car] }
        if settings.config.selectedCarID == nil { settings.config.selectedCarID = DemoDataProvider.car.id }
        let provider = DemoDataProvider()
        consumeTask = Task { @MainActor [weak self] in
            for await snapshot in provider.liveStream() {
                guard let self, !self.intentionalStop else { break }
                self.commitFull(snapshot)
            }
        }
    }

    // MARK: - Live MQTT

    private func startLive() {
        // Invalidate and tear down any previous connection so only ONE is ever live.
        connectionEpoch &+= 1
        let epoch = connectionEpoch
        consumeTask?.cancel(); consumeTask = nil
        if let old = client { client = nil; Task { await old.disconnect() } }

        status = .connecting
        let mqttConfig = settings.makeMQTTConfig()
        let topicRoot = settings.config.topicRoot
        let client = MQTTClient(config: mqttConfig)
        self.client = client

        consumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await client.connect(topics: ["\(topicRoot)/+/#"])
                guard epoch == self.connectionEpoch else { await client.disconnect(); return }
                self.status = .connected
                self.reconnectAttempt = 0
                for await msg in client.publishes {
                    if self.intentionalStop || epoch != self.connectionEpoch { break }
                    self.handle(topic: msg.topic, payload: msg.payload, topicRoot: topicRoot)
                }
                self.handleDisconnect(epoch: epoch)
            } catch {
                if epoch == self.connectionEpoch {
                    self.lastError = error.localizedDescription
                    self.status = .failed(error.localizedDescription)
                }
                self.handleDisconnect(epoch: epoch)
            }
        }
    }

    private func handle(topic: String, payload: String, topicRoot: String) {
        let prefix = topicRoot + "/"
        guard topic.hasPrefix(prefix) else { return }
        let rest = String(topic.dropFirst(prefix.count))
        let parts = rest.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let carID = Int(parts[0]) else { return }
        applyMetric(carID: carID, metric: parts[1], value: payload)
    }

    private func handleDisconnect(epoch: Int) {
        // Ignore drops from a superseded connection — only the current one may reconnect.
        guard epoch == connectionEpoch, !intentionalStop else { return }
        if status.isLive { status = .disconnected }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !intentionalStop, !settings.config.demoMode, settings.config.hasMQTTConfigured else { return }
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let delay = min(30.0, pow(2.0, Double(min(reconnectAttempt, 5))))
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.intentionalStop else { return }
            self.startLive()
        }
    }

    // MARK: - State application

    private func applyMetric(carID: Int, metric: String, value: String) {
        var current = states[carID] ?? VehicleState(carID: carID)
        let previous = current
        current.apply(metric: metric, value: value)
        states[carID] = current
        upsertCar(from: current)
        notifications.process(previous: previous, current: current, carName: name(for: carID, hint: current.displayName))
        saveCacheThrottled(current)
        pushToWidgets(previous: previous, current: current)
    }

    private func commitFull(_ snapshot: VehicleState) {
        let previous = states[snapshot.carID]
        states[snapshot.carID] = snapshot
        upsertCar(from: snapshot)
        notifications.process(previous: previous, current: snapshot, carName: name(for: snapshot.carID, hint: snapshot.displayName))
        saveCacheThrottled(snapshot)
        pushToWidgets(previous: previous, current: snapshot)
    }

    /// Mirror the actively-selected car to the home/lock widgets and the charging Live Activity.
    private func pushToWidgets(previous: VehicleState?, current: VehicleState) {
        guard current.carID == resolvedCarID else { return }
        let chargingChanged = (previous?.isCharging ?? false) != current.isCharging
        WidgetBridge.update(state: current,
                            carName: name(for: current.carID, hint: current.displayName),
                            config: settings.config,
                            cache: cache,
                            force: chargingChanged)
    }

    private func upsertCar(from state: VehicleState) {
        let id = state.carID
        if let idx = cars.firstIndex(where: { $0.id == id }) {
            if let name = state.displayName, !name.isEmpty { cars[idx].displayName = name }
            if let model = state.model { cars[idx].model = model }
        } else {
            cars.append(CarSummary(id: id, displayName: state.displayName ?? "Car \(id)", model: state.model))
            cars.sort { $0.id < $1.id }
        }
        if settings.config.selectedCarID == nil {
            settings.config.selectedCarID = id
        }
    }

    private func name(for carID: Int, hint: String?) -> String {
        if let hint, !hint.isEmpty { return hint }
        return cars.first(where: { $0.id == carID })?.title ?? "Tesla"
    }

    private func saveCacheThrottled(_ state: VehicleState) {
        let now = Date()
        if let last = lastCacheSave[state.carID], now.timeIntervalSince(last) < 10 { return }
        lastCacheSave[state.carID] = now
        cache.saveSnapshot(state)
    }
}
