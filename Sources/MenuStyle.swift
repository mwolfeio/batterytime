import AppKit

/// Every measurement here was taken from screenshots of Apple's own battery menu on macOS 27.2
/// (2x PNGs in ~/Developer/_reference, divided by two). Change them here, not in the views.
enum MenuStyle {
    // Menu chrome is drawn by NSMenu itself (5 pt top/bottom padding on macOS 27).
    static let width: CGFloat = 308
    static let inset: CGFloat = 14                 // text, badges and separators, both edges

    // Title block: "Battery" / "11%", then "Power Source: Battery" / time estimate.
    static let headerHeight: CGFloat = 50
    static let titleBaseline: CGFloat = 21
    static let subtitleBaseline: CGFloat = 45.5

    // Separators: 11 pt tall item, 1 pt line 5 pt from its top.
    static let separatorHeight: CGFloat = 11
    static let separatorLineY: CGFloat = 5

    // "Energy Mode" / "Using Significant Energy" headers and the "No Apps…" note.
    static let smallRowHeight: CGFloat = 22
    static let smallRowBaseline: CGFloat = 15.5

    // Energy Mode rows with circular badges.
    static let badgeRowHeight: CGFloat = 32
    static let badgeDiameter: CGFloat = 26
    static let badgeTop: CGFloat = 3
    static let badgeLabelX: CGFloat = 48
    static let badgeLabelBaseline: CGFloat = 21

    // Plain rows ("Battery Settings…", app rows).
    static let rowHeight: CGFloat = 24
    static let rowBaseline: CGFloat = 16
    static let appIconSize: CGFloat = 16
    static let appLabelX: CGFloat = 38

    // Hover highlight (not visible in the references; inferred from macOS 27 menus).
    static let highlightInsetX: CGFloat = 5
    static let highlightRadius: CGFloat = 10

    // Fonts.
    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let rowFont = NSFont.systemFont(ofSize: 13)
    static let smallFont = NSFont.systemFont(ofSize: 12)
    static let sectionFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    // Colours. Dark values are calibrated to the reference (sRGB, menu background #1F1F1F);
    // light mode uses the matching system colours (no light reference was available).
    static let primaryText = dynamic(dark: NSColor(white: 1, alpha: 0.90), light: .labelColor)
    static let secondaryText = dynamic(dark: NSColor(white: 1, alpha: 0.375), light: .secondaryLabelColor)
    static let separator = dynamic(dark: NSColor(white: 1, alpha: 0.09), light: .separatorColor)
    static let highlight = dynamic(dark: NSColor(white: 1, alpha: 0.10), light: NSColor(white: 0, alpha: 0.07))
    static let badgeOff = NSColor.quaternaryLabelColor
    static let badgeOffGlyph = secondaryText
    static let badgeOnGlyph = NSColor.white
    /// Selected badge: #0091FF in the reference, i.e. systemBlue. Follows a custom accent colour if one is set.
    static let badgeOn: NSColor = UserDefaults.standard.object(forKey: "AppleAccentColor") == nil ? .systemBlue : .controlAccentColor

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua]).map {
            [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua].contains($0)
        } ?? false
    }

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { isDark($0) ? dark : light }
    }
}
