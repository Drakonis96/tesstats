import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var isOnboarding = false
    var presentedAsSheet = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var mqttPassword = ""
    @State private var basicAuthPassword = ""
    @State private var pushSecret = ""
    @State private var diagnostics: ConnectionDiagnostics?
    @State private var testing = false
    @State private var showInsecureConfirm = false
    @State private var savedToast = false
    @State private var section: SettingsSection = .connection

    // Data / profiles / backup
    @State private var showExportSheet = false
    @State private var showEncryptedExport = false
    @State private var showRestoreImporter = false
    @State private var restoreError: String?
    @State private var newProfileName = ""
    @State private var showAddProfile = false
    // Encrypted-backup import
    @State private var showImportPassword = false
    @State private var importPassword = ""
    @State private var pendingEncrypted: EncryptedBackup?
    // Storage / reset
    @State private var showClearCacheConfirm = false
    @State private var showEraseAllConfirm = false

    var body: some View {
        @Bindable var settings = env.settings
        @Bindable var notifications = env.notifications

        VStack(spacing: 0) {
            if !isOnboarding { settingsHeader }
            SettingsTabBar(selection: $section)
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, isOnboarding ? 8 : 4)
                .padding(.bottom, 6)
            Form {
                switch section {
                case .connection:
                    serverSection($settings)
                    mqttSection($settings)
                    apiSection($settings)
                    basicAuthSection($settings)
                    securitySection($settings)
                    testSection
                case .preferences:
                    appearanceSection($settings)
                    preferencesSection($settings)
                    dashboardLayoutSection($settings)
                case .notifications:
                    notificationsSection($notifications)
                    tpmsSection($notifications)
                    quietHoursSection($notifications)
                    liveActivitySection($settings)
                    pushSection($settings)
                case .data:
                    profilesSection
                    backupSection
                    exportSection
                    storageSection
                case .vehicle:
                    vehiclesSection($settings)
                    demoSection($settings)
                    aboutSection
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onChange(of: notifications.prefs) { _, _ in env.notifications.persist() }
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle(L("Settings"))
        .tint(Brand.crimson)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isOnboarding ? L("Save & Connect") : L("Save")) { save() }
                    .fontWeight(.semibold)
            }
            if isOnboarding {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
        .onAppear {
            mqttPassword = env.settings.mqttPassword
            basicAuthPassword = env.settings.basicAuthPassword
            pushSecret = env.settings.pushSecret
        }
        .alert(L("Use an unencrypted connection?"), isPresented: $showInsecureConfirm) {
            Button(L("Cancel"), role: .cancel) { env.settings.config.allowInsecureTransport = false }
            Button(L("I understand the risk"), role: .destructive) {}
        } message: {
            Text(L("Credentials and data would travel in plain text. Only do this inside a trusted local network."))
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(drives: env.history.drives, charges: env.history.charges)
        }
        .sheet(isPresented: $showEncryptedExport) {
            EncryptedBackupSheet(makeBackup: { env.settings.makeBackup() })
        }
        .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: [.json]) { result in
            handleRestore(result)
        }
        .alert(L("Enter the backup password"), isPresented: $showImportPassword) {
            SecureField(L("Password"), text: $importPassword)
            Button(L("Restore")) { decryptAndRestore() }
            Button(L("Cancel"), role: .cancel) { importPassword = ""; pendingEncrypted = nil }
        } message: {
            Text(L("This backup is password-protected. Enter its password to restore."))
        }
        .alert(L("Save profile"), isPresented: $showAddProfile) {
            TextField(L("Name"), text: $newProfileName)
            Button(L("Save")) {
                let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { env.settings.saveCurrentAsProfile(name: name) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Save the current server configuration as a switchable profile."))
        }
        .alert(L("Clear cache?"), isPresented: $showClearCacheConfirm) {
            Button(L("Clear cache"), role: .destructive) {
                env.clearCache()
                withAnimation { savedToast = true }
                Task { try? await Task.sleep(for: .seconds(1.4)); withAnimation { savedToast = false } }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Removes downloaded drives, charges and snapshots saved offline. They'll be downloaded again next time."))
        }
        .alert(L("Delete all data?"), isPresented: $showEraseAllConfirm) {
            Button(L("Delete everything"), role: .destructive) {
                dismiss()   // close the sheet first, then wipe so the return to onboarding is clean
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.15))
                    env.eraseAllData()
                }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This erases your server, credentials, profiles, notifications and cache, and returns the app to the start. It can't be undone."))
        }
        .overlay(alignment: .bottom) { if savedToast { savedBanner } }
    }

    private func handleRestore(_ result: Result<URL, Error>) {
        restoreError = nil
        switch result {
        case .failure(let error):
            restoreError = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                restoreError = L("That file isn't a valid Tesstats backup.")
                return
            }
            switch BackupImport.inspect(data) {
            case .plain(let backup):
                applyRestore(backup)
            case .encrypted(let enc):
                pendingEncrypted = enc
                showImportPassword = true   // ask for the password before decrypting
            case .invalid:
                restoreError = L("That file isn't a valid Tesstats backup.")
            }
        }
    }

    private func decryptAndRestore() {
        guard let enc = pendingEncrypted else { return }
        do {
            let data = try BackupCrypto.decrypt(enc, password: importPassword)
            guard let backup = ConfigBackup.decode(data) else {
                restoreError = L("That file isn't a valid Tesstats backup.")
                importPassword = ""; pendingEncrypted = nil
                return
            }
            applyRestore(backup)
        } catch {
            restoreError = error.localizedDescription
        }
        importPassword = ""
        pendingEncrypted = nil
    }

    private func applyRestore(_ backup: ConfigBackup) {
        env.settings.restore(backup)
        env.applyConfigChange()
        reloadSecretFields()
        withAnimation { savedToast = true }
        Task { try? await Task.sleep(for: .seconds(1.4)); withAnimation { savedToast = false } }
    }

    // MARK: - Sections

    private var settingsHeader: some View {
        VStack(spacing: 10) {
            LogoMark(width: 150)
                .shadow(color: Brand.crimson.opacity(0.25), radius: 12)
            ConnectionPill(status: env.live.status)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func serverSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            LabeledTextField(title: L("Address (IP or domain)"),
                             text: settings.config.serverHost,
                             prompt: "teslamate.example.com",
                             keyboard: .URL)
        } header: {
            Text(L("Server"))
        } footer: {
            Text(L("Your reverse-proxy domain or the server's IP. Used as the default host."))
        }
    }

    private func mqttSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            LabeledTextField(title: L("MQTT host (name only)"), text: settings.config.mqttHost,
                             prompt: "teslamate.example.com", keyboard: .URL)
            HStack {
                Text(L("Port")).foregroundStyle(Brand.textSecondary)
                Spacer()
                TextField("8883", value: settings.config.mqttPort, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardTypeNumberPad()
                    .frame(width: 90)
            }
            Picker(L("Transport"), selection: settings.config.mqttTransport) {
                ForEach(MQTTTransport.allCases) { Text($0.label).tag($0) }
            }
            if settings.config.mqttTransport.wrappedValue == .websocket {
                LabeledTextField(title: L("WebSocket path"),
                                 text: settings.config.mqttWebsocketPath, prompt: "/mqtt")
            }
            LabeledTextField(title: L("Username"), text: settings.config.mqttUsername, prompt: "mqtt-user")
            SecureField(L("Password"), text: $mqttPassword)
            LabeledTextField(title: L("Topic namespace (optional)"),
                             text: settings.config.topicNamespace, prompt: "—")
        } header: {
            Text(L("MQTT (real-time)"))
        } footer: {
            Text(L("Always encrypted (mqtts/wss). Enter the host as a plain name — no https:// and no path (the app builds the URL). Read-only subscription."))
        }
    }

    private func basicAuthSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            Toggle(L("My server uses Basic Auth"), isOn: settings.config.usesBasicAuth)
                .tint(Brand.crimson)
            if settings.config.usesBasicAuth.wrappedValue {
                LabeledTextField(title: L("Username"), text: settings.config.basicAuthUsername, prompt: "user")
                SecureField(L("Password"), text: $basicAuthPassword)
            }
        } header: {
            Text(L("Reverse proxy Basic Auth"))
        } footer: {
            Text(L("Applied to the wss MQTT handshake and the history API. Sent only over TLS."))
        }
    }

    private func apiSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            LabeledTextField(title: L("TeslaMateApi base URL"),
                             text: settings.config.apiBaseURL,
                             prompt: "https://teslamate.example.com/api", keyboard: .URL)
        } header: {
            Text(L("History API (recommended)"))
        } footer: {
            Text(L("Optional but recommended. Here it IS a full URL — include https:// and the path (e.g. https://host/api). Provides drives, charges and battery history. Inherits Basic Auth."))
        }
    }

    private func securitySection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            Toggle(L("Trust a custom / self-signed certificate"),
                   isOn: settings.config.trustCustomCertificate)
                .tint(Brand.crimson)
            LabeledTextField(title: L("Pinned public-key SHA-256 (optional)"),
                             text: settings.config.pinnedPublicKeySHA256, prompt: "base64…")
            Toggle(isOn: Binding(
                get: { settings.config.allowInsecureTransport.wrappedValue },
                set: { newValue in
                    settings.config.allowInsecureTransport.wrappedValue = newValue
                    if newValue { showInsecureConfirm = true }
                })) {
                    Label(L("Allow unencrypted (LAN only)"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Brand.warning)
                }
                .tint(Brand.warning)
        } header: {
            Text(L("Security & certificates"))
        } footer: {
            Text(L("Let's Encrypt works out of the box. For self-hosted certs, trust your CA or pin its key. TLS is required by default."))
        }
    }

    private var testSection: some View {
        Section {
            Button {
                runTest()
            } label: {
                HStack {
                    Label(L("Test connection"), systemImage: "checkmark.shield")
                    Spacer()
                    if testing { ProgressView().tint(Brand.crimson) }
                }
            }
            .disabled(testing)

            if let diagnostics {
                DiagnosticsView(title: L("MQTT"), lines: diagnostics.mqtt)
                DiagnosticsView(title: L("History API"), lines: diagnostics.api)
            }
        } header: {
            Text(L("Diagnostics"))
        }
    }

    private func vehiclesSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            if env.live.cars.isEmpty {
                Text(L("No vehicles detected yet. Connect to discover them automatically."))
                    .font(.subheadline).foregroundStyle(Brand.textSecondary)
            } else {
                Picker(L("Active vehicle"), selection: Binding(
                    get: { env.live.resolvedCarID ?? env.live.cars.first?.id ?? 0 },
                    set: { env.live.selectCar($0) })) {
                        ForEach(env.live.cars) { car in
                            Text(car.title).tag(car.id)
                        }
                    }
            }
        } header: {
            Text(L("Vehicles"))
        }
    }

    private func appearanceSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            Picker(L("Theme"), selection: settings.config.appearance) {
                ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: settings.config.appearance.wrappedValue) { _, _ in env.settings.save() }

            VStack(alignment: .leading, spacing: 12) {
                Text(L("Accent color")).foregroundStyle(Brand.textSecondary)
                accentSwatches(settings)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L("Appearance"))
        } footer: {
            Text(L("Choose a light or dark theme and the accent color used across the app."))
        }
    }

    private func accentSwatches(_ settings: Bindable<SettingsStore>) -> some View {
        let selected = settings.config.accentColorHex.wrappedValue
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 14) {
            ForEach(AccentPalette.options) { opt in
                let isSelected = selected.caseInsensitiveCompare(opt.hex) == .orderedSame
                Button {
                    Brand.setAccent(opt.hex)                                   // update accent before the rebuild
                    settings.config.accentColorHex.wrappedValue = opt.hex      // triggers the root re-render
                    env.settings.save()
                } label: {
                    Circle()
                        .fill(opt.color)
                        .frame(width: 32, height: 32)
                        .overlay(Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .opacity(isSelected ? 1 : 0))
                        .overlay(Circle()
                            .strokeBorder(Brand.textPrimary, lineWidth: 2)
                            .padding(-3)
                            .opacity(isSelected ? 0.9 : 0))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(opt.name)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    private func preferencesSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            Picker(L("Language"), selection: Binding(
                get: { AppLanguage(rawValue: settings.config.languageCode.wrappedValue) ?? .system },
                set: { newValue in
                    settings.config.languageCode.wrappedValue = newValue.rawValue
                    env.settings.save()
                    LanguageManager.apply(newValue.rawValue)
                })) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
            Picker(L("Distance"), selection: settings.config.units) {
                ForEach(UnitsPreference.allCases) { Text($0.label).tag($0) }
            }
            Picker(L("Temperature"), selection: settings.config.temperatureUnit) {
                ForEach(TempUnit.allCases) { Text($0.label).tag($0) }
            }
            Picker(L("Range shown"), selection: settings.config.rangeKind) {
                ForEach(RangeKind.allCases) { Text($0.label).tag($0) }
            }
            LabeledTextField(title: L("Currency code"), text: settings.config.currencyCode, prompt: "EUR")
            HStack {
                Text(L("Fuel price / L")).foregroundStyle(Brand.textSecondary)
                Spacer()
                TextField("1.70", value: settings.config.fuelPricePerLiter, format: .number)
                    .multilineTextAlignment(.trailing).keyboardTypeDecimal().frame(width: 90)
            }
            HStack {
                Text(L("Comparison car L/100km")).foregroundStyle(Brand.textSecondary)
                Spacer()
                TextField("7.0", value: settings.config.fuelConsumptionLPer100km, format: .number)
                    .multilineTextAlignment(.trailing).keyboardTypeDecimal().frame(width: 90)
            }
            HStack {
                Text(L("Charge price / kWh")).foregroundStyle(Brand.textSecondary)
                Spacer()
                TextField("0.15", value: settings.config.chargePricePerKwh, format: .number)
                    .multilineTextAlignment(.trailing).keyboardTypeDecimal().frame(width: 90)
            }
        } header: {
            Text(L("Preferences"))
        } footer: {
            Text(L("Charge price is used to estimate cost and savings when TeslaMate has no recorded cost."))
        }
    }

    private func dashboardLayoutSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            ForEach(DashboardCard.resolved(settings.config.dashboardCardOrder.wrappedValue)) { card in
                HStack(spacing: 12) {
                    Image(systemName: card.icon).foregroundStyle(Brand.crimson).frame(width: 24)
                    Text(card.title).foregroundStyle(Brand.textPrimary)
                    Spacer()
                    Image(systemName: "line.3.horizontal").foregroundStyle(Brand.textTertiary)
                }
            }
            .onMove { from, to in
                var order = DashboardCard.resolved(env.settings.config.dashboardCardOrder)
                order.move(fromOffsets: from, toOffset: to)
                env.settings.config.dashboardCardOrder = order.map { $0.rawValue }
                env.settings.save()
            }
        } header: {
            HStack {
                Text(L("Home cards"))
                Spacer()
                #if os(iOS)
                EditButton().font(.caption.weight(.semibold)).tint(Brand.crimson)
                #endif
            }
        } footer: {
            Text(L("Drag to reorder the cards on the Summary screen. Cards only appear when their data is available (e.g. Charging while charging)."))
        }
    }

    private func notificationsSection(_ notifications: Bindable<NotificationEngine>) -> some View {
        Section {
            Toggle(L("Enable notifications"), isOn: notifications.prefs.enabled).tint(Brand.crimson)
            if notifications.prefs.enabled.wrappedValue {
                Toggle(L("Charging started"), isOn: notifications.prefs.chargeStarted).tint(Brand.crimson)
                Toggle(L("Charging complete"), isOn: notifications.prefs.chargeComplete).tint(Brand.crimson)
                Toggle(L("Charge limit reached"), isOn: notifications.prefs.chargeTargetReached).tint(Brand.crimson)
                Toggle(L("Left unplugged"), isOn: notifications.prefs.leftUnplugged).tint(Brand.crimson)
                Toggle(L("Plugged in, not charging"), isOn: notifications.prefs.pluggedNotCharging).tint(Brand.crimson)
                Toggle(L("Open doors / unlocked"), isOn: notifications.prefs.openingsOrUnlocked).tint(Brand.crimson)
                Toggle(L("Software updates"), isOn: notifications.prefs.softwareUpdate).tint(Brand.crimson)
                Toggle(L("Geofence enter / exit"), isOn: notifications.prefs.geofence).tint(Brand.crimson)
                Toggle(L("Possible Sentry (inferred)"), isOn: notifications.prefs.sentryInferred).tint(Brand.crimson)
                Stepper(value: notifications.prefs.lowBatteryThreshold, in: 5...60, step: 5) {
                    Toggle(L("Low battery below \(notifications.prefs.lowBatteryThreshold.wrappedValue)%"),
                           isOn: notifications.prefs.lowBattery).tint(Brand.crimson)
                }
            }
        } header: {
            Text(L("Notifications"))
        } footer: {
            Text(L("On-device local alerts. iOS can't reliably poll 24/7 in the background — for guaranteed alerts with the app closed, run the optional push microservice (see README)."))
        }
    }

    private func tpmsSection(_ notifications: Bindable<NotificationEngine>) -> some View {
        Section {
            Toggle(L("Low tire pressure alert"), isOn: notifications.prefs.tpmsLow).tint(Brand.crimson)
            if notifications.prefs.tpmsLow.wrappedValue {
                Picker(L("Unit"), selection: notifications.prefs.tpmsUnitIsPsi) {
                    Text("bar").tag(false)
                    Text("psi").tag(true)
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(L("Alert below")).foregroundStyle(Brand.textSecondary)
                    Spacer()
                    TextField("2.4", value: Binding(
                        get: { notifications.prefs.tpmsThresholdDisplay.wrappedValue },
                        set: { notifications.prefs.tpmsThresholdDisplay.wrappedValue = $0 }),
                        format: .number)
                        .multilineTextAlignment(.trailing).keyboardTypeDecimal().frame(width: 80)
                    Text(notifications.prefs.tpmsUnitIsPsi.wrappedValue ? "psi" : "bar")
                        .foregroundStyle(Brand.textTertiary)
                }
            }
        } header: {
            Text(L("Tire pressure"))
        } footer: {
            Text(L("Notifies when any wheel drops below your threshold. TPMS readings arrive only while the car is awake."))
        }
    }

    private func quietHoursSection(_ notifications: Bindable<NotificationEngine>) -> some View {
        Section {
            Toggle(L("Quiet hours"), isOn: notifications.prefs.quietHoursEnabled).tint(Brand.crimson)
            if notifications.prefs.quietHoursEnabled.wrappedValue {
                DatePicker(L("From"), selection: Binding(
                    get: { Self.date(fromMinutes: notifications.prefs.quietStartMinutes.wrappedValue) },
                    set: { notifications.prefs.quietStartMinutes.wrappedValue = Self.minutes(from: $0) }),
                    displayedComponents: .hourAndMinute)
                DatePicker(L("To"), selection: Binding(
                    get: { Self.date(fromMinutes: notifications.prefs.quietEndMinutes.wrappedValue) },
                    set: { notifications.prefs.quietEndMinutes.wrappedValue = Self.minutes(from: $0) }),
                    displayedComponents: .hourAndMinute)
            }
        } header: {
            Text(L("Do not disturb"))
        } footer: {
            Text(L("On-device alerts are silenced during this window (e.g. overnight)."))
        }
    }

    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: Data, profiles & backup

    private var profilesSection: some View {
        Section {
            if env.settings.profiles.isEmpty {
                Text(L("No saved profiles. Save your current server as a profile to switch between installs quickly."))
                    .font(.subheadline).foregroundStyle(Brand.textSecondary)
            } else {
                ForEach(env.settings.profiles) { profile in
                    Button {
                        env.settings.switchToProfile(profile.id)
                        env.applyConfigChange()
                        reloadSecretFields()
                    } label: {
                        HStack {
                            Image(systemName: env.settings.activeProfileID == profile.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(env.settings.activeProfileID == profile.id ? Brand.crimson : Brand.textTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).foregroundStyle(Brand.textPrimary)
                                Text(profile.config.serverHost.isEmpty ? profile.config.mqttHost : profile.config.serverHost)
                                    .font(.caption).foregroundStyle(Brand.textTertiary)
                            }
                            Spacer()
                        }
                    }
                    .tint(Brand.textPrimary)
                }
                .onDelete { idx in
                    idx.map { env.settings.profiles[$0].id }.forEach { env.settings.deleteProfile($0) }
                }
            }
            Button {
                newProfileName = env.settings.config.serverHost.isEmpty ? L("My server") : env.settings.config.serverHost
                showAddProfile = true
            } label: {
                Label(L("Save current as profile"), systemImage: "plus.circle")
            }
            .tint(Brand.crimson)
        } header: {
            Text(L("Server profiles"))
        } footer: {
            Text(L("Switch between multiple TeslaMate installations. Each profile keeps its own credentials in the Keychain."))
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                showEncryptedExport = true
            } label: {
                Label(L("Export encrypted backup"), systemImage: "lock.doc")
            }
            .tint(Brand.crimson)
            Button {
                showRestoreImporter = true
            } label: {
                Label(L("Restore from backup file"), systemImage: "square.and.arrow.down")
            }
            .tint(Brand.crimson)
            if let restoreError {
                Text(restoreError).font(.caption).foregroundStyle(Brand.danger)
            }
        } header: {
            Text(L("Backup & restore"))
        } footer: {
            Text(L("The backup holds your server settings and credentials, locked with a password only you know — AES-256 encrypted. Keep the password safe: it can't be recovered."))
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                showExportSheet = true
            } label: {
                Label(L("Export trips & charges"), systemImage: "tablecells")
            }
            .tint(Brand.crimson)
        } header: {
            Text(L("Export data"))
        } footer: {
            Text(L("Share your drives and charging sessions as CSV, JSON or GPX."))
        }
    }

    private var storageSection: some View {
        Section {
            Button {
                showClearCacheConfirm = true
            } label: {
                HStack {
                    Label(L("Clear cache"), systemImage: "internaldrive")
                    Spacer()
                    Text(cacheSizeText).font(.caption).foregroundStyle(Brand.textTertiary)
                }
            }
            .tint(Brand.crimson)
            Button(role: .destructive) {
                showEraseAllConfirm = true
            } label: {
                Label(L("Delete all data"), systemImage: "trash")
            }
        } header: {
            Text(L("Storage & reset"))
        } footer: {
            Text(L("“Clear cache” removes downloaded history saved offline. “Delete all data” also erases your server, credentials, profiles and preferences."))
        }
    }

    private var cacheSizeText: String {
        let bytes = env.cache.sizeBytes()
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func reloadSecretFields() {
        mqttPassword = env.settings.mqttPassword
        basicAuthPassword = env.settings.basicAuthPassword
        pushSecret = env.settings.pushSecret
    }

    private func liveActivitySection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            Toggle(isOn: settings.config.liveActivityEnabled) {
                Label(L("Charging Live Activity"), systemImage: "bolt.fill")
            }.tint(Brand.crimson)
        } header: {
            Text(L("Live Activity"))
        } footer: {
            Text(L("Shows live charging progress on the Lock Screen and Dynamic Island while the car is plugged in. Off by default."))
        }
    }

    private func pushSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            Toggle(isOn: settings.config.pushEnabled) {
                Label(L("Immediate push (app closed)"), systemImage: "bolt.horizontal.circle")
            }.tint(Brand.crimson)
            if settings.config.pushEnabled.wrappedValue {
                LabeledTextField(title: L("Push service URL"),
                                 text: settings.config.pushServiceURL,
                                 prompt: "https://push.example.com", keyboard: .URL)
                SecureField(L("Shared secret"), text: $pushSecret)
            }
        } header: {
            Text(L("Immediate push (optional)"))
        } footer: {
            Text(L("For guaranteed alerts (Sentry/security) with the app closed, run the optional push microservice (see /server). Requires an Apple Push key. Without it, alerts are local-only while the app runs."))
        }
    }

    private func demoSection(_ settings: Bindable<SettingsStore>) -> some View {
        Section {
            Toggle(isOn: settings.config.demoMode) {
                Label(L("Demo mode"), systemImage: "play.circle")
            }.tint(Brand.crimson)
        } footer: {
            Text(L("Explore the full UI with realistic sample data. No network is contacted."))
        }
    }

    private var aboutSection: some View {
        Section {
            KeyValueRow(label: L("Version"), value: appVersion)
            VStack(alignment: .leading, spacing: 8) {
                aboutNote("eye", L("Read-only. Tesstats never sends commands to your car."))
                aboutNote("video.slash", L("Sentry is inferred from the screen banner; clips live on the car's USB and aren't available via TeslaMate."))
                aboutNote("lock", L("TLS only · credentials in Keychain · no telemetry or trackers."))
            }
            .padding(.vertical, 4)
        } header: {
            Text(L("About"))
        }
    }

    private func aboutNote(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.caption).foregroundStyle(Brand.crimson).frame(width: 18)
            Text(text).font(.caption).foregroundStyle(Brand.textSecondary)
        }
    }

    private var savedBanner: some View {
        Label(L("Saved"), systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Brand.online, in: Capsule())
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - Actions

    private func commitSecrets() {
        env.settings.mqttPassword = mqttPassword
        env.settings.basicAuthPassword = basicAuthPassword
        env.settings.pushSecret = pushSecret
    }

    private func save() {
        commitSecrets()
        env.notifications.persist()
        if env.settings.activeProfileID != nil { env.settings.updateActiveProfile() }
        env.applyConfigChange()
        if isOnboarding || presentedAsSheet {
            dismiss()   // Save also closes the sheet — no separate Done button needed.
        } else {
            withAnimation { savedToast = true }
            Task { try? await Task.sleep(for: .seconds(1.4)); withAnimation { savedToast = false } }
        }
    }

    private func runTest() {
        commitSecrets()
        env.settings.save()
        testing = true
        diagnostics = nil
        Task {
            let mqtt = await env.tester.testMQTT(config: env.settings.makeMQTTConfig(),
                                                 topicRoot: env.settings.config.topicRoot)
            let api = await env.tester.testAPI(config: env.settings.makeAPIConfig())
            diagnostics = ConnectionDiagnostics(mqtt: mqtt, api: api, finished: true)
            testing = false
        }
    }
}

// MARK: - Small helpers

private struct LabeledTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var keyboard: PlatformKeyboard = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(Brand.textTertiary)
            TextField(prompt, text: $text)
                .textFieldKeyboard(keyboard)
                .autocorrectionDisabled()
        }
    }
}

private struct DiagnosticsView: View {
    let title: String
    let lines: [DiagLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Brand.textTertiary)
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: line.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(line.ok ? Brand.online : Brand.danger)
                        .font(.caption)
                    Text(line.message).font(.caption).foregroundStyle(Brand.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings sections (icon sub-tabs)

enum SettingsSection: String, CaseIterable, Identifiable {
    case connection, preferences, notifications, data, vehicle
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .connection: "antenna.radiowaves.left.and.right"
        case .preferences: "slider.horizontal.3"
        case .notifications: "bell.badge"
        case .data: "square.and.arrow.up.on.square"
        case .vehicle: "car"
        }
    }
    var shortLabel: String {
        switch self {
        case .connection: L("Server")
        case .preferences: L("Prefs")
        case .notifications: L("Alerts")
        case .data: L("Data")
        case .vehicle: L("Info")
        }
    }
}

/// Icon sub-tab bar — icon only, with a short label that appears only when selected.
struct SettingsTabBar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SettingsSection.allCases) { sec in
                let active = sec == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = sec }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sec.icon).font(.subheadline.weight(.semibold))
                        if active {
                            Text(sec.shortLabel).font(.caption.weight(.semibold)).fixedSize()
                        }
                    }
                    .frame(maxWidth: active ? .infinity : nil)
                    .padding(.vertical, 10)
                    .padding(.horizontal, active ? 12 : 13)
                    .foregroundStyle(active ? Color.white : Brand.textSecondary)
                    .background(active ? Brand.crimson : Brand.elevatedSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
