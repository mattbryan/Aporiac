import SwiftUI
import UIKit

// MARK: - Color Tokens

extension Color {

    private static func adaptiveUIColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    // MARK: Base

    /// Primary text and UI elements. Near-black in light mode, near-white in dark mode.
    static let siftInk = Color(adaptiveUIColor(
        light: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    ))

    /// Muted text for unhighlighted content in entries older than today.
    static let siftInkFaded = Color(adaptiveUIColor(
        light: UIColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1),
        dark: UIColor(red: 0.58, green: 0.58, blue: 0.60, alpha: 1)
    ))

    /// App background. Near-white (light) / near-black (dark) with a faint warm cast.
    static let siftSurface = Color(adaptiveUIColor(
        light: UIColor(red: 0.98, green: 0.97, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    ))

    /// Section dividers and subtle borders.
    static let siftDivider = Color(adaptiveUIColor(
        light: UIColor(red: 0.88, green: 0.87, blue: 0.86, alpha: 1),
        dark: UIColor(red: 0.24, green: 0.24, blue: 0.25, alpha: 1)
    ))

    /// Secondary UI — labels, placeholders, inactive states.
    static let siftSubtle = Color(adaptiveUIColor(
        light: UIColor(red: 0.72, green: 0.71, blue: 0.70, alpha: 1),
        dark: UIColor(red: 0.55, green: 0.54, blue: 0.53, alpha: 1)
    ))

    /// Light label on dark or saturated fills (gem days, habit log selection) where adaptive surface would clash.
    static let siftContrastLight = Color(red: 0.98, green: 0.97, blue: 0.96)

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

    /// Section labels — sheet titles, secondary headers.
    static let siftHeadline = Font.system(size: 20, weight: .medium, design: .default)

    /// Body — primary writing surface, entry content.
    static let siftBody = Font.system(size: 17, weight: .regular, design: .default)

    /// Emphasis within body — section labels, card titles.
    static let siftBodyMedium = Font.system(size: 17, weight: .medium, design: .default)

    /// Supporting — captions, metadata, timestamps.
    static let siftCaption = Font.system(size: 13, weight: .regular, design: .default)

    /// Secondary content — supporting sentences, sheet labels.
    static let siftCallout = Font.system(size: 15, weight: .regular, design: .default)

    /// Minimum size — compact calendar aux labels; use sparingly.
    static let siftMicro = Font.system(size: 11, weight: .regular, design: .default)
}

// MARK: - Spacing Tokens

/// All spacing is a multiple of the 8pt base unit.
enum DS {

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xs: CGFloat  = 4
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
