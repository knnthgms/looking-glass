import SwiftUI
import ServiceManagement

// MARK: - Shell

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, window, photos, camera, icons
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .window: "Window"
        case .photos: "Photos"
        case .camera: "Camera"
        case .icons: "Icons"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .window: "macwindow"
        case .photos: "photo.on.rectangle.angled"
        case .camera: "video.fill"
        case .icons: "app.badge.fill"
        }
    }
}

/// Settings live inside the mirror window (a drawer beside the live preview), so there is only ever one window.
struct SettingsView: View {
    @AppStorage("settingsPane") private var paneRaw = SettingsPane.window.rawValue
    private var pane: SettingsPane { SettingsPane(rawValue: paneRaw) ?? .window }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.top, PanelLayout.drawerTop - 8)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            Divider()
            SettingsDetail(pane: pane)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsPane.allCases) { p in
                let selected = p == pane
                Button { paneRaw = p.rawValue } label: {
                    VStack(spacing: 3) {
                        Image(systemName: p.symbol).font(.system(size: 16, weight: .medium)).frame(height: 18)
                        Text(p.title).font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { AppController.shared.closeSettings() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(.tertiary).padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            .help("Close settings")
        }
    }
}

struct SettingsDetail: View {
    let pane: SettingsPane
    var body: some View {
        switch pane {
        case .general: GeneralSettings()
        case .window: WindowSettings()
        case .photos: PhotoSettings()
        case .camera: CameraSettings()
        case .icons: IconSettings()
        }
    }
}

// MARK: - Building blocks

/// A titled group of rows on a soft rounded card.
private struct Card<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 6)
            }
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Row<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 9)
    }
}

private struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        Row(title: title, subtitle: subtitle) { Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small) }
    }
}

private struct Sep: View { var body: some View { Divider().opacity(0.6) } }

/// Slider row with a live value readout.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let readout: (Double) -> String

    var body: some View {
        Row(title: title) {
            HStack(spacing: 8) {
                Group {
                    if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
                }
                .frame(width: 150)
                Text(readout(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            }
        }
    }
}

private struct Pane<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(spacing: 18, content: content).padding(16)
        }
        .scrollIndicators(.never)
    }
}

/// A selectable chip: text on a pill, accent-filled when chosen.
private struct Chip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.callout.weight(.medium)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .foregroundStyle(selected ? Color.white : .primary)
                .background(selected ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private let tileGradient = LinearGradient(colors: [Color(red: 0.53, green: 0.62, blue: 1), Color(red: 0.52, green: 0.3, blue: 0.95)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(Key.notchTrigger) private var notch = false
    @AppStorage(Key.notchAutoHide) private var notchAutoHide = true
    @AppStorage(Key.hideMenuBarIcon) private var hideIcon = false
    @AppStorage(Key.reopenPoppedOut) private var reopenPoppedOut = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Pane {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pin.fill").font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pin the mirror").font(.headline)
                    Text("Press Pin on the mirror to lift it out of the menu bar into a window that stays on top of everything, on every desktop. Press Unpin, or the red dot, to put it away.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Card(title: "Startup") {
                ToggleRow(title: "Open at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch {
                            NSLog("Launch at login failed: \(error.localizedDescription)")
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
                Sep()
                ToggleRow(title: "Bring back the pinned mirror", subtitle: "Reopen it where you left it", isOn: $reopenPoppedOut)
            }

            Card(title: "Notch", footer: "Rest the pointer on the notch and the mirror grows out of it. On Macs without a notch, use the middle of the top screen edge.") {
                ToggleRow(title: "Open when I hover the notch", isOn: $notch)
                Sep()
                ToggleRow(title: "Close when the pointer leaves", isOn: $notchAutoHide).disabled(!notch)
            }

            Card(title: "Menu bar", footer: "With the icon hidden, open the mirror from the notch, or launch Looking Glass again to return here.") {
                ToggleRow(title: "Hide the menu bar icon", isOn: $hideIcon)
            }
        }
    }
}

// MARK: - Window

private struct WindowSettings: View {
    @AppStorage(Key.shape) private var shape = MaskShape.rounded.rawValue
    @AppStorage(Key.format) private var format = WindowFormat.square.rawValue
    @AppStorage(Key.mirrorSize) private var size = 320.0
    @AppStorage(Key.windowOpacity) private var opacity = 1.0
    @AppStorage(Key.zoom) private var zoom = 1.0
    @AppStorage(Key.rotation) private var rotation = 0.0
    @AppStorage(Key.customAspect) private var customAspect = 1.25

    private var isCircle: Bool { shape == MaskShape.circle.rawValue }

    var body: some View {
        Pane {
            Card(title: "Format", footer: "This is the shape of the live preview. Photos can use their own shape (Photos tab).") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(WindowFormat.allCases) { f in
                        FormatTile(format: f, customAspect: customAspect, selected: !isCircle && format == f.rawValue) {
                            format = f.rawValue
                            shape = MaskShape.rounded.rawValue
                        }
                    }
                }
                .padding(.vertical, 10)
                if !isCircle && format == WindowFormat.custom.rawValue {
                    Sep()
                    Row(title: "Proportions", subtitle: "Or drag the window's edges") {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait").foregroundStyle(.secondary)
                            Slider(value: Binding(get: { log2(customAspect) }, set: { customAspect = pow(2, $0) }), in: -1...1)
                                .frame(width: 110)
                            Image(systemName: "rectangle").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Card(title: "Size") {
                HStack(spacing: 8) {
                    ForEach(SizePreset.allCases) { p in Chip(label: p.label, selected: abs(size - p.value) < 1) { size = p.value } }
                }
                .padding(.vertical, 10)
                Sep()
                SliderRow(title: "Custom", value: $size, range: 200...560, step: 10) { "\(Int($0))" }
            }

            Card(title: "Shape") {
                HStack(spacing: 8) {
                    ForEach(MaskShape.allCases) { s in ShapeTile(shape: s, selected: shape == s.rawValue) { shape = s.rawValue } }
                }
                .padding(.vertical, 10)
            }

            Card(title: "Look") {
                SliderRow(title: "Transparency", value: Binding(get: { 1 - opacity }, set: { opacity = 1 - $0 }), range: 0...0.7) {
                    $0 < 0.005 ? "Off" : "\(Int($0 * 100))%"
                }
                Sep()
                SliderRow(title: "Zoom", value: $zoom, range: 1...4) { String(format: "%.1f×", $0) }
                Sep()
                Row(title: "Rotation") {
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("\(Int(rotation))°").font(.title3.monospacedDigit().weight(.medium))
                            HStack(spacing: 5) {
                                Button { rotation = wrap(rotation - 90) } label: { Image(systemName: "rotate.left") }
                                Button("Reset") { rotation = 0 }
                                Button { rotation = wrap(rotation + 90) } label: { Image(systemName: "rotate.right") }
                            }
                            .controlSize(.small)
                        }
                        RotationDial(degrees: $rotation).frame(width: 84, height: 84)
                    }
                }
            }
        }
    }

    private func wrap(_ d: Double) -> Double {
        var v = d.truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 }
        if v < -180 { v += 360 }
        return v
    }
}

private struct FormatTile: View {
    let format: WindowFormat
    let customAspect: Double
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06))
                    mini
                }
                .frame(height: 58)
                VStack(spacing: 0) {
                    Text(format.label).font(.callout.weight(.medium))
                    Text(format.detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var mini: some View {
        let box: CGFloat = 40
        let a = format == .custom ? CGFloat(customAspect) : format.aspect
        let w = a >= 1 ? box : box * a, h = a >= 1 ? box / a : box
        if format == .custom {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                .frame(width: w, height: h)
                .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.accentColor))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tileGradient).frame(width: w, height: h)
        }
    }
}

private struct ShapeTile: View {
    let shape: MaskShape
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if shape == .circle { Circle().fill(tileGradient) }
                    else { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tileGradient) }
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(shape.label).font(.callout.weight(.medium))
                    Text(shape.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// A knob you can drag around. Positive = clockwise; detents at every 45° help you land on exact angles.
struct RotationDial: View {
    @Binding var degrees: Double

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let r = d / 2
            ZStack {
                Circle().fill(.quaternary.opacity(0.5))
                Circle().strokeBorder(.separator, lineWidth: 1)
                ForEach(0..<24, id: \.self) { i in
                    Capsule()
                        .fill(i % 6 == 0 ? Color.secondary : Color.secondary.opacity(0.4))
                        .frame(width: i % 6 == 0 ? 2 : 1, height: i % 6 == 0 ? 8 : 5)
                        .offset(y: -(r - 8))
                        .rotationEffect(.degrees(Double(i) * 15))
                }
                Capsule().fill(Color.accentColor).frame(width: 3, height: r - 18).offset(y: -(r - 18) / 2)
                    .rotationEffect(.degrees(degrees))
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - r, dy = g.location.y - r
                guard dx * dx + dy * dy > 16 else { return }
                var angle = atan2(dx, -dy) * 180 / .pi            // 0° at 12 o'clock, clockwise positive
                let nearest = (angle / 45).rounded() * 45
                if abs(angle - nearest) < 4 { angle = nearest }
                degrees = angle.rounded()
            })
            .onTapGesture(count: 2) { degrees = 0 }
            .help("Drag to rotate — double-click to reset")
        }
    }
}

// MARK: - Photos

private struct PhotoSettings: View {
    @AppStorage(Key.saveFolder) private var folder = Prefs.defaultSaveFolder
    @AppStorage(Key.autoSave) private var autoSave = true
    @AppStorage(Key.fileFormat) private var format = ImageFileFormat.png.rawValue
    @AppStorage(Key.photoAspect) private var photoAspect = "match"
    @AppStorage(Key.frameStyle) private var frame = FrameStyle.classic.rawValue
    @AppStorage(Key.frameWidth) private var frameWidth = FrameWidth.regular.rawValue
    @AppStorage(Key.captionPreset) private var preset = CaptionPreset.classic.rawValue
    @AppStorage(Key.showDate) private var showDate = true
    @AppStorage(Key.dateFormat) private var dateFormat = DateStyleOption.medium.rawValue
    @AppStorage(Key.showTime) private var showTime = false
    @AppStorage(Key.caption) private var caption = ""
    @AppStorage(Key.flipPhotos) private var flipPhotos = true
    @AppStorage(Key.maskPhotos) private var maskPhotos = true
    @AppStorage(Key.shutterSound) private var sound = true
    @AppStorage(Key.flashEffect) private var flash = true
    @AppStorage(Key.countdown) private var countdown = 0
    @AppStorage(Key.shape) private var windowShape = MaskShape.rounded.rawValue

    var body: some View {
        VStack(spacing: 0) {
            PhotoPreviewHeader(trigger: [frame, frameWidth, preset, photoAspect, showDate.description, dateFormat,
                                         showTime.description, caption, maskPhotos.description, windowShape])
            Divider()
            Pane {
                shapeCard
                frameCard
                captionCard
                savingCard
                captureCard
            }
        }
    }

    private var shapeCard: some View {
        Card(title: "Photo shape", footer: "Hover the capture button on the mirror to see what a photo will keep.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                Chip(label: "Match window", selected: photoAspect == "match") { photoAspect = "match" }
                ForEach([WindowFormat.square, .portrait, .phonePortrait, .landscape, .phoneLandscape]) { f in
                    Chip(label: f.detail.replacingOccurrences(of: " ", with: ""), selected: photoAspect == f.rawValue) { photoAspect = f.rawValue }
                }
            }
            .padding(.vertical, 10)
            Sep()
            ToggleRow(title: "Round the corners", subtitle: "Follows the window shape (circle too)", isOn: $maskPhotos)
        }
    }

    private var frameCard: some View {
        Card(title: "Frame") {
            HStack(spacing: 10) {
                ForEach(FrameStyle.allCases) { f in PaperSwatch(style: f, selected: frame == f.rawValue) { frame = f.rawValue } }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            Sep()
            Row(title: "Border") {
                Picker("", selection: $frameWidth) {
                    ForEach(FrameWidth.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            .disabled(frame == FrameStyle.none.rawValue)
        }
    }

    private var captionCard: some View {
        Card(title: "Text & decoration", footer: "Style applies to the date and caption on the frame — or on the photo itself for Film stamp.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(CaptionPreset.allCases) { p in
                    StyleChip(preset: p, frame: FrameStyle(rawValue: frame) ?? .classic, selected: preset == p.rawValue) { preset = p.rawValue }
                }
            }
            .padding(.vertical, 10)
            Sep()
            ToggleRow(title: "Print the date", isOn: $showDate)
            if showDate {
                Sep()
                Row(title: "Date style") {
                    Picker("", selection: $dateFormat) {
                        ForEach(DateStyleOption.allCases) { Text($0.format(Date())).tag($0.rawValue) }
                    }
                    .labelsHidden().frame(width: 150)
                }
                Sep()
                ToggleRow(title: "Include the time", isOn: $showTime)
            }
            Sep()
            HStack {
                TextField("", text: $caption, prompt: Text("Add a line of text…"))
                    .textFieldStyle(.plain)
                if !caption.isEmpty {
                    Button { caption = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var savingCard: some View {
        Card(title: "Saving") {
            ToggleRow(title: "Save every photo", subtitle: "Automatically, as soon as you take it", isOn: $autoSave)
            Sep()
            Row(title: "Folder") {
                HStack(spacing: 8) {
                    Text((folder as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.head).foregroundStyle(.secondary).frame(maxWidth: 130, alignment: .trailing)
                    Button("Choose…") { chooseFolder() }
                }
            }
            Sep()
            Row(title: "File type") {
                Picker("", selection: $format) { ForEach(ImageFileFormat.allCases) { Text($0.label).tag($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 130)
            }
            Sep()
            Row(title: "Photos folder") { Button("Open") { AppController.shared.openPhotosFolder() } }
        }
    }

    private var captureCard: some View {
        Card(title: "Capture") {
            Row(title: "Self-timer") {
                Picker("", selection: $countdown) {
                    Text("Off").tag(0); Text("3s").tag(3); Text("5s").tag(5); Text("10s").tag(10)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            Sep()
            ToggleRow(title: "Mirror photos", subtitle: "Like the preview, not like a camera", isOn: $flipPhotos)
            Sep()
            ToggleRow(title: "Shutter sound", isOn: $sound)
            Sep()
            ToggleRow(title: "Screen flash", isOn: $flash)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Where should Looking Glass save your photos?"
        panel.directoryURL = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}

/// Pinned at the top of the Photos tab: the real composer's output for the current settings.
private struct PhotoPreviewHeader: View {
    let trigger: [String]
    private static let sample = DevTools.sampleFrame()

    var body: some View {
        var o = PhotoOptions.fromPrefs()
        o.maxPhotoSide = 520
        o.flip = false
        let image = PhotoComposer.compose(source: Self.sample, options: o)
        return ZStack {
            Color.primary.opacity(0.04)
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
                    .padding(.vertical, 14).padding(.horizontal, 20)
                    .id(trigger)
            }
        }
        .frame(height: 196)
    }
}

private struct PaperSwatch: View {
    let style: FrameStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if style == .none {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        Image(systemName: "nosign").foregroundStyle(.secondary)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: PhotoComposer.look(style).paper))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.black.opacity(0.15), lineWidth: 0.75))
                        RoundedRectangle(cornerRadius: 2).fill(tileGradient).padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 14)
                    }
                }
                .frame(width: 52, height: 58)
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                Text(label).font(.caption).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch style { case .classic: "White"; case .vintage: "Cream"; case .midnight: "Black"; case .none: "None" }
    }
}

/// A caption style shown as a specimen in its own font, colour and decoration.
private struct StyleChip: View {
    let preset: CaptionPreset
    let frame: FrameStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let spec = preset.spec
        let look = PhotoComposer.look(frame)
        let ink = Color(nsColor: PhotoComposer.inkColor(spec, look))
        let font = Font.custom(spec.font(14).fontName, size: 15 * min(max(spec.size, 0.8), 1.15))

        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if spec.stampOnPhoto {
                        LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                        Text("'26 10 10").font(.custom(spec.font(10).fontName, size: 11)).foregroundStyle(ink)
                            .shadow(color: ink.opacity(0.8), radius: 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(7)
                    } else {
                        Color(nsColor: look.paper)
                        VStack(spacing: 3) {
                            if spec.decor == .rule { Capsule().fill(Color(nsColor: look.ink).opacity(0.35)).frame(width: 34, height: 1) }
                            Text(spec.decorate("Oct 10")).font(font).kerning(spec.kern * 0.6).foregroundStyle(ink)
                        }
                        .rotationEffect(.degrees(spec.tilt))
                        if spec.decor == .tape {
                            Rectangle().fill(Color(red: 1, green: 0.88, blue: 0.4).opacity(0.85)).frame(width: 30, height: 9)
                                .rotationEffect(.degrees(-4)).frame(maxHeight: .infinity, alignment: .top).offset(y: -2)
                        }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.15), lineWidth: 0.75))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2).padding(-3))
                Text(preset.label).font(.caption).foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera & mic

private struct CameraSettings: View {
    @ObservedObject private var camera = CameraModel.shared
    @AppStorage(Key.cameraID) private var cameraID = ""
    @AppStorage(Key.flipPreview) private var flip = true
    @AppStorage(Key.micMeter) private var micMeter = false
    @AppStorage(Key.reactions) private var reactions = true

    var body: some View {
        Pane {
            Card(title: "Camera") {
                Row(title: "Camera") {
                    Picker("", selection: $cameraID) {
                        Text("System default").tag("")
                        ForEach(camera.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }
                    .labelsHidden().frame(width: 190)
                }
                Sep()
                ToggleRow(title: "Mirror the preview", subtitle: "Like a real mirror", isOn: $flip)
            }

            Card(title: "On the picture",
                 footer: "Controls only appear while the pointer is over the mirror, so they stay out of screen recordings. Press 1–6 to send a reaction, Space to capture.") {
                ToggleRow(title: "Mic check", subtitle: "A live level meter, to test your mic", isOn: $micMeter)
                Sep()
                ToggleRow(title: "Reactions", subtitle: "Little emoji animations", isOn: $reactions)
            }
        }
    }
}

// MARK: - Icons

private struct IconSettings: View {
    @AppStorage(Key.menuBarIcon) private var menuIcon = MenuBarIcon.handMirror.rawValue
    @AppStorage(Key.showDockIcon) private var showDock = false
    @AppStorage(Key.dockIconStyle) private var dockStyle = DockIconStyle.classic.rawValue

    var body: some View {
        Pane {
            Card(title: "Menu bar icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(MenuBarIcon.available) { option in
                        let selected = menuIcon == option.rawValue
                        Button { menuIcon = option.rawValue } label: {
                            Image(nsImage: IconRenderer.menuBarImage(option))
                                .renderingMode(.template)
                                .resizable().scaledToFit().frame(width: 20, height: 20)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
            }

            Card(title: "Dock icon", footer: "Used whenever Looking Glass shows in the Dock or the app switcher.") {
                ToggleRow(title: "Show in the Dock", isOn: $showDock)
                Sep()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(DockIconStyle.allCases) { style in
                        let selected = dockStyle == style.rawValue
                        Button { dockStyle = style.rawValue } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: IconRenderer.dockIcon(style, size: 64))
                                    .resizable().frame(width: 62, height: 62)
                                    .padding(2)
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                                Text(style.label).font(.caption2).foregroundStyle(selected ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }
}
