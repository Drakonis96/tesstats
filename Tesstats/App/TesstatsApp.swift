import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct TesstatsApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var macDelegate
    #endif
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootContainerView()
                .environment(env)
                .preferredColorScheme(.dark)
                .tint(Brand.crimson)
                .lowercaseKeyboardStart()
                .macTextScale()
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 760)
        #endif

        #if os(macOS)
        // Menu-bar presence: Tesstats keeps running in the background (live MQTT + notifications)
        // even after the window is closed, with battery/charge status always in the menu bar.
        MenuBarExtra {
            MenuBarContent(env: env)
        } label: {
            MenuBarLabel(env: env)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(iOS)
/// Minimal app delegate to receive the APNs device token for the optional push service.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by AppEnvironment; called when iOS hands us a device token.
    nonisolated(unsafe) static var onToken: ((String) -> Void)?

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        AppDelegate.onToken?(token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Remote notifications unavailable: \(error.localizedDescription)")
    }
}
#endif

/// Decides between onboarding and the main tab UI, and shows a brief branded splash.
struct RootContainerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()

            Group {
                if env.settings.isConfigured {
                    #if os(macOS)
                    MacRootView()
                    #else
                    RootTabView()
                    #endif
                } else {
                    OnboardingView()
                }
            }
            .id(env.settings.config.languageCode)   // rebuild the tree on language change
            .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            env.bootstrap()
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeOut(duration: 0.5)) { showSplash = false }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS suspends background work, so reconnect on foreground and release on background.
            // On macOS the app keeps running in the menu bar, so the live connection stays up.
            #if os(iOS)
            switch phase {
            case .active where env.settings.isConfigured:
                env.live.start()
            case .background:
                env.live.stop()
            default:
                break
            }
            #endif
        }
    }
}

private struct SplashView: View {
    @State private var glow = false
    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 18) {
                LogoMark(width: 220)
                    .shadow(color: Brand.crimson.opacity(glow ? 0.7 : 0.2), radius: glow ? 26 : 8)
                    .scaleEffect(glow ? 1.0 : 0.96)
                Text("Tesstats")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Brand.textPrimary)
                    .tracking(2)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}
