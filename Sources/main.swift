import AppKit

let args = CommandLine.arguments
if args.contains("--dump") {
    Dump.run()
    exit(0)
}
if let i = args.firstIndex(of: "--snapshot") {
    let dir = i + 1 < args.count ? args[i + 1] : FileManager.default.currentDirectoryPath
    MainActor.assumeIsolated { Snapshot.run(dir: dir) }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    if let i = args.firstIndex(of: "--self-test") {
        delegate.selfTest = true
        SelfTest.outputDir = i + 1 < args.count ? args[i + 1] : nil
    }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
