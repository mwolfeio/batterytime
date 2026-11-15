import AppKit

/// `--dump`: prints what the menu would show and the exact commands an energy-mode click would run
/// (without running them).
enum Dump {
    static func run() {
        let b = PowerSource.read()
        let e = EnergyModeController.read()
        print("Battery:        \(b.hasBattery ? "\(b.percent)%" : "none")  onAC=\(b.onAC) charging=\(b.isCharging) charged=\(b.isCharged) lowPower=\(b.lowPowerActive)")
        print("Line 2:         \(b.powerSourceText)  |  \(b.timeEstimateText ?? "(no estimate)")")
        print("Energy mode:    \(e.mode.title)  (High Power supported: \(e.highPowerSupported))")
        print("Menu bar glyph: \(BatteryGlyph.state(for: b))")
        print("Clicking a mode would run (first that succeeds):")
        for mode in EnergyMode.allCases {
            print("  \(mode.title):")
            print("    \(EnergyModeController.sudoCommand(for: mode, onAC: b.onAC).joined(separator: " "))")
            print("    /usr/bin/osascript -e '\(EnergyModeController.adminPromptScript(for: mode, onAC: b.onAC))'")
        }
        let apps = EnergyUsage.sample()
        print("Using significant energy (≥ \(Int(EnergyUsage.threshold))): " + (apps.isEmpty ? "none" : apps.map { "\($0.name) \(Int($0.impact))" }.joined(separator: ", ")))
    }
}

/// `--self-test [DIR]`: launches normally, opens the menu itself, moves the highlight with a
/// Down-arrow key event posted to its own queue, logs the geometry and highlight state, optionally
/// saves the live menu's rows to DIR/live-menu.png, closes the menu and quits.
@MainActor
enum SelfTest {
    static var outputDir: String?
    private static var openMenu: NSMenu?

    static func run(statusItem: NSStatusItem, menu: NSMenu) {
        let button = statusItem.button
        log("status item length=\(statusItem.length) button=\(button.map { NSStringFromRect($0.frame) } ?? "nil") image=\(button?.image.map { NSStringFromSize($0.size) } ?? "nil") template=\(button?.image?.isTemplate ?? false)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { button?.performClick(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            log("FAIL menu did not open")
            exit(1)
        }
    }

    /// Called from menuWillOpen.
    static func menuWillOpen(_ menu: NSMenu) {
        openMenu = menu
        schedule(0.6) { pressDownArrow() }
        schedule(1.0) { inspectOpenMenu() }
    }

    private static func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { action() } }
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func pressDownArrow() {
        guard let window = openMenu?.items.compactMap({ $0.view?.window }).first else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: "\u{F701}",
                                        charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }

    private static func inspectOpenMenu() {
        guard let menu = openMenu, let window = menu.items.compactMap({ $0.view?.window }).first else {
            log("FAIL menu did not open")
            exit(1)
        }
        log("menu window \(type(of: window)) frame=\(NSStringFromRect(window.frame))")
        var expectedHeight: CGFloat = 10
        for item in menu.items where !item.isHidden {
            guard let view = item.view as? MenuRowView else { continue }
            let f = view.convert(view.bounds, to: nil)
            expectedHeight += f.height
            log(String(format: "  y=%6.1f h=%5.1f w=%5.1f enabled=%d highlighted=%d  %@", window.frame.height - f.maxY,
                       f.height, f.width, item.isEnabled ? 1 : 0, view.isHighlighted ? 1 : 0, item.title))
        }
        let chain = sequence(first: menu.items[0].view!, next: { $0.superview }).map { "\(type(of: $0))" }.joined(separator: " < ")
        log("view ancestry: \(chain)")
        log("highlighted item after Down arrow: \(menu.highlightedItem?.title ?? "none")")
        if let dir = outputDir, let content = window.contentView {
            let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/live-menu.png"))
            log("saved \(dir)/live-menu.png")
        }
        let ok = window.frame.width == MenuStyle.width && window.frame.height == expectedHeight
        log(ok ? "PASS menu \(Int(window.frame.width))x\(Int(window.frame.height)) pt" : "FAIL expected \(MenuStyle.width)x\(expectedHeight)")
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(ok ? 0 : 1) }
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
}

/// `--snapshot DIR`: renders the menu rows and the menu bar glyphs offscreen to PNGs, for checking
/// against the reference screenshots when screen capture is not available.
@MainActor
enum Snapshot {
    static func run(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let finder = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        let safari = NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")

        var b = BatteryInfo(hasBattery: true, percent: 11, onAC: false, minutesToEmpty: 110)
        menu(b, mode: .automatic, dark: true, to: "\(dir)/menu-dark-automatic.png")
        b.percent = 8; b.lowPowerActive = true; b.minutesToEmpty = nil
        menu(b, mode: .low, dark: true, hover: .high, to: "\(dir)/menu-dark-lowpower-hover.png")
        b = BatteryInfo(hasBattery: true, percent: 62, onAC: true, isCharging: true, minutesToFull: 42)
        menu(b, mode: .high, dark: true, apps: [("Safari", safari), ("Finder", finder)], to: "\(dir)/menu-dark-charging-apps.png")
        b = BatteryInfo(hasBattery: true, percent: 11, onAC: false, minutesToEmpty: 110)
        menu(b, mode: .automatic, dark: false, hover: .low, to: "\(dir)/menu-light-automatic-hover.png")
        glyphSheet(to: "\(dir)/glyphs.png")
        print("Wrote snapshots to \(dir)")
    }

    private static func rows(_ b: BatteryInfo, mode: EnergyMode, hover: EnergyMode?, apps: [(String, NSImage)]) -> [MenuRowView] {
        let header = HeaderView()
        header.percentText = "\(b.percent)%"
        header.sourceText = b.powerSourceText
        header.timeText = b.timeEstimateText
        var views: [MenuRowView] = [header, SeparatorView(), SmallTextView("Energy Mode", header: true)]
        for m in EnergyMode.allCases {
            let row = EnergyModeRowView(mode: m)
            row.selected = m == mode
            row.forceHighlight = m == hover
            views.append(row)
        }
        views.append(SeparatorView())
        if apps.isEmpty {
            views.append(SmallTextView("No Apps Using Significant Energy", header: false))
        } else {
            views.append(SmallTextView("Using Significant Energy", header: true))
            views += apps.map { AppRowView(name: $0.0, icon: $0.1) }
        }
        views += [SeparatorView(), PlainRowView("Battery Settings…")]
        return views
    }

    private static func menu(_ b: BatteryInfo, mode: EnergyMode, dark: Bool, hover: EnergyMode? = nil,
                             apps: [(String, NSImage)] = [], to path: String) {
        let views = rows(b, mode: mode, hover: hover, apps: apps)
        let height = 10 + views.reduce(0) { $0 + $1.frame.height }
        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: height))
        container.background = dark ? NSColor(srgbRed: 31 / 255, green: 31 / 255, blue: 31 / 255, alpha: 1) : NSColor(srgbRed: 236 / 255, green: 236 / 255, blue: 236 / 255, alpha: 1)
        container.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var y: CGFloat = 5
        for v in views {
            v.frame.origin.y = y
            y += v.frame.height
            container.addSubview(v)
        }
        save(render(container, scale: 2), to: path)
    }

    private static func glyphSheet(to path: String) {
        let states: [BatteryGlyph.State] = [
            .init(percent: 11), .init(percent: 8, fill: .lowPower), .init(percent: 7, fill: .critical),
            .init(percent: 50), .init(percent: 100), .init(percent: 62, accessory: .bolt), .init(percent: 100, accessory: .plug),
            .init(percent: 30, fill: .lowPower, accessory: .bolt),
        ]
        let cell = NSSize(width: BatteryGlyph.statusItemLength, height: 22)
        let sheet = FlippedView(frame: NSRect(x: 0, y: 0, width: cell.width * 2, height: cell.height * CGFloat(states.count)))
        for (row, state) in states.enumerated() {
            for (col, dark) in [true, false].enumerated() {
                let v = GlyphCell(frame: NSRect(x: CGFloat(col) * cell.width, y: CGFloat(row) * cell.height, width: cell.width, height: cell.height))
                v.state = state
                v.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                sheet.addSubview(v)
            }
        }
        save(render(sheet, scale: 8), to: path)
    }

    /// Renders into an sRGB context so alpha blending matches the screen (and the sRGB-converted references).
    private static func render(_ view: NSView, scale: CGFloat) -> NSBitmapImageRep {
        let cg = CGContext(data: nil, width: Int(view.bounds.width * scale), height: Int(view.bounds.height * scale),
                           bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.scaleBy(x: scale, y: scale)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: cg, flipped: false))
        let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
        rep.size = view.bounds.size
        return rep
    }

    private static func save(_ rep: NSBitmapImageRep, to path: String) {
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private final class FlippedView: NSView {
        var background: NSColor = .clear
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) { background.setFill(); bounds.fill() }
    }

    /// Mimics the menu bar: a template glyph is tinted like the system would (white 0.945 on dark, measured).
    private final class GlyphCell: NSView {
        var state = BatteryGlyph.State(percent: 100)
        override func draw(_ dirtyRect: NSRect) {
            let dark = MenuStyle.isDark(effectiveAppearance)
            (dark ? NSColor(srgbRed: 38 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1) : NSColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)).setFill()
            bounds.fill()
            let image = BatteryGlyph.image(state)
            let rect = NSRect(x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2,
                              width: image.size.width, height: image.size.height)
            if image.isTemplate {
                let tint = dark ? NSColor(white: 1, alpha: 0.945) : NSColor(white: 0, alpha: 0.85)
                let tinted = NSImage(size: image.size, flipped: false) { r in
                    image.draw(in: r)
                    tint.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: rect)
            } else {
                image.draw(in: rect)
            }
        }
    }
}
