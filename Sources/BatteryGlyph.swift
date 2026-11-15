import AppKit

/// The menu bar battery icon, drawn to match macOS 27's: a solid pill whose empty part is
/// half-transparent, the charge in full ink (template white/black), yellow in Low Power Mode,
/// red when low. Geometry measured from Apple's icon (points).
enum BatteryGlyph {
    struct State: Equatable {
        enum Fill { case normal, lowPower, critical }
        enum Accessory { case none, bolt, plug }
        var percent: Int
        var fill: Fill = .normal
        var accessory: Accessory = .none
    }

    /// Apple's status item (and its open-menu highlight pill) is 43 pt wide with the body centred.
    static let statusItemLength: CGFloat = 43
    static let canvas = NSSize(width: 29, height: 12)
    static let body = NSRect(x: 3, y: 0, width: 23, height: 12)
    static let bodyRadius: CGFloat = 3.5
    static let nub = NSRect(x: 27, y: 3.75, width: 1.5, height: 4.5)
    static let emptyAlpha: CGFloat = 0.48
    static let nubAlpha: CGFloat = 0.57
    static let criticalPercent = 10
    static let lowPowerYellow = NSColor.systemYellow    // #FFD702 in the reference
    static let criticalRed = NSColor.systemRed

    static func state(for battery: BatteryInfo) -> State {
        var s = State(percent: battery.hasBattery ? battery.percent : 100)
        if battery.lowPowerActive { s.fill = .lowPower }
        else if battery.hasBattery && !battery.onAC && battery.percent <= criticalPercent { s.fill = .critical }
        if battery.onAC { s.accessory = battery.isCharging && !battery.isCharged ? .bolt : .plug }
        return s
    }

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: canvas, flipped: true) { _ in
            // Template images are tinted by the menu bar; coloured ones need the menu bar's ink
            // (white at 0.945 on a dark menu bar, measured) drawn by hand.
            let dark = MenuStyle.isDark(NSAppearance.currentDrawing())
            draw(state, ink: state.fill == .normal ? .black : (dark ? NSColor(white: 1, alpha: 0.945) : NSColor(white: 0, alpha: 0.85)))
            return true
        }
        image.isTemplate = state.fill == .normal
        return image
    }

    static func draw(_ s: State, ink: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = max(1, ctx.userSpaceToDeviceSpaceTransform.a)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius)

        ink.withAlphaComponent(ink.alphaComponent * emptyAlpha).setFill()
        bodyPath.fill()
        ink.withAlphaComponent(ink.alphaComponent * nubAlpha).setFill()
        nubShape(nub).fill()

        // Apple rounds the charge up to the next device pixel (11 % → 6 px of 46).
        let fillWidth = min(body.width, ceil(CGFloat(s.percent) / 100 * body.width * scale) / scale)
        if fillWidth > 0 {
            NSGraphicsContext.saveGraphicsState()
            bodyPath.addClip()
            switch s.fill {
            case .normal: ink.setFill()
            case .lowPower: lowPowerYellow.setFill()
            case .critical: criticalRed.setFill()
            }
            NSRect(x: body.minX, y: body.minY, width: fillWidth, height: body.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        let accessory: NSBezierPath? = switch s.accessory {
        case .none: nil
        case .bolt: boltPath()
        case .plug: plugPath()
        }
        if let accessory {
            // Knock a 1 pt gap around the glyph so it reads against the fill, then draw it.
            NSGraphicsContext.saveGraphicsState()
            ctx.setBlendMode(.clear)
            accessory.lineWidth = 2
            accessory.lineJoinStyle = .round
            accessory.stroke()
            accessory.fill()
            NSGraphicsContext.restoreGraphicsState()
            ink.setFill()
            accessory.fill()
        }
    }

    /// Battery terminal: flat against the body, rounded on the outside (a "D"), as in Apple's glyphs.
    static func nubShape(_ nub: NSRect) -> NSBezierPath {
        let r = min(nub.width, nub.height / 2)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: nub.minX, y: nub.minY))
        p.line(to: NSPoint(x: nub.maxX - r, y: nub.minY))
        p.appendArc(from: NSPoint(x: nub.maxX, y: nub.minY), to: NSPoint(x: nub.maxX, y: nub.minY + r), radius: r)
        p.line(to: NSPoint(x: nub.maxX, y: nub.maxY - r))
        p.appendArc(from: NSPoint(x: nub.maxX, y: nub.maxY), to: NSPoint(x: nub.maxX - r, y: nub.maxY), radius: r)
        p.line(to: NSPoint(x: nub.minX, y: nub.maxY))
        p.close()
        return p
    }

    /// Lightning bolt centred on the body (flipped coordinates).
    private static func boltPath() -> NSBezierPath {
        let pts: [(CGFloat, CGFloat)] = [(3.9, 0), (0.2, 5.3), (2.8, 5.3), (2.1, 9.5), (5.8, 4.1), (3.2, 4.1)]
        let origin = NSPoint(x: body.midX - 3, y: body.midY - 4.75)
        let p = NSBezierPath()
        for (i, pt) in pts.enumerated() {
            let q = NSPoint(x: origin.x + pt.0, y: origin.y + pt.1)
            if i == 0 { p.move(to: q) } else { p.line(to: q) }
        }
        p.close()
        return p
    }

    /// Two-prong plug centred on the body (flipped coordinates).
    private static func plugPath() -> NSBezierPath {
        let cx = body.midX
        let p = NSBezierPath()
        p.append(NSBezierPath(rect: NSRect(x: cx - 2.1, y: 1.2, width: 1.1, height: 2.4)))
        p.append(NSBezierPath(rect: NSRect(x: cx + 1.0, y: 1.2, width: 1.1, height: 2.4)))
        p.append(NSBezierPath(roundedRect: NSRect(x: cx - 3, y: 3.4, width: 6, height: 3.8), xRadius: 1.3, yRadius: 1.3))
        p.append(NSBezierPath(rect: NSRect(x: cx - 0.75, y: 7, width: 1.5, height: 1.6)))
        p.append(NSBezierPath(rect: NSRect(x: cx - 0.4, y: 8.4, width: 0.8, height: 2.4)))
        return p
    }
}
