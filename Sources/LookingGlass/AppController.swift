import AppKit
import SwiftUI
import ServiceManagement

/// Panel that can still take key presses (Space = shutter, 1–6 = reactions).
final class MirrorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppController: NSObject, ObservableObject, NSPopoverDelegate, NSWindowDelegate {
    static let shared = AppController()

    // Photo + transient UI state, observed by the mirror view.
    @Published var lastPhoto: NSImage?
    @Published var lastPhotoURL: URL?
    @Published var photoID = UUID()
    @Published var countdown: Int?
    @Published var flashTick = 0
    @Published var toast: String?
    @Published var isPoppedOut = Prefs.poppedOut
    /// The settings drawer is open inside the pop-out window.
    @Published var settingsOpen = false
    /// True while the window exists only to show settings (it goes away when settings closes).
    @Published var previewOwned = false

    private let camera = CameraModel.shared
    private let mic = MicMonitor.shared
    private let island = IslandController()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var panel: MirrorPanel?

    private var lastRaw: CGImage?          // composed photo waiting to be saved
    private var capturing = false
    private var cameraHeld = false
    private var micHeld = false
    private var applyingFrame = false

    private var notchPoll: Timer?
    private var notchDwell = 0
    private var keyMonitor: Any?

    // Last-applied values, so applying prefs never rewrites defaults (which would re-trigger us).
    private var applied: (icon: MenuBarIcon?, dock: Bool?, dockStyle: DockIconStyle?, popover: CGSize?, panel: CGSize?) = (nil, nil, nil, nil, nil)

    // MARK: Start

    func start() {
        Prefs.registerDefaults()
        buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Looking Glass"
        }

        let host = NSHostingController(rootView: MirrorView(host: .popover))
        host.sizingOptions = []
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        island.onVisibilityChange = { [weak self] in self?.syncResources() }

        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        installKeyMonitor()
        applyPrefs()

        if Prefs.poppedOut && Prefs.reopenPoppedOut { showPanel() } else { Prefs.poppedOut = false; isPoppedOut = false }
    }

    func stop() {
        camera.release()
        mic.stop()
    }

    // MARK: Prefs

    @objc private func defaultsChanged() { applyPrefs() }

    private func applyPrefs() {
        // Menu bar icon
        let wantVisible = !Prefs.hideMenuBarIcon
        if statusItem.isVisible != wantVisible { statusItem.isVisible = wantVisible }
        let icon = Prefs.menuBarIcon
        if applied.icon != icon {
            statusItem.button?.image = IconRenderer.menuBarImage(icon)
            applied.icon = icon
        }

        // Dock icon
        let dock = Prefs.showDockIcon
        if applied.dock != dock {
            NSApp.setActivationPolicy(dock ? .regular : .accessory)
            applied.dock = dock
            applied.dockStyle = nil
        }
        let style = Prefs.dockIconStyle
        if applied.dockStyle != style {
            NSApp.applicationIconImage = IconRenderer.dockIcon(style, size: 512)
            applied.dockStyle = style
        }

        // Window sizing (format, size and shape all feed into the dimensions)
        let dims = Prefs.windowDimensions
        if applied.popover != dims {
            let margin: CGFloat = Prefs.shape == .circle ? 14 : 0
            popover.contentSize = NSSize(width: dims.width + margin * 2, height: dims.height + margin * 2)
            applied.popover = dims
        }
        if panel != nil, applied.panel != dims { resizePanel(animated: false) }
        applied.panel = dims

        camera.applyPreferredDevice()
        configureNotchMonitor()
        syncResources()
    }

    /// Camera and mic run only while a mirror window is actually on screen.
    private func syncResources() {
        let visible = popover.isShown || (panel?.isVisible ?? false) || island.isShown
        if visible && !cameraHeld { camera.acquire(); cameraHeld = true }
        if !visible && cameraHeld { camera.release(); cameraHeld = false }
        let wantMic = visible && Prefs.micMeter
        if wantMic && !micHeld { mic.start(); micHeld = true }
        if !wantMic && micHeld { mic.stop(); micHeld = false }
    }

    // MARK: Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu() } else { toggleMirror() }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: isPoppedOut ? "Show / Hide Mirror" : "Show Mirror", action: #selector(toggleMirrorAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: isPoppedOut ? "Put Back in Menu Bar" : "Pop Out Mirror", action: #selector(togglePopOutAction), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Photos Folder", action: #selector(openPhotosFolderAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Looking Glass", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleMirrorAction() { toggleMirror() }
    @objc private func togglePopOutAction() { isPoppedOut ? dockBack() : popOut() }
    @objc private func openPhotosFolderAction() { openPhotosFolder() }
    @objc private func openSettingsAction() { openSettings() }

    func toggleMirror() {
        island.hide(animated: false)
        if isPoppedOut {
            if let panel, panel.isVisible { panel.orderOut(nil); syncResources() } else { showPanel() }
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button, statusItem.isVisible {
            showPopover(relativeTo: button.bounds, of: button)
        }
    }

    // MARK: Popover

    private func showPopover(relativeTo rect: NSRect, of view: NSView) {
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        syncResources()
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { syncResources() }
    }

    // MARK: Pop-out window (also hosts settings)

    func popOut() {
        let frame = popover.contentViewController?.view.window?.frame ?? NSRect(x: 0, y: 0, width: 0, height: 0)
        popover.performClose(nil)
        island.hide(animated: false)
        previewOwned = false
        isPoppedOut = true
        Prefs.poppedOut = true
        let anchor = frame.width > 0 ? NSPoint(x: frame.midX - Prefs.windowDimensions.width / 2, y: frame.maxY - 8) : nil
        showPanel(topLeft: anchor)
        showToast("Pinned — stays on top of other windows")
    }

    /// Back into the menu bar bubble.
    func dockBack() {
        hidePanel()
        if statusItem.isVisible, let button = statusItem.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.showPopover(relativeTo: button.bounds, of: button)
            }
        }
    }

    /// Red traffic light: put the mirror away entirely.
    @objc func closePanel() { hidePanel() }

    private func hidePanel() {
        panel?.orderOut(nil)
        settingsOpen = false
        previewOwned = false
        isPoppedOut = false
        Prefs.poppedOut = false
        syncResources()
    }

    /// Turns a settings-only window into a real pop-out.
    func keepPreview() {
        previewOwned = false
        isPoppedOut = true
        Prefs.poppedOut = true
        if let panel { Prefs.panelTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY) }
        showToast("Pinned — stays on top of other windows")
    }

    private func makePanel() -> MirrorPanel {
        let size = panelTargetSize()
        let p = MirrorPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        // Only the red light: "Unpin" is an explicit button on the mirror, so no mystery yellow/green.
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        if let close = p.standardWindowButton(.closeButton) {
            close.target = self; close.action = #selector(closePanel); close.toolTip = "Close"
        }

        let hosting = NSHostingView(rootView: PanelRoot())
        hosting.sizingOptions = []          // we own the window size
        hosting.safeAreaRegions = []        // let the picture run under the title bar
        p.contentView = hosting
        setNativeChromeVisible(false, on: p, animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved(_:)),
                                               name: NSWindow.didMoveNotification, object: p)
        return p
    }

    private func panelTargetSize() -> NSSize {
        PanelLayout.size(mirror: Prefs.windowDimensions, settingsOpen: settingsOpen)
    }

    /// The real traffic lights only fade in while the pointer is over the window.
    func setNativeChromeVisible(_ visible: Bool) {
        guard let panel else { return }
        setNativeChromeVisible(visible || settingsOpen, on: panel, animated: true)
    }

    private func setNativeChromeVisible(_ visible: Bool, on p: NSPanel, animated: Bool) {
        let buttons = [p.standardWindowButton(.closeButton)].compactMap { $0 }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.15 : 0
            for b in buttons { b.animator().alphaValue = visible ? 1 : 0 }
        }
    }

    /// Resizes the window (format/size changes, settings drawer) keeping its top-left corner fixed.
    private func resizePanel(animated: Bool) {
        guard let panel else { return }
        let target = panelTargetSize()
        applyConstraints(on: panel)
        if abs(panel.frame.width - target.width) < 0.5, abs(panel.frame.height - target.height) < 0.5 { return }

        var f = panel.frame
        f.origin.y += f.height - target.height
        f.size = target
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame, f.maxX > visible.maxX {
            f.origin.x = max(visible.minX, visible.maxX - f.width)
        }
        applyingFrame = true
        panel.setFrame(f, display: true, animate: animated)
        applyingFrame = false
        setNativeChromeVisible(settingsOpen, on: panel, animated: animated)
    }

    /// Keeps the format's proportions while the user drags an edge; locks the size while settings is open.
    private func applyConstraints(on p: MirrorPanel) {
        if settingsOpen {
            p.styleMask.remove(.resizable)
            p.contentResizeIncrements = NSSize(width: 1, height: 1)
        } else {
            p.styleMask.insert(.resizable)
            let shape = Prefs.shape, format = Prefs.effectiveFormat(Prefs.format, shape: shape)
            if format == .custom {
                p.contentResizeIncrements = NSSize(width: 1, height: 1)      // any shape you like
                p.contentMinSize = NSSize(width: 210, height: 210)
                p.contentMaxSize = NSSize(width: 1000, height: 1000)
            } else {
                let dims = Prefs.windowDimensions
                p.contentAspectRatio = NSSize(width: dims.width, height: dims.height)
                p.contentMinSize = Prefs.dimensions(format: format, size: 200)
                p.contentMaxSize = Prefs.dimensions(format: format, size: 760)
            }
        }
    }

    /// `topLeft`: where the window's top-left corner goes. Otherwise the remembered spot, or the top right of the screen.
    private func showPanel(topLeft: NSPoint? = nil) {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        let size = panelTargetSize()
        var tl: NSPoint
        if let topLeft {
            tl = topLeft
        } else if !previewOwned, let saved = Prefs.panelTopLeft,
                  isOnScreen(NSRect(x: saved.x, y: saved.y - size.height, width: size.width, height: size.height)) {
            tl = saved
        } else if let screen = NSScreen.main {
            tl = NSPoint(x: screen.visibleFrame.maxX - size.width - 24, y: screen.visibleFrame.maxY - 24)
        } else {
            tl = NSPoint(x: 100, y: 800)
        }
        if let visible = NSScreen.main?.visibleFrame {      // never start partly off-screen
            tl.x = min(max(tl.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            tl.y = min(max(tl.y, visible.minY + size.height), visible.maxY)
        }
        applyConstraints(on: panel)
        applyingFrame = true
        panel.setFrame(NSRect(x: tl.x, y: tl.y - size.height, width: size.width, height: size.height), display: true)
        applyingFrame = false
        setNativeChromeVisible(settingsOpen, on: panel, animated: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        syncResources()
    }

    @objc private func panelMoved(_ note: Notification) {
        guard let panel, !previewOwned, !settingsOpen, !applyingFrame else { return }
        Prefs.panelTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    private func isOnScreen(_ rect: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
    }

    // MARK: Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { closePanel(); return false }
        return true
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { window !== panel }

    /// Dragging the window's edge resizes the mirror everywhere (popover and island included).
    /// Only a finished user drag is persisted, so programmatic frame changes can never feed back into the pref.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === panel, !settingsOpen, let size = w.contentView?.bounds.size else { return }
        let areaSize = (size.width * size.height).squareRoot().rounded()
        let d = UserDefaults.standard
        if Prefs.effectiveFormat(Prefs.format, shape: Prefs.shape) == .custom {
            let aspect = Double(size.width / max(size.height, 1))
            if abs(aspect - Double(Prefs.customAspect)) > 0.005 { d.set(aspect, forKey: Key.customAspect) }
        }
        if abs(areaSize - Prefs.mirrorSize) >= 1 { d.set(Double(areaSize), forKey: Key.mirrorSize) }
    }

    // MARK: Settings (a drawer in the pop-out window)

    func openSettings() {
        popover.performClose(nil)
        island.hide(animated: false)
        if let panel, panel.isVisible {
            withAnimation(.easeInOut(duration: 0.25)) { settingsOpen = true }
            resizePanel(animated: true)
        } else {
            previewOwned = true
            settingsOpen = true
            let size = panelTargetSize()
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            showPanel(topLeft: NSPoint(x: visible.midX - size.width / 2, y: min(visible.maxY - 16, visible.midY + size.height / 2)))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        if let panel { setNativeChromeVisible(true, on: panel, animated: false) }
    }

    func closeSettings() {
        guard settingsOpen else { return }
        if previewOwned {
            hidePanel()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { settingsOpen = false }
            resizePanel(animated: true)
        }
    }

    func toggleSettings() { settingsOpen ? closeSettings() : openSettings() }

    // MARK: Notch trigger

    /// Polls the pointer instead of using a global event monitor: `NSEvent.mouseLocation` needs no
    /// permissions and keeps working in the menu bar region, where monitors can go quiet.
    private func configureNotchMonitor() {
        if Prefs.notchTrigger, notchPoll == nil {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollNotch() }
            }
            RunLoop.main.add(timer, forMode: .common)
            notchPoll = timer
        } else if !Prefs.notchTrigger, let timer = notchPoll {
            timer.invalidate()
            notchPoll = nil
            notchDwell = 0
        }
    }

    /// The strip of screen the pointer must touch: the notch itself on notched Macs, otherwise
    /// a short stretch of the very top edge so the feature still works on other displays.
    private func triggerZone(on screen: NSScreen) -> NSRect {
        let f = screen.frame
        let inset = screen.safeAreaInsets.top
        if inset > 0 {
            let left = screen.auxiliaryTopLeftArea?.maxX ?? f.midX - 90
            let right = screen.auxiliaryTopRightArea?.minX ?? f.midX + 90
            return NSRect(x: left - 6, y: f.maxY - inset, width: right - left + 12, height: inset + 2)
        }
        return NSRect(x: f.midX - 80, y: f.maxY - 4, width: 160, height: 6)
    }

    private func pollNotch() {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }) ?? NSScreen.main,
              triggerZone(on: screen).contains(p) else {
            notchDwell = 0
            return
        }
        notchDwell += 1
        if notchDwell == 5 { notchTriggered(on: screen) }     // ~0.25 s resting on the notch
    }

    private func notchTriggered(on screen: NSScreen) {
        guard NSEvent.pressedMouseButtons == 0, !island.isShown else { return }
        if isPoppedOut {
            if panel?.isVisible != true { showPanel() }
            return
        }
        guard !popover.isShown else { return }
        island.show(on: screen)
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = event.window else { return event }
                let isMirror = window === self.panel || window === self.island.window
                    || window === self.popover.contentViewController?.view.window
                guard isMirror, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                // Don't steal keys while typing in a settings field.
                if window.firstResponder is NSTextView { return event }
                switch event.charactersIgnoringModifiers ?? "" {
                case " ": self.takePhoto(); return nil
                case "1", "2", "3", "4", "5", "6":
                    if let n = Int(event.charactersIgnoringModifiers ?? "") { ReactionEngine.shared.fire(index: n - 1) }
                    return nil
                case "\u{1b}":
                    if window === self.island.window { self.island.hide(); return nil }
                    if window === self.panel { self.settingsOpen ? self.closeSettings() : self.closePanel(); return nil }
                    return event
                default: return event
                }
            }
        }
    }

    // MARK: Photos

    func takePhoto() {
        guard !capturing else { return }
        guard camera.isRunning else { showToast("Camera isn't ready yet"); return }
        capturing = true
        let seconds = Prefs.countdown
        Task { @MainActor in
            if seconds > 0 {
                for n in stride(from: seconds, to: 0, by: -1) {
                    withAnimation(.spring(duration: 0.3)) { countdown = n }
                    try? await Task.sleep(for: .seconds(1))
                }
                withAnimation { countdown = nil }
            }
            await shoot()
            capturing = false
        }
    }

    private func shoot() async {
        if Prefs.flashEffect { flashTick += 1 }
        if Prefs.shutterSound { Self.shutterSound?.stop(); Self.shutterSound?.play() }

        guard let raw = await camera.capturePhoto() else { showToast("Couldn't take the photo"); return }
        guard let composed = PhotoComposer.compose(source: raw, options: .fromPrefs()) else { showToast("Couldn't develop the photo"); return }

        lastRaw = composed
        lastPhotoURL = nil
        photoID = UUID()
        let scale = min(1, 700 / CGFloat(composed.height))
        let preview = NSImage(cgImage: composed, size: NSSize(width: CGFloat(composed.width) * scale, height: CGFloat(composed.height) * scale))
        withAnimation(.spring(duration: 0.45)) { lastPhoto = preview }

        if Prefs.autoSave {
            saveLastPhoto()
            let id = photoID
            Task { @MainActor in          // a saved photo gets out of the way after a few seconds
                try? await Task.sleep(for: .seconds(7))
                if photoID == id, lastPhotoURL != nil { dismissPhoto() }
            }
        }
    }

    private static let shutterSound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Pop")
    }()

    func saveLastPhoto() {
        guard let image = lastRaw else { return }
        do {
            let url = try writePhoto(image)
            lastPhotoURL = url
            showToast("Saved to \((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)")
        } catch {
            showToast("Couldn't save: \(error.localizedDescription)")
        }
    }

    private func writePhoto(_ image: CGImage) throws -> URL {
        let format = Prefs.fileFormat
        let folder = URL(fileURLWithPath: (Prefs.saveFolder as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Looking Glass \(stamp.string(from: Date()))"
        var url = folder.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(format.fileExtension)
            n += 1
        }
        guard let data = PhotoComposer.encode(image, as: format) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
        return url
    }

    func copyLastPhoto() {
        guard let image = lastRaw else { return }
        let ns = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([ns])
        showToast("Copied to clipboard")
    }

    func revealLastPhoto() {
        if let url = lastPhotoURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func dismissPhoto() {
        withAnimation { lastPhoto = nil }
        lastRaw = nil
        lastPhotoURL = nil
    }

    func openPhotosFolder() {
        let url = URL(fileURLWithPath: (Prefs.saveFolder as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private var toastTask: Task<Void, Never>?
    func showToast(_ text: String) {
        withAnimation { toast = text }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { withAnimation { toast = nil } }
        }
    }

    // MARK: Menus

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Looking Glass", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Looking Glass", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Without an Edit menu, ⌘C/⌘V don't work in text fields of an accessory-style app.
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
