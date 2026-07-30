import SwiftUI

/// Drag-to-reorder / show-hide editor shared by every section.
///
/// Reachable from the section it edits (toolbar ▦ button) rather than buried in Settings, so
/// rearranging a screen happens where the user is already looking at it.
struct SectionLayoutEditor<Block: SectionBlock>: View {
    let section: SectionID
    let blockType: Block.Type
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private var layout: SectionLayoutState { env.settings.config.layout(for: section) }
    private var ordered: [Block] { SectionLayout.resolved(Block.self, layout: layout) }
    private var hidden: Set<String> { Set(layout.hidden) }
    private var shownBlocks: [Block] { ordered.filter { !hidden.contains($0.rawValue) } }
    private var hiddenBlocks: [Block] { ordered.filter { hidden.contains($0.rawValue) } }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                List {
                    Section {
                        if shownBlocks.isEmpty {
                            Text(String(localized: "Every block is hidden. Add one back below."))
                                .font(.subheadline).foregroundStyle(Brand.textSecondary)
                        }
                        ForEach(shownBlocks) { block in
                            row(block, isHidden: false)
                        }
                        .onMove(perform: move)
                    } header: {
                        Text(String(localized: "Shown"))
                    } footer: {
                        Text(String(localized: "Drag the handle to reorder. Blocks still only appear when they have data."))
                    }

                    if !hiddenBlocks.isEmpty {
                        Section(String(localized: "Hidden")) {
                            ForEach(hiddenBlocks) { block in
                                row(block, isHidden: true)
                            }
                        }
                    }
                }
                .alwaysReorderable()
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(String(localized: "Arrange \(section.title)"))
            .toolbarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Reset")) { apply(SectionLayoutState()) }
                        .disabled(layout.isDefault)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(Brand.crimson)
    }

    private func row(_ block: Block, isHidden: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: block.icon)
                .foregroundStyle(isHidden ? Brand.textTertiary : Brand.crimson)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .foregroundStyle(isHidden ? Brand.textSecondary : Brand.textPrimary)
                Text(block.blurb)
                    .font(.caption).foregroundStyle(Brand.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if block.canHide {
                Button {
                    toggle(block)
                } label: {
                    Image(systemName: isHidden ? "plus.circle.fill" : "eye.slash")
                        .font(.body)
                        .foregroundStyle(isHidden ? Brand.driving : Brand.textTertiary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isHidden ? String(localized: "Show") : String(localized: "Hide"))
            }
        }
    }

    private func move(from: IndexSet, to: Int) {
        // `shownBlocks` is a filtered view of the full order, so the move is applied to the
        // visible list and the hidden blocks are appended back afterwards.
        var shown = shownBlocks
        shown.move(fromOffsets: from, toOffset: to)
        apply(SectionLayoutState(order: (shown + hiddenBlocks).map(\.rawValue),
                                 hidden: layout.hidden))
    }

    private func toggle(_ block: Block) {
        var hiddenList = layout.hidden
        if let idx = hiddenList.firstIndex(of: block.rawValue) {
            hiddenList.remove(at: idx)
        } else {
            hiddenList.append(block.rawValue)
        }
        let order = layout.order.isEmpty ? ordered.map(\.rawValue) : layout.order
        apply(SectionLayoutState(order: order, hidden: hiddenList))
    }

    private func apply(_ new: SectionLayoutState) {
        env.settings.config.setLayout(new, for: section)
        env.settings.save()
    }
}

private extension View {
    /// Show the drag handles permanently so reordering needs no Edit button. macOS has no
    /// `editMode`; its lists reorder from `.onMove` directly.
    @ViewBuilder
    func alwaysReorderable() -> some View {
        #if os(iOS)
        self.environment(\.editMode, .constant(.active))
        #else
        self
        #endif
    }
}

/// Toolbar button that opens the arrange sheet for a section.
struct ArrangeSectionButton<Block: SectionBlock>: View {
    let section: SectionID
    let blockType: Block.Type
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "square.grid.2x2")
        }
        .tint(Brand.crimson)
        .accessibilityLabel(String(localized: "Arrange section"))
        .sheet(isPresented: $presented) {
            SectionLayoutEditor(section: section, blockType: blockType)
        }
    }
}
