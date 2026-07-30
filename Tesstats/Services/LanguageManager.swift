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
///
/// Strings are only half the picture: dates, weekday names, chart axis labels and numbers are
/// formatted from a `Locale`, not from the string table. `locale` mirrors the selected language
/// so those surfaces switch with it instead of staying on the device language (which used to
/// leave e.g. Spanish weekday labels inside an otherwise English app).
enum LanguageManager {
    nonisolated(unsafe) static var bundle: Bundle?
    /// Locale matching the selected language — `.current` while following the system.
    nonisolated(unsafe) static private(set) var locale: Locale = .current
    /// Calendar carrying `locale`, so month/weekday symbols follow the selected language.
    nonisolated(unsafe) static private(set) var calendar: Calendar = .current

    static func apply(_ code: String) {
        if !code.isEmpty, let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            bundle = Bundle(path: path)
        } else {
            bundle = nil
        }
        locale = resolvedLocale(code)
        var cal = Calendar.current
        cal.locale = locale
        calendar = cal
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    /// The locale a given language code maps to. Empty means "follow the system".
    static func resolvedLocale(_ code: String) -> Locale {
        code.isEmpty ? .current : Locale(identifier: code)
    }
}

/// Localize a string against the user-selected language (falls back to the system bundle).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: LanguageManager.bundle ?? .main)
}
