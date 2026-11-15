import Foundation

enum EnergyMode: Int, CaseIterable {
    case automatic = 0, low = 1, high = 2

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .low: "Low Power"
        case .high: "High Power"
        }
    }
}

struct EnergyModeState: Equatable {
    var mode: EnergyMode = .automatic
    var highPowerSupported = false
}

/// Reads and writes the energy mode with `pmset`. Writing needs root: `sudo -n` first (works once
/// install-sudoers.sh has been run), otherwise the standard macOS administrator prompt.
enum EnergyModeController {
    static let pmset = "/usr/bin/pmset"

    static func read() -> EnergyModeState {
        EnergyModeState(
            mode: parseMode(run(pmset, ["-g"]).output) ?? .automatic,
            highPowerSupported: parseHighPowerSupported(run(pmset, ["-g", "cap"]).output)
        )
    }

    /// `pmset -g` lists the settings in use for the current power source.
    static func parseMode(_ output: String) -> EnergyMode? {
        var low = false, high = false
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, let value = Int(parts[1]) else { continue }
            switch parts[0] {
            case "powermode": return EnergyMode(rawValue: value)
            case "lowpowermode": low = value == 1
            case "highpowermode": high = value == 1
            default: break
            }
        }
        return high ? .high : low ? .low : nil
    }

    static func parseHighPowerSupported(_ output: String) -> Bool {
        output.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "highpowermode" }
    }

    /// `pmset -b` sets the battery profile, `-c` the power adapter profile.
    static func pmsetArguments(for mode: EnergyMode, onAC: Bool) -> [String] {
        [onAC ? "-c" : "-b", "powermode", String(mode.rawValue)]
    }

    static func sudoCommand(for mode: EnergyMode, onAC: Bool) -> [String] {
        ["/usr/bin/sudo", "-n", pmset] + pmsetArguments(for: mode, onAC: onAC)
    }

    static func adminPromptScript(for mode: EnergyMode, onAC: Bool) -> String {
        let command = ([pmset] + pmsetArguments(for: mode, onAC: onAC)).joined(separator: " ")
        return "do shell script \"\(command)\" with administrator privileges"
    }

    /// Runs off the main thread; `completion` is called on the main thread.
    static func apply(_ mode: EnergyMode, onAC: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let sudo = sudoCommand(for: mode, onAC: onAC)
            var ok = run(sudo[0], Array(sudo.dropFirst())).status == 0
            if !ok {
                ok = run("/usr/bin/osascript", ["-e", adminPromptScript(for: mode, onAC: onAC)]).status == 0
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
