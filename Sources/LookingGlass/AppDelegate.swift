import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppController.shared.stop()
    }

    /// Clicking the Dock icon (or launching the app again) is the way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppController.shared.openSettings()
        return true
    }
}
