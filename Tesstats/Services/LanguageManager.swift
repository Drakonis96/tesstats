import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system = ""
    case spanish = "es"
    case english = "en"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: L("System")
        case .spanish: "Español"
        case .english: "English"
        }
    }
}

/// Runtime language override. Because the modern `String(localized:)` API bypasses the
/// old Bundle swizzle, every localized string in the app goes through `L(_:)`, which
/// resolves against the currently selected language bundle — so switching is instant.
enum LanguageManager {
    nonisolated(unsafe) static var bundle: Bundle?

    static func apply(_ code: String) {
        if !code.isEmpty, let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            bundle = Bundle(path: path)
        } else {
            bundle = nil
        }
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }
}

/// Localize a string against the user-selected language (falls back to the system bundle).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: LanguageManager.bundle ?? .main)
}
