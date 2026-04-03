import SwiftUI

// MARK: - Color Tokens

extension Color {

    // MARK: Base

    /// Primary text and UI elements. Near-black.
    static let siftInk = Color(red: 0.08, green: 0.08, blue: 0.09)

    /// Muted text for unhighlighted content in entries older than today.
    static let siftInkFaded = Color(red: 0.55, green: 0.55, blue: 0.57)

    /// App background. Near-white with a faint warm cast.
    static let siftSurface = Color(red: 0.98, green: 0.97, blue: 0.96)

    /// Section dividers and subtle borders.
    static let siftDivider = Color(red: 0.88, green: 0.87, blue: 0.86)

    /// Secondary UI — labels, placeholders, inactive states.
    static let siftSubtle = Color(red: 0.72, green: 0.71, blue: 0.70)

    // MARK: Gem Accent (blue)

    /// Gem highlight text color and gem-day calendar squares. Mint — oklch(84.5% 0.143 164.978).
    static let siftGem = Color(red: 0.373, green: 0.914, blue: 0.709)

    /// Gem highlight background — applied behind selected text.
    static let siftGemBackground = Color(red: 0.373, green: 0.914, blue: 0.709).opacity(0.15)

    // MARK: Action Accent (warm amber)

    /// Action item highlight text color.
    static let siftAction = Color(red: 0.88, green: 0.52, blue: 0.22)

    /// Action item highlight background — applied behind selected text.
    static let siftActionBackground = Color(red: 0.88, green: 0.52, blue: 0.22).opacity(0.12)
}

// MARK: - Typography Tokens

extension Font {

    /// Large display — date headers, primary screen titles.
    static let siftTitle = Font.system(size: 28, weight: .medium, design: .default)

    /// Body — primary writing surface, entry content.
    static let siftBody = Font.system(size: 16, weight: .regular, design: .default)

    /// Emphasis within body — section labels, card titles.
    static let siftBodyMedium = Font.system(size: 16, weight: .medium, design: .default)

    /// Supporting — captions, metadata, timestamps.
    static let siftCaption = Font.system(size: 12, weight: .regular, design: .default)
}

// MARK: - Spacing Tokens

/// All spacing is a multiple of the 8pt base unit.
enum DS {

    enum Spacing {
        static let xs: CGFloat  = 8
        static let sm: CGFloat  = 16
        static let md: CGFloat  = 24
        static let lg: CGFloat  = 32
        static let xl: CGFloat  = 48
        static let xxl: CGFloat = 64
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat  = 8
        static let md: CGFloat  = 12
        static let lg: CGFloat  = 16
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

    /// Opacity of a day square in the calendar grid based on how many days ago it was.
    /// Today (0) is fully opaque. Day 6 is the most subtle.
    static func calendarDayOpacity(daysAgo: Int) -> Double {
        let curve: [Double] = [1.0, 0.72, 0.52, 0.36, 0.24, 0.15, 0.08]
        return curve[min(max(daysAgo, 0), 6)]
    }

    /// Whether content older than today should render at faded ink.
    /// Today's content is always full ink regardless of edit state.
    static func textColor(daysAgo: Int) -> Color {
        daysAgo == 0 ? .siftInk : .siftInkFaded
    }
}
