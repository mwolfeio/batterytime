import AppKit

/// Base for every row in the menu. Rows draw their own hover highlight (Apple's battery menu is
/// built from custom views too) and forward clicks to the menu item's action.
class MenuRowView: NSView {
    /// Set by snapshots to render the hover state without a live menu.
    var forceHighlight = false
    var isInteractive: Bool { false }

    init(height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: height))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var isHighlighted: Bool {
        forceHighlight || (isInteractive && enclosingMenuItem?.isHighlighted == true && enclosingMenuItem?.isEnabled == true)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            MenuStyle.highlight.setFill()
            let r = MenuStyle.highlightRadius
            NSBezierPath(roundedRect: bounds.insetBy(dx: MenuStyle.highlightInsetX, dy: 0), xRadius: r, yRadius: r).fill()
        }
        drawContent()
    }

    func drawContent() {}

    override func mouseUp(with event: NSEvent) {
        guard isInteractive, let item = enclosingMenuItem, item.isEnabled, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }

    // MARK: Text

    private func attributes(_ font: NSFont, _ color: NSColor) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: color, .paragraphStyle: para]
    }

    private static let layout = NSLayoutManager()

    /// Draws one line so that its baseline sits exactly at `baseline`. (The text system puts the
    /// baseline at `defaultBaselineOffset`, which is rounded up from the font's ascender.)
    func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, baseline: CGFloat, maxWidth: CGFloat? = nil) {
        let width = maxWidth ?? (bounds.width - MenuStyle.inset - x)
        let rect = NSRect(x: x, y: baseline - Self.layout.defaultBaselineOffset(for: font), width: width,
                          height: Self.layout.defaultLineHeight(for: font))
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes(font, color))
    }

    func drawTextRight(_ text: String, font: NSFont, color: NSColor, right: CGFloat, baseline: CGFloat) {
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        drawText(text, font: font, color: color, x: right - width, baseline: baseline, maxWidth: width + 1)
    }

    func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// "Battery   11%" / "Power Source: Battery   1:50 remaining".
final class HeaderView: MenuRowView {
    var percentText = "" { didSet { if percentText != oldValue { needsDisplay = true } } }
    var sourceText = "" { didSet { if sourceText != oldValue { needsDisplay = true } } }
    var timeText: String? { didSet { if timeText != oldValue { needsDisplay = true } } }

    init() { super.init(height: MenuStyle.headerHeight) }

    override func drawContent() {
        let right = bounds.width - MenuStyle.inset
        let percentWidth = textWidth(percentText, font: MenuStyle.rowFont)
        drawText("Battery", font: MenuStyle.titleFont, color: MenuStyle.primaryText, x: MenuStyle.inset,
                 baseline: MenuStyle.titleBaseline, maxWidth: right - MenuStyle.inset - percentWidth - 8)
        drawTextRight(percentText, font: MenuStyle.rowFont, color: MenuStyle.secondaryText, right: right, baseline: MenuStyle.titleBaseline)

        var sourceMax = right - MenuStyle.inset
        if let timeText {
            drawTextRight(timeText, font: MenuStyle.smallFont, color: MenuStyle.secondaryText, right: right, baseline: MenuStyle.subtitleBaseline)
            sourceMax -= textWidth(timeText, font: MenuStyle.smallFont) + 8
        }
        drawText(sourceText, font: MenuStyle.smallFont, color: MenuStyle.secondaryText, x: MenuStyle.inset,
                 baseline: MenuStyle.subtitleBaseline, maxWidth: sourceMax)
    }
}

final class SeparatorView: MenuRowView {
    init() { super.init(height: MenuStyle.separatorHeight) }

    override func drawContent() {
        MenuStyle.separator.setFill()
        NSRect(x: MenuStyle.inset, y: MenuStyle.separatorLineY, width: bounds.width - 2 * MenuStyle.inset, height: 1).fill()
    }
}

/// "Energy Mode", "Using Significant Energy" (semibold) and "No Apps Using Significant Energy" (regular).
final class SmallTextView: MenuRowView {
    let text: String
    let font: NSFont

    init(_ text: String, header: Bool) {
        self.text = text
        self.font = header ? MenuStyle.sectionFont : MenuStyle.smallFont
        super.init(height: MenuStyle.smallRowHeight)
    }

    override func drawContent() {
        drawText(text, font: font, color: MenuStyle.secondaryText, x: MenuStyle.inset, baseline: MenuStyle.smallRowBaseline)
    }
}

/// "Battery Settings…" and other plain clickable rows.
final class PlainRowView: MenuRowView {
    let text: String
    init(_ text: String) {
        self.text = text
        super.init(height: MenuStyle.rowHeight)
    }

    override var isInteractive: Bool { true }

    override func drawContent() {
        drawText(text, font: MenuStyle.rowFont, color: MenuStyle.primaryText, x: MenuStyle.inset, baseline: MenuStyle.rowBaseline)
    }
}

final class AppRowView: MenuRowView {
    let name: String
    let icon: NSImage?

    init(name: String, icon: NSImage?) {
        self.name = name
        self.icon = icon
        super.init(height: MenuStyle.rowHeight)
    }

    override var isInteractive: Bool { true }

    override func drawContent() {
        let size = MenuStyle.appIconSize
        icon?.draw(in: NSRect(x: MenuStyle.inset, y: (bounds.height - size) / 2, width: size, height: size),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        drawText(name, font: MenuStyle.rowFont, color: MenuStyle.primaryText, x: MenuStyle.appLabelX, baseline: MenuStyle.rowBaseline)
    }
}

final class EnergyModeRowView: MenuRowView {
    let mode: EnergyMode
    var selected = false { didSet { if selected != oldValue { needsDisplay = true } } }

    init(mode: EnergyMode) {
        self.mode = mode
        super.init(height: MenuStyle.badgeRowHeight)
    }

    override var isInteractive: Bool { true }

    override func drawContent() {
        let d = MenuStyle.badgeDiameter
        EnergyBadge.draw(mode, selected: selected, in: NSRect(x: MenuStyle.inset, y: MenuStyle.badgeTop, width: d, height: d))
        drawText(mode.title, font: MenuStyle.rowFont, color: MenuStyle.primaryText, x: MenuStyle.badgeLabelX, baseline: MenuStyle.badgeLabelBaseline)
    }
}

/// The 26 pt circular badges on the Energy Mode rows: accent circle + white glyph when selected,
/// faint circle + grey glyph otherwise. Glyph geometry measured from Apple's menu (flipped, points
/// from the circle's top-left).
enum EnergyBadge {
    static let body = NSRect(x: 3, y: 8.75, width: 17.25, height: 9)
    static let bodyRadius: CGFloat = 2.5
    static let nub = NSRect(x: 21, y: 11.45, width: 1.3, height: 3.6)
    static let outlineWidth: CGFloat = 1.35
    static let lowPowerLevel: CGFloat = 4.15        // width of the low-power charge inside the outline
    static let secondaryAlpha: CGFloat = 0.52       // charge level inside the Low Power outline
    static let tertiaryAlpha: CGFloat = 0.28        // battery body behind the High Power arrows

    static func draw(_ mode: EnergyMode, selected: Bool, in circle: NSRect) {
        (selected ? MenuStyle.badgeOn : MenuStyle.badgeOff).setFill()
        NSBezierPath(ovalIn: circle).fill()

        // Resolve the dynamic colour for the current appearance so alpha can be scaled.
        let dynamicGlyph = selected ? MenuStyle.badgeOnGlyph : MenuStyle.badgeOffGlyph
        let glyph = dynamicGlyph.usingColorSpace(.sRGB) ?? dynamicGlyph
        let ox = circle.minX, oy = circle.minY
        let bodyRect = body.offsetBy(dx: ox, dy: oy)
        let nubRect = nub.offsetBy(dx: ox, dy: oy)
        let nubPath = BatteryGlyph.nubShape(nubRect)

        switch mode {
        case .automatic:
            glyph.setFill()
            NSBezierPath(roundedRect: bodyRect, xRadius: bodyRadius, yRadius: bodyRadius).fill()
            nubPath.fill()

        case .low:
            let half = outlineWidth / 2
            let outline = NSBezierPath(roundedRect: bodyRect.insetBy(dx: half, dy: half), xRadius: bodyRadius - half, yRadius: bodyRadius - half)
            outline.lineWidth = outlineWidth
            glyph.setStroke()
            outline.stroke()
            glyph.setFill()
            nubPath.fill()
            let inner = bodyRect.insetBy(dx: outlineWidth, dy: outlineWidth)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: inner, xRadius: bodyRadius - outlineWidth, yRadius: bodyRadius - outlineWidth).addClip()
            glyph.withAlphaComponent(glyph.alphaComponent * secondaryAlpha).setFill()
            NSRect(x: inner.minX, y: inner.minY, width: lowPowerLevel, height: inner.height).fill()
            NSGraphicsContext.restoreGraphicsState()

        case .high:
            glyph.withAlphaComponent(glyph.alphaComponent * tertiaryAlpha).setFill()
            NSBezierPath(roundedRect: bodyRect, xRadius: bodyRadius, yRadius: bodyRadius).fill()
            nubPath.fill()
            // Three ▶ with softened corners: fill, then a thin round-joined stroke (adds 0.25 pt),
            // composited as one layer so the translucent stroke doesn't darken the edges.
            let ctx = NSGraphicsContext.current?.cgContext
            ctx?.saveGState()
            ctx?.setAlpha(glyph.alphaComponent)
            ctx?.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { ctx?.endTransparencyLayer(); ctx?.restoreGState() }
            glyph.withAlphaComponent(1).setFill()
            glyph.withAlphaComponent(1).setStroke()
            for i in 0..<3 {
                let x = ox + 6.15 + CGFloat(i) * 4.3
                let top = oy + 11.5, height: CGFloat = 3.9, width: CGFloat = 3.25
                let t = NSBezierPath()
                t.move(to: NSPoint(x: x, y: top))
                t.line(to: NSPoint(x: x + width, y: top + height / 2))
                t.line(to: NSPoint(x: x, y: top + height))
                t.close()
                t.lineWidth = 0.5
                t.lineJoinStyle = .round
                t.fill()
                t.stroke()
            }
        }
    }
}
