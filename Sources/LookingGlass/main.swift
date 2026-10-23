import AppKit

// Developer helpers used by build.sh and for eyeballing output without a camera.
if let i = CommandLine.arguments.firstIndex(of: "--export-icon"), CommandLine.arguments.count > i + 1 {
    let data = IconRenderer.pngData(of: IconRenderer.dockIcon(.classic, size: 1024), pixels: 1024)
    try? data?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--selftest"), CommandLine.arguments.count > i + 1 {
    _ = NSApplication.shared   // SwiftUI views need an initialised app
    DevTools.run(outputDirectory: CommandLine.arguments[i + 1])
    exit(0)
}

// NSApplication.delegate is weak, so the delegate must outlive `run()` explicitly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
