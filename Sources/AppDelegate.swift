import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let header = HeaderView()
    private var modeRows: [EnergyMode: (item: NSMenuItem, view: EnergyModeRowView)] = [:]
    private var energyItems: [NSMenuItem] = []
    private var quitItem: NSMenuItem?
    private var powerSource: CFRunLoopSource?
    private var appearanceObservation: NSKeyValueObservation?

    private var battery = BatteryInfo()
    private var energyMode = EnergyModeState()
    private var energyApps: [EnergyUsage.App] = []
    private var lastEnergySample = Date.distantPast
    private var samplingEnergy = false
    private var lastGlyph: BatteryGlyph.State?

    var selfTest = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: BatteryGlyph.statusItemLength)
        statusItem.autosaveName = "BatteryTime"
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.setAccessibilityTitle("Battery")
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateIcon(force: true) }
        }

        buildMenu()
        statusItem.menu = menu

        battery = PowerSource.read()
        energyMode = EnergyModeController.read()
        updateIcon()
        updateMenu()

        powerSource = PowerSource.observe { [weak self] in
            MainActor.assumeIsolated { self?.powerChanged() }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEnergyMode() }
        }
        let timer = Timer(timeInterval: EnergyUsage.backgroundInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleEnergy(force: true) }
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        sampleEnergy(force: true)

        if selfTest { SelfTest.run(statusItem: statusItem, menu: menu) }
    }

    // MARK: Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = MenuStyle.width

        add(header, title: "Battery")
        add(SeparatorView())
        add(SmallTextView("Energy Mode", header: true), title: "Energy Mode")
        for mode in EnergyMode.allCases {
            let view = EnergyModeRowView(mode: mode)
            let item = add(view, title: mode.title, action: #selector(selectEnergyMode(_:)))
            item.representedObject = mode.rawValue
            modeRows[mode] = (item, view)
        }
        add(SeparatorView())
        rebuildEnergySection()
        add(SeparatorView())
        add(PlainRowView("Battery Settings…"), title: "Battery Settings…", action: #selector(openBatterySettings))
    }

    @discardableResult
    private func add(_ view: MenuRowView, title: String = "", action: Selector? = nil, at index: Int? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.view = view
        item.isEnabled = action != nil
        if let index { menu.insertItem(item, at: index) } else { menu.addItem(item) }
        return item
    }

    /// The "Using Significant Energy" block sits between the second and third separators.
    private func rebuildEnergySection() {
        let insertAt = energyItems.first.map { menu.index(of: $0) } ?? menu.numberOfItems
        energyItems.forEach(menu.removeItem)
        energyItems = []
        var index = insertAt
        func insert(_ view: MenuRowView, _ title: String, _ action: Selector? = nil) -> NSMenuItem {
            let item = add(view, title: title, action: action, at: index)
            index += 1
            energyItems.append(item)
            return item
        }
        let apps = energyApps.compactMap { app in NSRunningApplication(processIdentifier: app.pid).map { (app, $0) } }
        if apps.isEmpty {
            _ = insert(SmallTextView("No Apps Using Significant Energy", header: false), "No Apps Using Significant Energy")
        } else {
            _ = insert(SmallTextView("Using Significant Energy", header: true), "Using Significant Energy")
            for (app, running) in apps {
                let item = insert(AppRowView(name: app.name, icon: running.icon), app.name, #selector(activateApp(_:)))
                item.representedObject = app.pid
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        battery = PowerSource.read()
        energyMode = EnergyModeController.read()
        updateIcon()
        updateMenu()
        rebuildEnergySection()
        sampleEnergy(force: false)

        // Apple's menu has no Quit item; hold Option while opening to get one.
        let wantsQuit = NSEvent.modifierFlags.contains(.option)
        if wantsQuit, quitItem == nil {
            quitItem = add(PlainRowView("Quit BatteryTime"), title: "Quit BatteryTime", action: #selector(quit))
        } else if !wantsQuit, let item = quitItem {
            menu.removeItem(item)
            quitItem = nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if selfTest { SelfTest.menuWillOpen(menu) }
    }

    private func updateMenu() {
        header.percentText = battery.hasBattery ? "\(battery.percent)%" : ""
        header.sourceText = battery.powerSourceText
        header.timeText = battery.timeEstimateText
        for (mode, row) in modeRows {
            row.view.selected = mode == energyMode.mode
            row.item.isHidden = mode == .high && !energyMode.highPowerSupported
        }
    }

    private func updateIcon(force: Bool = false) {
        let state = BatteryGlyph.state(for: battery)
        guard force || state != lastGlyph, let button = statusItem?.button else { return }
        lastGlyph = state
        button.image = BatteryGlyph.image(state)
        button.setAccessibilityValue(battery.hasBattery ? "\(battery.percent)%" : battery.powerSourceText)
    }

    // MARK: Updates

    private func powerChanged() {
        let wasOnAC = battery.onAC
        battery = PowerSource.read()
        if battery.onAC != wasOnAC { energyMode = EnergyModeController.read() }
        updateIcon()
        updateMenu()
    }

    private func refreshEnergyMode() {
        battery = PowerSource.read()
        energyMode = EnergyModeController.read()
        updateIcon()
        updateMenu()
    }

    private func sampleEnergy(force: Bool) {
        guard !samplingEnergy, force || Date().timeIntervalSince(lastEnergySample) > EnergyUsage.minimumSampleInterval else { return }
        samplingEnergy = true
        DispatchQueue.global(qos: .utility).async {
            let apps = EnergyUsage.sample()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.samplingEnergy = false
                    self.lastEnergySample = Date()
                    guard apps != self.energyApps else { return }
                    self.energyApps = apps
                    self.rebuildEnergySection()
                }
            }
        }
    }

    // MARK: Actions

    @objc private func selectEnergyMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int, let mode = EnergyMode(rawValue: raw), mode != energyMode.mode else { return }
        EnergyModeController.apply(mode, onAC: battery.onAC) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEnergyMode() }
        }
    }

    @objc private func activateApp(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? pid_t else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    @objc private func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
