import Foundation
import IOKit.ps

struct BatteryInfo: Equatable {
    var hasBattery = false
    var percent = 0
    var onAC = true
    var isCharging = false
    var isCharged = false
    /// Minutes; nil while macOS is still calculating.
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var lowPowerActive = false

    var powerSourceText: String { onAC ? "Power Source: Power Adapter" : "Power Source: Battery" }

    /// The one addition to Apple's menu: shown right-aligned under the percentage.
    var timeEstimateText: String? {
        guard hasBattery else { return nil }
        if !onAC {
            guard let m = minutesToEmpty else { return "Calculating…" }
            return "\(Self.clock(m)) remaining"
        }
        guard isCharging, !isCharged, percent < 100 else { return nil }
        guard let m = minutesToFull else { return "Calculating…" }
        return "\(Self.clock(m)) until full"
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

enum PowerSource {
    static func read() -> BatteryInfo {
        var info = BatteryInfo()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return info }
        if let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? {
            info.onAC = providing != kIOPSBatteryPowerValue
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  d[kIOPSIsPresentKey] as? Bool ?? true else { continue }
            info.hasBattery = true
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            info.percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            info.percent = Swift.min(100, Swift.max(0, info.percent))
            if let state = d[kIOPSPowerSourceStateKey] as? String { info.onAC = state == kIOPSACPowerValue }
            info.isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            info.isCharged = d[kIOPSIsChargedKey] as? Bool ?? false
            info.minutesToEmpty = positive(d[kIOPSTimeToEmptyKey])
            info.minutesToFull = positive(d[kIOPSTimeToFullChargeKey])
            info.lowPowerActive = (d["LPM Active"] as? Bool) ?? ProcessInfo.processInfo.isLowPowerModeEnabled
            break
        }
        if !info.hasBattery { info.lowPowerActive = ProcessInfo.processInfo.isLowPowerModeEnabled }
        return info
    }

    private static func positive(_ value: Any?) -> Int? {
        guard let v = value as? Int, v > 0 else { return nil }
        return v
    }

    /// Calls `handler` on the main run loop (in common modes, so an open menu updates too)
    /// whenever macOS reports a power source change. Keep the returned source alive.
    static func observe(_ handler: @escaping () -> Void) -> CFRunLoopSource? {
        let box = Unmanaged.passRetained(HandlerBox(handler)).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<HandlerBox>.fromOpaque(ctx).takeUnretainedValue().handler()
        }, box)?.takeRetainedValue() else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return source
    }

    private final class HandlerBox {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
    }
}
