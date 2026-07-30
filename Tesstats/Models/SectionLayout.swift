import Foundation

/// A block the user can move or hide inside a section.
///
/// Every scrollable screen is built from these, so one editor and one persistence format
/// cover Summary, Trips, Charging, Battery and Stats.
protocol SectionBlock: RawRepresentable<String>, CaseIterable, Identifiable, Hashable, Sendable {
    var title: String { get }
    var icon: String { get }
    /// A one-line "what is this for", shown in the layout editor.
    var blurb: String { get }
    /// A section's main content (the trip list, the charge list) can be moved but not hidden —
    /// hiding it would leave the screen with nothing to show.
    ///
    /// Declared here, not only in the extension below: the editor is generic over
    /// `SectionBlock`, and a member that exists solely in a protocol extension is dispatched
    /// statically, so a conformer's override would be ignored there.
    var canHide: Bool { get }
}

extension SectionBlock {
    var id: String { rawValue }
    var canHide: Bool { true }
}

/// The screens whose layout the user can rearrange.
enum SectionID: String, CaseIterable, Sendable {
    case summary, trips, charging, battery, stats

    var title: String {
        switch self {
        case .summary: String(localized: "Summary")
        case .trips: String(localized: "Trips")
        case .charging: String(localized: "Charging")
        case .battery: String(localized: "Battery")
        case .stats: String(localized: "Stats")
        }
    }
}

/// Persisted arrangement of one section. Empty means "defaults".
struct SectionLayoutState: Codable, Equatable, Sendable {
    var order: [String] = []
    var hidden: [String] = []

    var isDefault: Bool { order.isEmpty && hidden.isEmpty }
}

enum SectionLayout {
    /// Every block in user order. Blocks added by a later app version are unknown to a saved
    /// order, so they are appended rather than silently dropped.
    static func resolved<B: SectionBlock>(_ type: B.Type, layout: SectionLayoutState) -> [B] {
        let saved = layout.order.compactMap { B(rawValue: $0) }
        guard !saved.isEmpty else { return Array(B.allCases) }
        let missing = B.allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    /// The blocks actually drawn, in user order.
    static func visible<B: SectionBlock>(_ type: B.Type, layout: SectionLayoutState) -> [B] {
        let hidden = Set(layout.hidden)
        return resolved(type, layout: layout).filter { !hidden.contains($0.rawValue) }
    }
}
