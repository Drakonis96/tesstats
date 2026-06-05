import SwiftUI

/// Cross-platform keyboard hints. `keyboardType` is iOS/iPadOS-only, so these become
/// no-ops on macOS, keeping the shared SwiftUI code building everywhere.
enum PlatformKeyboard {
    case `default`, URL, numberPad, decimal, email
}

extension ToolbarItemPlacement {
    /// Leading toolbar slot that compiles on both iOS and macOS (`topBarLeading` is iOS-only).
    static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
    /// Trailing toolbar slot that compiles on both iOS and macOS.
    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

extension View {
    @ViewBuilder
    func textFieldKeyboard(_ kind: PlatformKeyboard) -> some View {
        #if os(iOS)
        switch kind {
        case .default: self
        case .URL: self.keyboardType(.URL).textInputAutocapitalization(.never)
        case .numberPad: self.keyboardType(.numberPad)
        case .decimal: self.keyboardType(.decimalPad)
        case .email: self.keyboardType(.emailAddress).textInputAutocapitalization(.never)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func keyboardTypeNumberPad() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func keyboardTypeDecimal() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// Inline navigation title on iOS (used by detail screens); no-op elsewhere.
    @ViewBuilder
    func navigationBarTitleDisplayModeInlineIfAvailable() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Make text fields in this subtree start the keyboard in lowercase (no auto-capitalization).
    /// Applied near the root so it propagates to every field, including sheets. No-op on macOS.
    @ViewBuilder
    func lowercaseKeyboardStart() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Bump up text on macOS — the iOS semantic font sizes are too small for a desktop display.
    @ViewBuilder
    func macTextScale() -> some View {
        #if os(macOS)
        self.dynamicTypeSize(.xLarge)
        #else
        self
        #endif
    }
}
