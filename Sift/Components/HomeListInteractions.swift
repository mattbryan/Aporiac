import SwiftUI

// MARK: - Layout metrics

enum HomeScreenLayout {
    /// Width of one swipe action bucket; matches list-style swipe affordance (~76pt).
    static let swipeActionButtonWidth: CGFloat = 76
}

enum HomeSwipeRowKeys {
    static func habit(_ id: UUID) -> String { "habit:\(id.uuidString)" }

    static func action(_ id: UUID) -> String { "action:\(id.uuidString)" }

    static func gem(_ id: UUID) -> String { "gem:\(id.uuidString)" }

    static func actionIdentity(_ item: ActionItem) -> String {
        "\(item.id.uuidString)-completed:\(item.completed)"
    }
}

// MARK: - Swipe-open environment

private struct SwipeRevealRowIsOpenKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// `true` when a `SwipeRevealRow` foreground is offset (actions visible); used to disable text taps/selection.
    var swipeRevealRowIsOpen: Bool {
        get { self[SwipeRevealRowIsOpenKey.self] }
        set { self[SwipeRevealRowIsOpenKey.self] = newValue }
    }
}

/// Disables hit testing on primary row content while swipe actions are exposed so drags close the row without text selection.
struct SwipeRevealBlocksForegroundWhenSwipeOpen: ViewModifier {
    @Environment(\.swipeRevealRowIsOpen) private var swipeRevealRowIsOpen

    func body(content: Content) -> some View {
        content.allowsHitTesting(!swipeRevealRowIsOpen)
    }
}

// MARK: - Diamond (habit swipe chrome)

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - SwipeRevealRow

/// Drag past fully revealed by this factor (unclamped finger travel) before auto-performing the action.
private let swipeRevealPerformMultiplier: CGFloat = 1.75

/// `List` swipe actions do not run inside `ScrollView`. This mirrors leading/trailing actions with a horizontal drag
/// that defers to vertical scrolling until the gesture reads clearly horizontal.
struct SwipeRevealRow<Leading: View, Trailing: View, Content: View>: View {
    /// Stable key for this row; used with `openRowKey` so only one row stays open.
    var rowKey: String
    @Binding var openRowKey: String?
    var leadingWidth: CGFloat
    var trailingWidth: CGFloat
    var allowsFullSwipeLeading: Bool
    var allowsFullSwipeTrailing: Bool
    var contentBackdrop: Color
    var onFullSwipeLeading: (() -> Void)?
    var onFullSwipeTrailing: (() -> Void)?
    /// Raise for rows with embedded `TextField`s so swipe does not win over typing (see gem fragment editor).
    var dragGestureMinimumDistance: CGFloat = 28
    /// When false, swipe runs as `simultaneousGesture` so the text view keeps priority for small movements.
    var swipeUsesHighPriorityGesture: Bool = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var dragAnchor: CGFloat = 0
    @State private var isDragging: Bool = false
    /// `nil` until the gesture commits to horizontal vs vertical.
    @State private var horizontalLock: Bool?

    /// When a row is open, the foreground must still receive drags to swipe it closed.
    private var contentAllowsHitTesting: Bool {
        offset != 0 || !isDragging
    }

    var body: some View {
        let maxLeading = leadingWidth
        let maxTrailing = trailingWidth

        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                leading()
                    .frame(width: maxLeading)
                    .frame(maxHeight: .infinity)
                Spacer(minLength: 0)
                trailing()
                    .frame(width: maxTrailing)
                    .frame(maxHeight: .infinity)
            }

            swipeForeground(maxLeading: maxLeading, maxTrailing: maxTrailing)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .onChange(of: openRowKey) { _, newValue in
            guard newValue != rowKey, offset != 0 else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                offset = 0
            }
        }
        .onDisappear {
            if openRowKey == rowKey {
                openRowKey = nil
            }
        }
    }

    @ViewBuilder
    private func swipeForeground(maxLeading: CGFloat, maxTrailing: CGFloat) -> some View {
        let g = dragGesture(maxLeading: maxLeading, maxTrailing: maxTrailing)
        let basis = content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(contentBackdrop)
            .environment(\.swipeRevealRowIsOpen, offset != 0 || (openRowKey != nil && openRowKey != rowKey))
            .offset(x: offset)
            .allowsHitTesting(contentAllowsHitTesting)

        if swipeUsesHighPriorityGesture {
            basis.highPriorityGesture(g)
        } else {
            basis.simultaneousGesture(g)
        }
    }

    private func dragGesture(maxLeading: CGFloat, maxTrailing: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: dragGestureMinimumDistance, coordinateSpace: .local)
            .onChanged { value in
                if horizontalLock == nil {
                    let ax = abs(value.translation.width)
                    let ay = abs(value.translation.height)
                    if ax > ay + 10 {
                        horizontalLock = true
                    } else if ay > ax + 10 {
                        horizontalLock = false
                        return
                    } else {
                        return
                    }
                }

                guard horizontalLock == true else { return }

                if !isDragging {
                    // Close whichever *other* row is open; do not clear when this row is the open one
                    // or we'd reset our own offset mid-drag.
                    if let open = openRowKey, open != rowKey {
                        openRowKey = nil
                    }
                    dragAnchor = offset
                    isDragging = true
                }

                var next = dragAnchor + value.translation.width
                if next > maxLeading {
                    // Rubber-band: diminishing returns past full reveal
                    let overshot = next - maxLeading
                    next = maxLeading + overshot * 0.25
                } else if next < -maxTrailing {
                    let overshot = (-maxTrailing) - next
                    next = -maxTrailing - overshot * 0.25
                }
                offset = next
            }
            .onEnded { value in
                defer {
                    isDragging = false
                    horizontalLock = nil
                }

                guard horizontalLock == true else { return }

                finishDrag(
                    value: value,
                    maxLeading: maxLeading,
                    maxTrailing: maxTrailing
                )
            }
    }

    private func clearOpenRowIfNeeded() {
        if openRowKey == rowKey {
            openRowKey = nil
        }
    }

    private func finishDrag(value: DragGesture.Value, maxLeading: CGFloat, maxTrailing: CGFloat) {
        // Clamp offset back to valid range before evaluating snap
        let clampedOffset = min(maxLeading, max(-maxTrailing, offset))
        let rawTranslation = value.translation.width
        let performLeading = maxLeading * swipeRevealPerformMultiplier
        let performTrailing = maxTrailing * swipeRevealPerformMultiplier

        if allowsFullSwipeLeading, maxLeading > 0, rawTranslation > performLeading {
            clearOpenRowIfNeeded()
            onFullSwipeLeading?()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = 0 }
            return
        }

        if allowsFullSwipeTrailing, maxTrailing > 0, rawTranslation < -performTrailing {
            clearOpenRowIfNeeded()
            onFullSwipeTrailing?()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = 0 }
            return
        }

        let predicted = dragAnchor + value.predictedEndTranslation.width

        let closingFromLeading = dragAnchor > maxLeading * 0.5 && (dragAnchor - clampedOffset) > maxLeading * 0.35
        let closingFromTrailing = dragAnchor < -maxTrailing * 0.5 && (clampedOffset - dragAnchor) > maxTrailing * 0.35

        let snapLeading =
            !closingFromLeading
            && maxLeading > 0
            && (clampedOffset > maxLeading * 0.5 || (clampedOffset >= 0 && predicted > maxLeading * 0.85))
        let snapTrailing =
            !closingFromTrailing
            && maxTrailing > 0
            && (clampedOffset < -maxTrailing * 0.5 || (clampedOffset <= 0 && predicted < -maxTrailing * 0.85))

        if snapLeading, !snapTrailing {
            openRowKey = rowKey
            withAnimation(DS.animationSlow) { offset = maxLeading }
        } else if snapTrailing, !snapLeading {
            openRowKey = rowKey
            withAnimation(DS.animationSlow) { offset = -maxTrailing }
        } else if snapLeading, snapTrailing {
            openRowKey = rowKey
            withAnimation(DS.animationSlow) {
                offset = predicted > 0 ? maxLeading : -maxTrailing
            }
        } else {
            clearOpenRowIfNeeded()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = 0 }
        }
    }
}

// MARK: - ActionItemRow

struct ActionItemRow: View {
    let item: ActionItem
    @FocusState.Binding var focusedField: UUID?
    @Environment(\.swipeRevealRowIsOpen) private var swipeRevealRowIsOpen
    let onToggle: () -> Void
    let onContentChange: (String) -> Void
    /// When non-nil, the first newline in the field finishes the current line and invokes this with text after the newline (new item body).
    var onReturnCreatesNewItemBelow: ((String) -> Void)?

    /// Local text keeps Return-from-new-item from briefly showing a second line before the parent model catches up.
    @State private var fieldText: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                onToggle()
            } label: {
                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.siftAccent, lineWidth: 2)
                            .opacity(item.completed ? 0 : 1)
                        Circle()
                            .fill(Color.siftAccent)
                            .opacity(item.completed ? 1 : 0)
                        if item.completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.siftContrastLight)
                        }
                    }
                    .frame(width: 24, height: 24)
                    Color.clear
                        .frame(width: DS.Spacing.md)
                        .contentShape(Rectangle())
                }
                .contentShape(Rectangle())
                .animation(DS.animationSlow, value: item.completed)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!swipeRevealRowIsOpen)

            TextField(
                "",
                text: Binding(
                    get: { fieldText },
                    set: { newValue in
                        if let (head, tail) = newValue.splitAtFirstNewline(),
                           let onReturn = onReturnCreatesNewItemBelow
                        {
                            fieldText = head
                            onContentChange(head)
                            onReturn(tail)
                        } else {
                            fieldText = newValue
                            onContentChange(newValue)
                        }
                    }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.siftCallout)
            .foregroundStyle(Color.siftInk)
            .tint(Color.siftAccent)
            .lineLimit(1...8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(item.completed)
            .focused($focusedField, equals: item.id)
            .allowsHitTesting(!item.completed && !swipeRevealRowIsOpen)
        }
        .padding(DS.Spacing.md)
        .frame(minHeight: DS.ButtonHeight.large, alignment: .center)
        .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
        .onChange(of: swipeRevealRowIsOpen) { _, isOpen in
            if isOpen, focusedField == item.id {
                focusedField = nil
            }
        }
        .onAppear {
            fieldText = item.content
        }
        .onChange(of: item.id) { _, _ in
            fieldText = item.content
        }
        .onChange(of: item.content) { _, newValue in
            guard newValue != fieldText else { return }
            fieldText = newValue
        }
    }
}

/// Read-only row matching completed `ActionItemRow` chrome (Today list) for contexts without swipe/toggle.
struct CompletedActionItemDisplayRow: View {
    let content: String
    /// When false, omits outer horizontal inset — use when the parent already applies screen-edge margins.
    var includeOuterHorizontalPadding: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.siftAccent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.siftContrastLight)
            }
            .frame(width: 24, height: 24)

            Text(content)
                .font(.siftCallout)
                .foregroundStyle(Color.siftInk)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .frame(minHeight: DS.ButtonHeight.large, alignment: .center)
        .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        .padding(.horizontal, includeOuterHorizontalPadding ? DS.Spacing.md : 0)
        .padding(.bottom, DS.Spacing.sm)
    }
}

// MARK: - Gem fragment field (Gems tab)

/// Multiline fragment editor for a gem — tap to focus like home action rows (Gems tab).
/// `\.swipeRevealRowIsOpen` must not include `isDragging` (see `SwipeRevealRow`); this view uses it for
/// `allowsHitTesting` / focus clearing when another row is open or this row is slid open.
struct GemEditableFragmentRow: View {
    let item: GemWithThemes
    var font: Font = .siftBody
    @FocusState.Binding var focusedField: UUID?
    @Environment(\.swipeRevealRowIsOpen) private var swipeRevealRowIsOpen
    let onFragmentChange: (String) -> Void

    @State private var fieldText: String = ""

    var body: some View {
        TextField(
            "",
            text: Binding(
                get: { fieldText },
                set: { newValue in
                    fieldText = newValue
                    onFragmentChange(newValue)
                }
            ),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(font)
        .foregroundStyle(Color.siftInk)
        .tint(Color.siftGem)
        .lineLimit(1...12)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.sentences)
        .focused($focusedField, equals: item.gem.id)
        .allowsHitTesting(!swipeRevealRowIsOpen)
        .onChange(of: swipeRevealRowIsOpen) { _, isOpen in
            if isOpen, focusedField == item.gem.id {
                focusedField = nil
            }
        }
        .onAppear {
            guard focusedField != item.gem.id else { return }
            fieldText = item.gem.content
        }
        .onChange(of: item.gem.id) { _, _ in
            fieldText = item.gem.content
        }
        .onChange(of: item.gem.content) { _, newValue in
            guard focusedField != item.gem.id else { return }
            guard newValue != fieldText else { return }
            fieldText = newValue
        }
    }
}

/// Read-only gem row for the home / calendar day list (Figma day summary).
struct DaySummaryGemReadOnlyCard: View {
    let content: String

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Rectangle()
                .fill(Color.siftGem)
                .frame(width: 8)
                .frame(maxHeight: .infinity)

            Text(content)
                .font(.siftCallout)
                .foregroundStyle(Color.siftInk)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Spacing.sm)
                .padding(.trailing, DS.Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.siftCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
    }
}

// MARK: - Day gems (Home + calendar day)

/// Gems block shared by [`HomeView`](Sift/Views/Home/HomeView.swift) and [`CalendarDayHomeView`](Sift/Views/DayPicker/CalendarDayHomeView.swift).
struct HomeDayGemsSection: View {
    var sectionLabelTop: CGFloat
    /// True when the calendar day has at least one entry row and the shell is ready to show the block.
    var showsSection: Bool
    var isLoading: Bool
    var gems: [GemWithThemes]
    @Binding var openSwipeRowKey: String?
    var horizontalInset: CGFloat = DS.Spacing.md
    var onDeleteGem: (UUID) async -> Void

    var body: some View {
        if showsSection {
            Text("GEMS")
                .siftMicroSectionLabel()
                .foregroundStyle(Color.siftGem)
                .padding(.horizontal, horizontalInset)
                .padding(.top, sectionLabelTop)
                .padding(.bottom, DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isLoading {
                    SiftSkeletonShimmer {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DaySummaryGemCardSkeleton()
                            DaySummaryGemCardSkeleton()
                        }
                    }
                } else if gems.isEmpty {
                    Text("No gems saved from this day.")
                        .font(.siftCallout)
                        .foregroundStyle(Color.siftSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(gems) { item in
                            SwipeRevealRow(
                                rowKey: HomeSwipeRowKeys.gem(item.gem.id),
                                openRowKey: $openSwipeRowKey,
                                leadingWidth: 0,
                                trailingWidth: HomeScreenLayout.swipeActionButtonWidth,
                                allowsFullSwipeLeading: false,
                                allowsFullSwipeTrailing: true,
                                contentBackdrop: Color.siftSurface,
                                onFullSwipeLeading: nil,
                                onFullSwipeTrailing: {
                                    openSwipeRowKey = nil
                                    Task { await onDeleteGem(item.gem.id) }
                                },
                                leading: {
                                    Color.clear
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                },
                                trailing: {
                                    Button {
                                        openSwipeRowKey = nil
                                        Task { await onDeleteGem(item.gem.id) }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(Color.siftContrastLight)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .background(Color.siftDelete)
                                }
                            ) {
                                NavigationLink(value: item.gem.id) {
                                    DaySummaryGemReadOnlyCard(content: item.gem.content)
                                }
                                .buttonStyle(.plain)
                            }
                            .id(item.gem.id)
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalInset)
        }
    }
}

// MARK: - String (action field newline)

extension String {
    /// Splits on the first newline character, advancing past `\r\n` when present.
    func splitAtFirstNewline() -> (head: String, tail: String)? {
        guard let i = firstIndex(where: { $0.isNewline }) else { return nil }
        let head = String(self[..<i])
        var tailStart = index(after: i)
        if self[i] == "\r", tailStart < endIndex, self[tailStart] == "\n" {
            tailStart = index(after: tailStart)
        }
        let tail = String(self[tailStart...])
        return (head, tail)
    }
}
