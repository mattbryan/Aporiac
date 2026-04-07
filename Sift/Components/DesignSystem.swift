import SwiftUI
import UIKit

// MARK: - Color Tokens
// Values follow `Design System.json` (Sift Color System, Screen Size, Opacities).

extension Color {

    private static func adaptiveUIColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    // MARK: Ink & surfaces

    /// Ink primary — main text (`#262626` / `#e5e5e5`).
    static let siftInk = Color(adaptiveUIColor(
        light: UIColor(red: 38 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1),
        dark: UIColor(red: 229 / 255, green: 229 / 255, blue: 229 / 255, alpha: 1)
    ))

    /// Ink secondary — faded body (e.g. older days), aligned to design secondary ink.
    static let siftInkFaded = Color(adaptiveUIColor(
        light: UIColor(red: 82 / 255, green: 82 / 255, blue: 82 / 255, alpha: 1),
        dark: UIColor(red: 161 / 255, green: 161 / 255, blue: 161 / 255, alpha: 1)
    ))

    /// Surface flat — app chrome background (`#f5f5f5` / `#171717`).
    static let siftSurface = Color(adaptiveUIColor(
        light: UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
        dark: UIColor(red: 23 / 255, green: 23 / 255, blue: 23 / 255, alpha: 1)
    ))

    /// Surface outdent — cards and elevated rows (`#ffffff` / `#262626`).
    static let siftCard = Color(adaptiveUIColor(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 38 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)
    ))

    static let siftDivider = Color(adaptiveUIColor(
        light: UIColor(red: 224 / 255, green: 222 / 255, blue: 221 / 255, alpha: 1),
        dark: UIColor(red: 61 / 255, green: 61 / 255, blue: 64 / 255, alpha: 1)
    ))

    /// Ink subtle — tertiary text.
    static let siftSubtle = Color(adaptiveUIColor(
        light: UIColor(red: 161 / 255, green: 161 / 255, blue: 161 / 255, alpha: 1),
        dark: UIColor(red: 82 / 255, green: 82 / 255, blue: 82 / 255, alpha: 1)
    ))

    /// High-contrast light label on saturated swipe / log fills.
    static let siftContrastLight = Color(red: 250 / 255, green: 248 / 255, blue: 245 / 255)

    // MARK: Accent & action (teal)

    /// System accent — tab bar, primary controls, caret (`#00d49c` / `#63e7c0`).
    static let siftAccent = Color(adaptiveUIColor(
        light: UIColor(red: 0 / 255, green: 212 / 255, blue: 156 / 255, alpha: 1),
        dark: UIColor(red: 99 / 255, green: 231 / 255, blue: 192 / 255, alpha: 1)
    ))

    /// Action / inline action text (matches Basic.Action).
    static let siftAction = Color(adaptiveUIColor(
        light: UIColor(red: 0 / 255, green: 212 / 255, blue: 156 / 255, alpha: 1),
        dark: UIColor(red: 99 / 255, green: 231 / 255, blue: 192 / 255, alpha: 1)
    ))

    /// Teal tint surface — action chips, inline action highlight in the entry editor (Basic.Action bg).
    static let siftActionTint = Color(adaptiveUIColor(
        light: UIColor(red: 0 / 255, green: 212 / 255, blue: 156 / 255, alpha: 0.15),
        dark: UIColor(red: 99 / 255, green: 231 / 255, blue: 192 / 255, alpha: 0.15)
    ))

    // MARK: Gem (gold)

    /// Gem fragment color and markers (`#fdcb34`).
    static let siftGem = Color(red: 253 / 255, green: 203 / 255, blue: 52 / 255)

    static let siftGemBackground = Color(red: 253 / 255, green: 203 / 255, blue: 52 / 255).opacity(0.15)

    /// Destructive fills — swipe delete, etc.
    static let siftDelete = Color(red: 255 / 255, green: 93 / 255, blue: 72 / 255)
}

// MARK: - Typography Tokens
// Text styles from Figma export (`h1-regular`, `p1-medium`, …). Pair fonts with
// `SiftTextStyleToken` / `SiftTracking` on `Text` for matching letter spacing.
// PostScript names match `UIAppFonts` / bundled files under Resources/Fonts.

/// Letter spacing (points) per Figma text style token.
enum SiftTracking {
    static let h1Regular: CGFloat = 1
    static let h1Medium: CGFloat = 0.4
    static let h1Bold: CGFloat = -1
    static let h2Regular: CGFloat = 0.9
    static let h2Medium: CGFloat = 0.5
    static let h2Bold: CGFloat = -0.3
    static let p1Regular: CGFloat = 0
    static let p1Medium: CGFloat = -0.25
    static let p1Bold: CGFloat = -0.5
    static let p2Regular: CGFloat = 0
    static let p2Medium: CGFloat = -0.2
    static let p2Bold: CGFloat = -0.4
    /// Caption/Regular in Figma uses Satoshi Medium (500).
    static let captionRegular: CGFloat = 0
    static let captionBold: CGFloat = -0.2
    static let microRegular: CGFloat = 0
    static let microBold: CGFloat = -0.15
}

/// Figma text style tokens — use with `Text.siftTextStyle(_:)` for font + tracking (+ uppercase on micro).
enum SiftTextStyleToken: CaseIterable {
    case h1Regular
    case h1Medium
    case h1Bold
    case h2Regular
    case h2Medium
    case h2Bold
    case p1Regular
    case p1Medium
    case p1Bold
    case p2Regular
    case p2Medium
    case p2Bold
    case captionRegular
    case captionBold
    case microRegular
    case microBold
}

extension SiftTextStyleToken {
    /// Font without tracking (apply `tracking` on `Text`).
    var font: Font {
        switch self {
        case .h1Regular:
            return Self.newsreaderItalic(size: 36, weight: .regular)
        case .h1Medium:
            return Self.newsreaderItalic(size: 36, weight: .medium)
        case .h1Bold:
            return Self.newsreaderItalic(size: 36, weight: .bold)
        case .h2Regular:
            return Self.newsreaderItalic(size: 24, weight: .regular)
        case .h2Medium:
            return Self.newsreaderItalic(size: 24, weight: .medium)
        case .h2Bold:
            return Self.newsreaderItalic(size: 24, weight: .bold)
        case .p1Regular:
            return Font.custom("Satoshi-Regular", size: 17)
        case .p1Medium:
            return Font.custom("Satoshi-Medium", size: 17)
        case .p1Bold:
            return Font.custom("Satoshi-Bold", size: 17)
        case .p2Regular:
            return Font.custom("Satoshi-Regular", size: 15)
        case .p2Medium:
            return Font.custom("Satoshi-Medium", size: 15)
        case .p2Bold:
            return Font.custom("Satoshi-Bold", size: 15)
        case .captionRegular:
            return Font.custom("Satoshi-Medium", size: 13)
        case .captionBold:
            return Font.custom("Satoshi-Bold", size: 13)
        case .microRegular:
            return Font.custom("Satoshi-Medium", size: 11)
        case .microBold:
            return Font.custom("Satoshi-Bold", size: 11)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .h1Regular: SiftTracking.h1Regular
        case .h1Medium: SiftTracking.h1Medium
        case .h1Bold: SiftTracking.h1Bold
        case .h2Regular: SiftTracking.h2Regular
        case .h2Medium: SiftTracking.h2Medium
        case .h2Bold: SiftTracking.h2Bold
        case .p1Regular: SiftTracking.p1Regular
        case .p1Medium: SiftTracking.p1Medium
        case .p1Bold: SiftTracking.p1Bold
        case .p2Regular: SiftTracking.p2Regular
        case .p2Medium: SiftTracking.p2Medium
        case .p2Bold: SiftTracking.p2Bold
        case .captionRegular: SiftTracking.captionRegular
        case .captionBold: SiftTracking.captionBold
        case .microRegular: SiftTracking.microRegular
        case .microBold: SiftTracking.microBold
        }
    }

    /// Figma specifies uppercase for micro styles.
    var usesUppercase: Bool {
        switch self {
        case .microRegular, .microBold: true
        default: false
        }
    }

    private static func newsreaderItalic(size: CGFloat, weight: Font.Weight) -> Font {
        Font.custom("Newsreader", size: size)
            .italic()
            .weight(weight)
    }
}

extension Text {
    /// Applies Figma font, kerning, and micro uppercase when defined for the token.
    @ViewBuilder
    func siftTextStyle(_ token: SiftTextStyleToken) -> some View {
        let styled = font(token.font).kerning(token.tracking)
        if token.usesUppercase {
            styled.textCase(.uppercase)
        } else {
            styled
        }
    }

    /// Micro section rail — **GEMS**, weekday strip (bold + uppercase + tracking).
    @ViewBuilder
    func siftMicroSectionLabel() -> some View {
        siftTextStyle(.microBold)
    }
}

extension Font {

    // MARK: Figma tokens (font only; add kerning via `SiftTextStyleToken` / `SiftTracking`)

    static let siftH1Regular = SiftTextStyleToken.h1Regular.font
    static let siftH1Medium = SiftTextStyleToken.h1Medium.font
    static let siftH1Bold = SiftTextStyleToken.h1Bold.font
    static let siftH2Regular = SiftTextStyleToken.h2Regular.font
    static let siftH2Medium = SiftTextStyleToken.h2Medium.font
    static let siftH2Bold = SiftTextStyleToken.h2Bold.font
    static let siftP1Regular = SiftTextStyleToken.p1Regular.font
    static let siftP1Medium = SiftTextStyleToken.p1Medium.font
    static let siftP1Bold = SiftTextStyleToken.p1Bold.font
    static let siftP2Regular = SiftTextStyleToken.p2Regular.font
    static let siftP2Medium = SiftTextStyleToken.p2Medium.font
    static let siftP2Bold = SiftTextStyleToken.p2Bold.font
    static let siftCaptionRegular = SiftTextStyleToken.captionRegular.font
    static let siftCaptionBold = SiftTextStyleToken.captionBold.font
    static let siftMicroRegular = SiftTextStyleToken.microRegular.font
    static let siftMicroBold = SiftTextStyleToken.microBold.font

    // MARK: Legacy semantic aliases (map to Figma scale)

    /// H1/Medium — primary screen titles (Newsreader 36 italic).
    static let siftTitle = siftH1Medium

    /// H2/Medium — sheet titles, secondary headers.
    static let siftHeadline = siftH2Medium

    /// P1/Regular — body.
    static let siftBody = siftP1Regular

    /// P1/Medium — emphasized body.
    static let siftBodyMedium = siftP1Medium

    /// P2/Regular — callout / secondary lines.
    static let siftCallout = siftP2Regular

    /// Caption/Regular — Satoshi Medium 13 (Figma `caption-regular`).
    static let siftCaption = siftCaptionRegular

    /// Micro/Bold — use `Text.siftMicroSectionLabel()` when Figma uppercase applies.
    static let siftMicro = siftMicroBold

    /// Date heading — H1/Bold (Today line).
    static var siftDateHeading: Font { siftH1Bold }
}

// MARK: - Spacing Tokens

/// All spacing is a multiple of the 8pt base unit.
enum DS {

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        /// Screen edge inset (not in JSON; keeps 20pt margin).
        static let screenEdge: CGFloat = 20
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        /// Design token `xxl` (40pt).
        static let xxl: CGFloat = 40
        /// Design token `Page Top` (48pt).
        static let pageTop: CGFloat = 48
    }

    enum ButtonHeight {
        static let large: CGFloat = 52
        static let medium: CGFloat = 44
    }

    enum IconSize {
        static let xs: CGFloat = 16
        static let s: CGFloat = 20
        static let m: CGFloat = 24
        static let l: CGFloat = 28
        static let xl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 999
        /// Fully rounded capsule / circle.
        static let pill: CGFloat = 999
    }

    // MARK: - Animation

    /// Standard interactive transition — most taps, expansions, state changes.
    static let animation = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Quick, snappy response — highlights, toggles, small state changes.
    static let animationFast = Animation.spring(response: 0.18, dampingFraction: 0.90)

    /// Slow, deliberate — fades, background transitions.
    static let animationSlow = Animation.easeInOut(duration: 0.35)

    /// Used for anything that moves with the keyboard.
    static let animationKeyboard = Animation.spring(response: 0.45, dampingFraction: 1.0)

    // MARK: - Calendar Fading

    /// Opacity by days ago (design Opacities — percent / 100). Day `7+` → 4%.
    static func calendarDayOpacity(daysAgo: Int) -> Double {
        if daysAgo >= 7 { return 0.04 }
        let curve: [Double] = [1.0, 0.72, 0.52, 0.36, 0.24, 0.14, 0.08]
        return curve[min(max(daysAgo, 0), 6)]
    }

    /// Opacity for entry body text (headings + plain lines, not gems or actions) by days ago.
    /// Gentler curve than calendar — text must remain readable through day 6 (last accessible day).
    static func entryBodyOpacity(daysAgo: Int) -> Double {
        let curve: [Double] = [1.0, 0.85, 0.72, 0.60, 0.48, 0.38, 0.30]
        return curve[min(max(daysAgo, 0), 6)]
    }

    /// Whether content older than today should render at faded ink.
    /// Today's content is always full ink regardless of edit state.
    static func textColor(daysAgo: Int) -> Color {
        daysAgo == 0 ? .siftInk : .siftInkFaded
    }
}

// MARK: - Appearance override (testing)

/// Persisted color scheme for validating adaptive tokens. Use with `@AppStorage(AppColorSchemeOverride.storageKey)`.
enum AppColorSchemeOverride: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// `UserDefaults` key; keep in sync anywhere this override is read or written.
    static let storageKey = "sift.designSystem.colorScheme"

    var id: String { rawValue }

    /// Short label for pickers and menus.
    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Argument for `View.preferredColorScheme(_:)`; `nil` follows the device.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Skeleton placeholders (loading states)

/// Rounded rectangle placeholder matching Sift card rhythm.
struct SiftSkeletonBlock: View {
    var cornerRadius: CGFloat = DS.Radius.xs
    var height: CGFloat
    var width: CGFloat? = nil

    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        Group {
            if let width {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .frame(width: width, height: height)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
    }
}

/// Capsule line (title / secondary line hints).
struct SiftSkeletonLine: View {
    var height: CGFloat = 14
    var widthFraction: CGFloat = 1.0

    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: max(40, geo.size.width * widthFraction), height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }
}

/// Wraps skeleton content with a soft pulse (Timeline-driven; no `Timer`).
struct SiftSkeletonShimmer<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.085 + 0.035 * sin(t * 2 * Double.pi / 1.25)
            content()
                .environment(\.skeletonPulseOpacity, pulse)
        }
    }
}

private struct SkeletonPulseOpacityKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0.09
}

extension EnvironmentValues {
    /// Driven by `SiftSkeletonShimmer` for placeholder fills.
    var skeletonPulseOpacity: CGFloat {
        get { self[SkeletonPulseOpacityKey.self] }
        set { self[SkeletonPulseOpacityKey.self] = newValue }
    }
}

/// Matches home habit row vertical size (~52pt content + padding).
struct HomeHabitRowSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Circle()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                skeletonLine(height: 15, widthFraction: 0.72)
                skeletonLine(height: 12, widthFraction: 0.45)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: DS.ButtonHeight.large, alignment: .center)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.md)
    }

    private func skeletonLine(height: CGFloat, widthFraction: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: max(40, geo.size.width * widthFraction), height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }
}

/// Matches `ActionItemRow` capsule card rhythm on home.
struct HomeActionRowSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Circle()
                .strokeBorder(Color.siftInk.opacity(pulseOpacity + 0.04), lineWidth: 2)
                .frame(width: 24, height: 24)
            GeometryReader { geo in
                Capsule()
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .frame(width: max(40, geo.size.width * 0.88), height: 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .frame(minHeight: DS.ButtonHeight.large, alignment: .center)
        .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
    }
}

/// Generic two-line list row placeholder.
struct SiftListRowSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                line(16, 0.55)
                line(13, 0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, DS.Spacing.md)
    }

    private func line(_ h: CGFloat, _ f: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: max(40, geo.size.width * f), height: h)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: h)
    }
}

struct GemCardSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            line(17, 1)
            line(17, 0.92)
            line(15, 0.88)
            line(15, 0.65)
            HStack(spacing: DS.Spacing.sm) {
                Capsule()
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .frame(width: 56, height: 28)
                Capsule()
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .frame(width: 72, height: 28)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private func line(_ h: CGFloat, _ f: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: max(40, geo.size.width * f), height: h)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: h)
    }
}

/// Skeleton for a gem card on the day summary (matches `DaySummaryGemReadOnlyCard` layout).
struct DaySummaryGemCardSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Rectangle()
                .fill(Color.siftGem.opacity(pulseOpacity * 0.55 + 0.12))
                .frame(width: 8)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                line(15, 1)
                line(15, 0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Spacing.sm)
            .padding(.trailing, DS.Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.siftCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
    }

    private func line(_ h: CGFloat, _ f: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: max(40, geo.size.width * f), height: h)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: h)
    }
}

/// Skeleton for [`GemDetailView`](Sift/Views/Gems/GemCard.swift): theme pill row + body lines.
struct GemDetailSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.sm) {
                Capsule()
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .frame(width: 88, height: 28)
                Capsule()
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .frame(width: 72, height: 28)
                Capsule()
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .frame(width: 64, height: 28)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                line(17, 1)
                line(17, 0.95)
                line(17, 0.88)
                line(17, 0.62)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ h: CGFloat, _ f: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: max(40, geo.size.width * f), height: h)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: h)
    }
}

/// Seven square cells matching the calendar strip layout.
struct DayPickerWeekSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<7, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

/// Placeholder for gratitude + body blocks before entry payload is ready.
struct EntryEditorSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line(12, 0.35)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xs)
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(0..<4, id: \.self) { i in
                    line(16, i == 3 ? 0.5 : 1)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.lg)
            line(12, 0.42)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.sm)
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(0..<6, id: \.self) { i in
                    let fracs: [CGFloat] = [1, 0.95, 1, 0.88, 1, 0.6]
                    line(16, fracs[i])
                }
            }
            .padding(.horizontal, DS.Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ h: CGFloat, _ f: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.siftInk.opacity(pulseOpacity))
                .frame(width: max(40, geo.size.width * f), height: h)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: h)
    }
}

struct HabitHeatMapSkeleton: View {
    @Environment(\.skeletonPulseOpacity) private var pulseOpacity

    private let columns = 7
    private let rows = 4

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.xs), count: columns), spacing: DS.Spacing.xs) {
            ForEach(0..<(columns * rows), id: \.self) { _ in
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(Color.siftInk.opacity(pulseOpacity))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
