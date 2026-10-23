import AppKit
import SwiftUI

/// State shared between the island window and its SwiftUI content.
final class IslandModel: ObservableObject {
    @Published var expanded = false
    var notch = CGSize(width: 200, height: 32)
    var content = CGSize(width: 320, height: 320)

    static let pad: CGFloat = 12
    static let shadowRoom = CGSize(width: 70, height: 50)

    var fullSize: CGSize { CGSize(width: content.width + Self.pad * 2, height: notch.height + content.height + Self.pad) }
    var windowSize: CGSize { CGSize(width: fullSize.width + Self.shadowRoom.width, height: fullSize.height + Self.shadowRoom.height) }
}

/// A pill that grows out of the notch, Dynamic Island style: the black body springs open, the camera
/// scales and un-blurs into place, and closing plays it in reverse.
struct IslandRoot: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let full = model.fullSize
        let w = model.expanded ? full.width : model.notch.width
        let h = model.expanded ? full.height : model.notch.height
        let r: CGFloat = model.expanded ? 38 : 11

        ZStack(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: 0, style: .continuous)
                .fill(.black)
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(model.expanded ? 0.5 : 0), radius: 22, y: 10)

            MirrorView(host: .island)
                .padding(.top, model.notch.height)
                .scaleEffect(model.expanded ? 1 : 0.5, anchor: .top)
                .opacity(model.expanded ? 1 : 0)
                .blur(radius: model.expanded ? 0 : 14)
                .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(model.expanded ? 0.07 : 0), value: model.expanded)
        }
        .frame(width: model.windowSize.width, height: model.windowSize.height, alignment: .top)
        .animation(.spring(response: 0.46, dampingFraction: 0.66), value: model.expanded)
    }
}

/// Owns the island window: shows it at the notch, watches the pointer, and collapses it again.
@MainActor
final class IslandController {
    private(set) var window: MirrorPanel?
    private let model = IslandModel()
    private var screenFrame = NSRect.zero
    private var centerX: CGFloat = 0
    private var watch: Timer?
    private var outsideTicks = 0
    private var hideWork: DispatchWorkItem?

    var isShown: Bool { window?.isVisible == true }
    var onVisibilityChange: (() -> Void)?

    func show(on screen: NSScreen) {
        guard !isShown else { return }
        hideWork?.cancel()

        // The notch's real geometry; other displays get a pill the height of the menu bar.
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notch = CGSize(width: right.minX - left.maxX, height: inset)
            centerX = (left.maxX + right.minX) / 2
        } else {
            model.notch = CGSize(width: 150, height: NSStatusBar.system.thickness)
            centerX = screen.frame.midX
        }
        model.content = Prefs.windowDimensions
        model.expanded = false
        screenFrame = screen.frame

        let w = window ?? makeWindow()
        window = w
        let size = model.windowSize
        w.setFrame(NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        w.orderFrontRegardless()
        w.makeKey()
        onVisibilityChange?()

        DispatchQueue.main.async { self.model.expanded = true }
        outsideTicks = 0
        watch?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
    }

    func hide(animated: Bool = true) {
        guard isShown else { return }
        watch?.invalidate()
        watch = nil
        if animated {
            model.expanded = false
            let work = DispatchWorkItem { [weak self] in self?.finishHide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        } else {
            model.expanded = false
            finishHide()
        }
    }

    private func finishHide() {
        window?.orderOut(nil)
        onVisibilityChange?()
    }

    /// The pointer's resting place keeps the island open; wandering off closes it.
    private func tick() {
        guard isShown, model.expanded else { return }
        guard Prefs.notchAutoHide, !AppController.shared.settingsOpen else { outsideTicks = 0; return }
        let p = NSEvent.mouseLocation
        let full = model.fullSize
        let island = NSRect(x: centerX - full.width / 2, y: screenFrame.maxY - full.height, width: full.width, height: full.height)
        let inside = island.insetBy(dx: -16, dy: -16).contains(p) || p.y > screenFrame.maxY - model.notch.height - 2 && abs(p.x - centerX) < model.notch.width
        let busy = NSEvent.pressedMouseButtons != 0
        outsideTicks = (inside || busy) ? 0 : outsideTicks + 1
        if outsideTicks >= 6 { hide() }
    }

    private func makeWindow() -> MirrorPanel {
        let w = MirrorPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isFloatingPanel = true
        w.level = .popUpMenu            // above the menu bar, so it can cover it
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.hidesOnDeactivate = false
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hosting = NSHostingView(rootView: IslandRoot(model: model))
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        w.contentView = hosting
        return w
    }
}
