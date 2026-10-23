import AppKit
import SwiftUI

/// `LookingGlass --selftest <dir>` renders sample photos, icons and UI so they can be inspected without a camera.
enum DevTools {
    /// Set by `--selftest` so the hover-only controls can be rendered offscreen.
    nonisolated(unsafe) static var forceControls = false

    @MainActor static func render<V: View>(_ root: V, size: NSSize, to url: URL) {
        let view = NSHostingView(rootView: root)
        view.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    static func run(outputDirectory dir: String) {
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Prefs.registerDefaults()

        let sample = sampleFrame()
        func save(_ cg: CGImage?, _ name: String) {
            guard let cg, let data = PhotoComposer.encode(cg, as: .png) else { print("failed: \(name)"); return }
            try? data.write(to: out.appendingPathComponent(name))
        }

        // Every caption preset, plus a few format / frame / mask combinations.
        var o = PhotoOptions()
        o.maxPhotoSide = 600
        o.caption = ""
        for p in CaptionPreset.allCases {
            o.preset = p
            save(PhotoComposer.compose(source: sample, options: o), "preset-\(p.rawValue).png")
        }
        o.preset = .scrapbook; o.caption = "Hello"
        for f in [WindowFormat.portrait, .phoneLandscape, .phonePortrait] {
            o.aspect = f.aspect
            save(PhotoComposer.compose(source: sample, options: o), "format-\(f.rawValue).png")
        }
        o.aspect = 1; o.shape = .circle; o.zoom = 1.4; o.rotation = 20; o.preset = .sweet; o.frame = .vintage; o.showTime = true
        save(PhotoComposer.compose(source: sample, options: o), "photo-circle-rotated.png")
        o.shape = .rounded; o.frame = .midnight; o.preset = .filmStamp; o.rotation = 30
        save(PhotoComposer.compose(source: sample, options: o), "photo-midnight-stamp.png")
        o.frame = .none; o.preset = .filmStamp
        save(PhotoComposer.compose(source: sample, options: o), "photo-frameless-stamp.png")

        for style in DockIconStyle.allCases {
            let data = IconRenderer.pngData(of: IconRenderer.dockIcon(style, size: 256), pixels: 256)
            try? data?.write(to: out.appendingPathComponent("dock-\(style.rawValue).png"))
        }

        forceControls = true
        let defaults = UserDefaults.standard
        MainActor.assumeIsolated {
            for (format, shape, name) in [(WindowFormat.square, MaskShape.rounded, "square"),
                                          (.portrait, .rounded, "portrait"),
                                          (.phonePortrait, .rounded, "phone"),
                                          (.phoneLandscape, .rounded, "wide"),
                                          (.square, .circle, "circle")] {
                defaults.set(format.rawValue, forKey: Key.format)
                defaults.set(shape.rawValue, forKey: Key.shape)
                let dims = Prefs.windowDimensions
                render(MirrorView(host: .panel), size: NSSize(width: dims.width, height: dims.height),
                       to: out.appendingPathComponent("view-\(name).png"))
            }
            defaults.set(WindowFormat.square.rawValue, forKey: Key.format)
            defaults.set(MaskShape.rounded.rawValue, forKey: Key.shape)

            // The island, fully open.
            let model = IslandModel()
            model.content = Prefs.windowDimensions
            model.expanded = true
            render(IslandRoot(model: model).background(Color(white: 0.45)), size: model.windowSize, to: out.appendingPathComponent("island.png"))

            // Window with the settings drawer open.
            defaults.set(WindowFormat.square.rawValue, forKey: Key.format)
            AppController.shared.settingsOpen = true
            let total = PanelLayout.size(mirror: Prefs.windowDimensions, settingsOpen: true)
            render(PanelRoot(), size: total, to: out.appendingPathComponent("drawer.png"))
            AppController.shared.settingsOpen = false
            for pane in SettingsPane.allCases {
                render(SettingsDetail(pane: pane).background(Color(nsColor: .windowBackgroundColor)),
                       size: NSSize(width: PanelLayout.settingsWidth, height: pane == .photos ? 1500 : 620), to: out.appendingPathComponent("settings-\(pane.rawValue).png"))
            }
            for k in [Key.format, Key.shape, Key.captionPreset] { defaults.removeObject(forKey: k) }
        }
        print("wrote samples to \(out.path)")
    }

    /// A 16:9 test card with an off-centre face-ish blob so crops/rotation are visible.
    static func sampleFrame() -> CGImage {
        let w = 1920, h = 1080
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: PhotoComposer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: PhotoComposer.sRGB,
                           colors: [NSColor(srgbRed: 0.98, green: 0.62, blue: 0.4, alpha: 1).cgColor,
                                    NSColor(srgbRed: 0.25, green: 0.3, blue: 0.7, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: CGFloat(w), y: 0), options: [])
        ctx.setFillColor(NSColor(white: 1, alpha: 0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: 700, y: 250, width: 520, height: 620))
        ctx.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: 800, y: 560, width: 70, height: 70))
        ctx.fillEllipse(in: CGRect(x: 1050, y: 560, width: 70, height: 70))
        ctx.setFillColor(NSColor.systemRed.cgColor)            // marker on the LEFT, to verify mirroring
        ctx.fill(CGRect(x: 40, y: 40, width: 200, height: 200))
        return ctx.makeImage()!
    }
}
