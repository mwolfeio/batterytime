import AppKit

/// Approximates "Using Significant Energy". Apple's source is private, so this samples
/// `top -o power` (energy impact, same scale as Activity Monitor) and maps processes to apps.
enum EnergyUsage {
    /// Summed energy impact per app at or above this counts as significant.
    static let threshold = 20.0
    static let maxApps = 6
    /// Don't resample more often than this when the menu opens.
    static let minimumSampleInterval: TimeInterval = 30
    /// Background resample interval so the list is reasonably fresh when the menu opens.
    static let backgroundInterval: TimeInterval = 120

    struct App: Equatable {
        let pid: pid_t
        let name: String
        let impact: Double
    }

    /// Blocking (~1 s); call off the main thread.
    static func sample() -> [App] {
        let out = EnergyModeController.run("/usr/bin/top", ["-l", "2", "-o", "power", "-n", "40", "-stats", "pid,power"]).output
        return mapToApps(parseTop(out))
    }

    /// Returns pid → energy impact from the last sample block (the first one has no baseline).
    static func parseTop(_ output: String) -> [pid_t: Double] {
        var result: [pid_t: Double] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " })
            if parts.first == "PID" { result.removeAll(); continue }
            guard parts.count == 2, let pid = pid_t(parts[0]), let power = Double(parts[1]) else { continue }
            result[pid] = power
        }
        return result
    }

    static func mapToApps(_ impacts: [pid_t: Double]) -> [App] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
        }
        var byPid: [pid_t: NSRunningApplication] = [:]
        var byBundlePath: [String: NSRunningApplication] = [:]
        for app in apps {
            byPid[app.processIdentifier] = app
            if let path = app.bundleURL?.standardizedFileURL.path { byBundlePath[path] = app }
        }
        var totals: [pid_t: Double] = [:]
        for (pid, impact) in impacts where impact > 0 {
            let owner = byPid[pid] ?? outermostAppBundle(of: pid).flatMap { byBundlePath[$0] }
            if let owner { totals[owner.processIdentifier, default: 0] += impact }
        }
        return totals
            .filter { $0.value >= threshold }
            .compactMap { pid, impact in
                byPid[pid].map { App(pid: pid, name: $0.localizedName ?? "App", impact: impact) }
            }
            .sorted { $0.impact > $1.impact }
            .prefix(maxApps)
            .map { $0 }
    }

    /// Helper processes live inside their app's bundle, e.g. ".../Google Chrome.app/Contents/Frameworks/...".
    private static func outermostAppBundle(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
