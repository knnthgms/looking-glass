import SwiftUI

/// The mirror: just the camera, plus a few controls that appear while the pointer is over it.
/// Used in the menu bar popover, the pinned window and the notch island.
struct MirrorView: View {
    enum Host { case popover, panel, island }
    let host: Host
    /// True while the pinned window is showing its settings drawer next to the mirror.
    var drawer = false

    @ObservedObject private var camera = CameraModel.shared
    @ObservedObject private var mic = MicMonitor.shared
    @ObservedObject private var app = AppController.shared

    @AppStorage(Key.shape) private var shapeRaw = MaskShape.rounded.rawValue
    @AppStorage(Key.format) private var formatRaw = WindowFormat.square.rawValue
    @AppStorage(Key.customAspect) private var customAspect = 1.25
    @AppStorage(Key.photoAspect) private var photoAspectRaw = "match"
    @AppStorage(Key.zoom) private var zoom = 1.0
    @AppStorage(Key.rotation) private var rotation = 0.0
    @AppStorage(Key.mirrorSize) private var size = 320.0
    @AppStorage(Key.windowOpacity) private var opacity = 1.0
    @AppStorage(Key.flipPreview) private var flip = true
    @AppStorage(Key.micMeter) private var micMeter = false
    @AppStorage(Key.reactions) private var reactionsOn = true

    @State private var hovering = DevTools.forceControls
    @State private var showReactions = false
    @State private var overShutter = false

    // MARK: Geometry

    private var shape: MaskShape { MaskShape(rawValue: shapeRaw) ?? .rounded }
    private var format: WindowFormat { Prefs.effectiveFormat(WindowFormat(rawValue: formatRaw) ?? .square, shape: shape) }
    private var dims: CGSize { Prefs.dimensions(format: format, size: CGFloat(size)) }

    /// Keeps controls inside the visible area when a circle cuts the corners off.
    private var inset: CGFloat { shape == .circle ? min(dims.width, dims.height) * 0.14 : 0 }
    /// A circle in the popover floats on the bubble's own translucent material.
    private var margin: CGFloat { host == .popover && shape == .circle ? 14 : 0 }
    /// Native windows and the popover bubble round their own corners; the island and the drawer need their own.
    private var windowRadius: CGFloat {
        switch host {
        case .island: 26
        case .panel: drawer ? 16 : 0
        case .popover: 0
        }
    }

    var body: some View {
        ZStack {
            Group {
                backdrop
                cameraContent
            }
            .opacity(host == .panel ? opacity : 1)
            .clipShape(shape == .circle ? AnyShape(Circle()) : AnyShape(Rectangle()))

            ReactionLayer(width: dims.width, height: dims.height)
            if app.flashTick > 0 { FlashView(tick: app.flashTick) }
            if showGuide { cropGuide }
            controls
            if let n = app.countdown { countdownBadge(n) }
            if let toast = app.toast { toastView(toast) }
            thumbnail
        }
        .frame(width: dims.width, height: dims.height)
        .clipShape(RoundedRectangle(cornerRadius: windowRadius, style: .continuous))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.18)) { hovering = inside }
            if !inside { showReactions = false }
            if host == .panel { app.setNativeChromeVisible(inside) }
        }
        .padding(margin)
        .ignoresSafeArea()
    }

    // MARK: Camera

    @ViewBuilder private var backdrop: some View {
        if shape == .circle { Rectangle().fill(.ultraThinMaterial) } else { Color.black }
    }

    @ViewBuilder private var cameraContent: some View {
        switch camera.authorization {
        case .authorized:
            CameraPreview(session: camera.session, aspect: camera.aspect, mirrored: flip,
                          zoom: zoom, rotation: rotation, isCircle: shape == .circle)
                .frame(width: dims.width, height: dims.height)
            if !camera.isRunning { ProgressView().controlSize(.small).tint(.white) }
        case .notDetermined:
            ProgressView().controlSize(.small).tint(.white)
        default:
            VStack(spacing: 10) {
                Image(systemName: "video.slash").font(.system(size: 28))
                Text("Camera access is off").font(.headline)
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
            .foregroundStyle(.white)
            .padding(inset + 16)
        }
    }

    // MARK: Crop guide (only while aiming the shutter)

    private var photoAspect: CGFloat {
        photoAspectRaw == "match" ? dims.width / dims.height : (WindowFormat(rawValue: photoAspectRaw) ?? .square).aspect
    }
    private var showGuide: Bool {
        (overShutter || app.countdown != nil) && abs(photoAspect - dims.width / dims.height) > 0.02
    }

    /// If photos use a different shape than the window, hovering the capture button shows what will be kept.
    private var cropGuide: some View {
        let full = CGRect(origin: .zero, size: dims)
        let pa = photoAspect, wa = dims.width / dims.height
        let cw = pa > wa ? dims.width : dims.height * pa
        let ch = pa > wa ? dims.width / pa : dims.height
        let crop = CGRect(x: (dims.width - cw) / 2, y: (dims.height - ch) / 2, width: cw, height: ch)
        return ZStack {
            Path { p in p.addRect(full); p.addRect(crop) }.fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
            Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5).frame(width: crop.width, height: crop.height)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: Controls

    /// Everything that floats above the picture, shown only while the pointer is over the window.
    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom).frame(height: 70 + inset)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom).frame(height: 80 + inset)
            }
            .allowsHitTesting(false)

            VStack {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, 10 + inset)
            .padding(.vertical, 10 + inset * 0.8)
        }
        .environment(\.colorScheme, .dark)   // controls sit on video, so always use the dark material look
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
    }

    private var pinned: Bool { host == .panel && !app.previewOwned }

    private var topBar: some View {
        HStack(spacing: 8) {
            if micMeter {
                MicMeterView(level: mic.level, denied: mic.authorization == .denied || mic.authorization == .restricted)
                    .padding(.leading, host == .panel && !drawer ? 52 : 0)   // clear of the red traffic light
            }
            Spacer(minLength: 0)
            PinButton(pinned: pinned) {
                switch host {
                case .panel: app.previewOwned ? app.keepPreview() : app.dockBack()
                default: app.popOut()
                }
            }
            Menu {
                Button(app.settingsOpen ? "Close Settings" : "Settings…") { app.toggleSettings() }
                Button("Open Photos Folder") { app.openPhotosFolder() }
                Divider()
                Button("Quit Looking Glass") { NSApp.terminate(nil) }
            } label: {
                ControlFace(symbol: "gearshape.fill")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom) {
            if reactionsOn { reactionControl }
            Spacer(minLength: 0)
            CaptureButton(action: { app.takePhoto() }, hovering: $overShutter)
        }
    }

    private var reactionControl: some View {
        let room = Int((dims.width - 2 * inset - 120) / 32)
        let emoji = Array(ReactionEngine.palette.enumerated()).prefix(max(2, min(6, room)))
        return HStack(spacing: 4) {
            Button { withAnimation(.spring(duration: 0.3)) { showReactions.toggle() } } label: {
                ControlFace(symbol: showReactions ? "xmark" : "face.smiling", active: showReactions)
            }
            .buttonStyle(.plain)
            .help("Reactions")
            if showReactions {
                HStack(spacing: 0) {
                    ForEach(Array(emoji), id: \.offset) { index, e in
                        Button { ReactionEngine.shared.fire(e) } label: { Text(e).font(.system(size: 17)).frame(width: 32, height: 30) }
                            .buttonStyle(EmojiStyle())
                            .help("Send \(e)  (\(index + 1))")
                    }
                }
                .padding(.horizontal, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
            }
        }
    }

    // MARK: Overlays

    @ViewBuilder private var thumbnail: some View {
        if let photo = app.lastPhoto {
            PhotoThumb(image: photo, width: min(dims.width, dims.height) * 0.26)
                .id(app.photoID)
                .frame(width: dims.width, height: dims.height, alignment: .bottomTrailing)
                .padding(.trailing, 12 + inset)
                .padding(.bottom, 62 + inset * 0.7)
                .frame(width: dims.width, height: dims.height, alignment: .bottomTrailing)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func countdownBadge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: min(dims.width, dims.height) * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(radius: 10)
            .id(n)
            .transition(.scale(scale: 1.6).combined(with: .opacity))
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Text(text).font(.caption.weight(.medium)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.65), in: Capsule())
                .padding(.top, 12 + inset)
            Spacer()
        }
        .transition(.opacity)
    }
}

// MARK: - Controls

/// A frosted circle with an SF Symbol, the base of every round control.
struct ControlFace: View {
    let symbol: String
    var active = false
    @State private var hover = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background {
                if active { Circle().fill(Color.accentColor) } else { Circle().fill(.ultraThinMaterial) }
            }
            .overlay(Circle().strokeBorder(.white.opacity(hover ? 0.4 : 0.18), lineWidth: 0.75))
            .contentShape(Circle())
            .onHover { hover = $0 }
    }
}

/// "Pin" keeps the mirror on screen above everything; "Unpin" puts it back in the menu bar.
private struct PinButton: View {
    let pinned: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: pinned ? "pin.slash.fill" : "pin.fill").font(.system(size: 11, weight: .bold))
                Text(pinned ? "Unpin" : "Pin").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background {
                if pinned { Capsule().fill(Color.accentColor) } else { Capsule().fill(.ultraThinMaterial) }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(hover ? 0.4 : 0.18), lineWidth: 0.75))
            .contentShape(Capsule())
            .onHover { hover = $0 }
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin — put the mirror back in the menu bar"
                     : "Pin — keep the mirror on top of other windows, on every desktop")
    }
}

/// The classic camera shutter: white ring, white disc.
private struct CaptureButton: View {
    let action: () -> Void
    @Binding var hovering: Bool

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 42, height: 42)
                Circle().fill(.white).frame(width: 33, height: 33)
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .contentShape(Circle())
        }
        .buttonStyle(CaptureStyle())
        .onHover { hovering = $0 }
        .help("Take a photo (Space)")
    }
}

private struct CaptureStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct EmojiStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Small pieces

private struct FlashView: View {
    let tick: Int
    @State private var opacity = 0.9
    var body: some View {
        Color.white.opacity(opacity)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { opacity = 0 } }
            .id(tick)
    }
}

private struct MicMeterView: View {
    let level: Float
    let denied: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: denied ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(denied ? .red : .white)
            if !denied {
                HStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { i in
                        let lit = Float(i) / 12 < level
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(lit ? (i > 9 ? Color.red : i > 7 ? Color.yellow : Color.green) : .white.opacity(0.25))
                            .frame(width: 4, height: 10)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.75))
        .help(denied ? "Microphone access is off in System Settings" : "Mic check — speak to see the level")
        .animation(.linear(duration: 0.06), value: level)
    }
}

/// The freshly taken photo; it "develops" from white, and offers save / copy / reveal on hover.
private struct PhotoThumb: View {
    let image: NSImage
    let width: CGFloat
    @ObservedObject private var app = AppController.shared
    @State private var developed = false
    @State private var hover = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width)
            .brightness(developed ? 0 : 0.85)
            .saturation(developed ? 1 : 0.2)
            .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
            .overlay(alignment: .bottom) { if hover { actions } }
            .rotationEffect(.degrees(4))
            .onHover { hover = $0 }
            .onDrag {
                if let url = app.lastPhotoURL, let provider = NSItemProvider(contentsOf: url) { return provider }
                return NSItemProvider(object: image)
            }
            .onAppear { withAnimation(.easeIn(duration: 2.6)) { developed = true } }
            .help(app.lastPhotoURL == nil ? "Not saved yet" : "Saved — drag me anywhere")
    }

    private var actions: some View {
        HStack(spacing: 7) {
            if app.lastPhotoURL == nil { tiny("square.and.arrow.down", "Save") { app.saveLastPhoto() } }
            tiny("doc.on.doc", "Copy") { app.copyLastPhoto() }
            if app.lastPhotoURL != nil { tiny("folder", "Show in Finder") { app.revealLastPhoto() } }
            tiny("xmark", "Dismiss") { app.dismissPhoto() }
        }
        .padding(.bottom, 5)
    }

    private func tiny(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.black.opacity(0.7))
                .frame(width: 16, height: 16).background(.black.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
