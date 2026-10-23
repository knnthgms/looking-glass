import SwiftUI

/// Geometry of the pop-out window: just the mirror, or the mirror plus the settings drawer.
enum PanelLayout {
    static let settingsWidth: CGFloat = 410
    static let pad: CGFloat = 14
    static let drawerTop: CGFloat = 42       // clears the traffic lights
    static let minDrawerHeight: CGFloat = 620

    static func size(mirror: CGSize, settingsOpen: Bool) -> CGSize {
        guard settingsOpen else { return mirror }
        return CGSize(width: mirror.width + pad * 2 + 1 + settingsWidth,
                      height: max(mirror.height + drawerTop + pad, minDrawerHeight))
    }
}

/// The one and only pop-out window. Settings is not a separate window: it slides out beside the live mirror.
struct PanelRoot: View {
    @ObservedObject private var app = AppController.shared
    @AppStorage(Key.shape) private var shapeRaw = MaskShape.rounded.rawValue
    @AppStorage(Key.format) private var formatRaw = WindowFormat.square.rawValue
    @AppStorage(Key.mirrorSize) private var size = 320.0

    var body: some View {
        let shape = MaskShape(rawValue: shapeRaw) ?? .rounded
        let format = Prefs.effectiveFormat(WindowFormat(rawValue: formatRaw) ?? .square, shape: shape)
        let mirror = Prefs.dimensions(format: format, size: CGFloat(size))
        let total = PanelLayout.size(mirror: mirror, settingsOpen: app.settingsOpen)

        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if app.settingsOpen { Rectangle().fill(.regularMaterial) }
                MirrorView(host: .panel, drawer: app.settingsOpen)
                    .padding(.leading, app.settingsOpen ? PanelLayout.pad : 0)
                    .padding(.top, app.settingsOpen ? PanelLayout.drawerTop : 0)
            }
            .frame(width: app.settingsOpen ? mirror.width + PanelLayout.pad * 2 : mirror.width, height: total.height, alignment: .topLeading)

            if app.settingsOpen {
                Divider()
                SettingsView()
                    .frame(width: PanelLayout.settingsWidth, height: total.height)
                    .background(.background)
            }
        }
        .frame(width: total.width, height: total.height, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.25), value: app.settingsOpen)
    }
}
