import SwiftUI

/// UserDefaults keys. SwiftUI reads them through @AppStorage, AppKit code through `Prefs`.
enum Key {
    static let menuBarIcon = "menuBarIcon"
    static let hideMenuBarIcon = "hideMenuBarIcon"
    static let showDockIcon = "showDockIcon"
    static let dockIconStyle = "dockIconStyle"
    static let shape = "shape"
    static let zoom = "zoom"
    static let rotation = "rotation"
    static let mirrorSize = "mirrorSize"
    static let format = "format"
    static let customAspect = "customAspect"
    static let photoAspect = "photoAspect"
    static let frameWidth = "frameWidth"
    static let captionPreset = "captionPreset"
    static let windowOpacity = "windowOpacity"
    static let flipPreview = "flipPreview"
    static let cameraID = "cameraID"
    static let flipPhotos = "flipPhotos"
    static let maskPhotos = "maskPhotos"
    static let saveFolder = "saveFolder"
    static let autoSave = "autoSave"
    static let frameStyle = "frameStyle"
    static let showDate = "showDate"
    static let dateFormat = "dateFormat"
    static let showTime = "showTime"
    static let caption = "caption"
    static let fileFormat = "fileFormat"
    static let shutterSound = "shutterSound"
    static let flashEffect = "flashEffect"
    static let countdown = "countdown"
    static let notchTrigger = "notchTrigger"
    static let notchAutoHide = "notchAutoHide"
    static let micMeter = "micMeter"
    static let reactions = "reactions"
    static let poppedOut = "poppedOut"
    static let reopenPoppedOut = "reopenPoppedOut"
    static let panelTopLeft = "panelTopLeft"
}

enum MaskShape: String, CaseIterable, Identifiable {
    case rounded, circle
    var id: String { rawValue }
    var label: String { self == .rounded ? "Rounded" : "Circle" }
    var detail: String { self == .rounded ? "Standard window" : "Round view" }
    var symbol: String { self == .rounded ? "app" : "circle" }
}

/// The window's proportions. Photos can follow them or use their own (see `Prefs.photoAspect`).
enum WindowFormat: String, CaseIterable, Identifiable {
    case square, portrait, phonePortrait, landscape, phoneLandscape, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .square: "Square"
        case .portrait: "Portrait"
        case .phonePortrait: "Phone"
        case .landscape: "Landscape"
        case .phoneLandscape: "Wide"
        case .custom: "Custom"
        }
    }
    var detail: String {
        switch self {
        case .square: "1 : 1"
        case .portrait: "3 : 4"
        case .phonePortrait: "9 : 16"
        case .landscape: "4 : 3"
        case .phoneLandscape: "16 : 9"
        case .custom: "Drag to shape"
        }
    }
    /// width / height of the whole window.
    var aspect: CGFloat {
        switch self {
        case .square: 1
        case .portrait: 3.0 / 4
        case .phonePortrait: 9.0 / 16
        case .landscape: 4.0 / 3
        case .phoneLandscape: 16.0 / 9
        case .custom: Prefs.customAspect
        }
    }
}

enum FrameWidth: String, CaseIterable, Identifiable {
    case thin, regular, wide
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var scale: CGFloat { switch self { case .thin: 0.55; case .regular: 1; case .wide: 1.5 } }
}

enum SizePreset: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var value: Double { switch self { case .small: 240; case .medium: 320; case .large: 440 } }
}

/// Text and decoration styles for the white space of a photo frame.
enum CaptionPreset: String, CaseIterable, Identifiable {
    case classic, typewriter, scrapbook, filmStamp, sweet, minimal, elegant
    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: "Classic"
        case .typewriter: "Typewriter"
        case .scrapbook: "Scrapbook"
        case .filmStamp: "Film stamp"
        case .sweet: "Sweet"
        case .minimal: "Minimal"
        case .elegant: "Elegant"
        }
    }
}

enum FrameStyle: String, CaseIterable, Identifiable {
    case classic, vintage, midnight, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: "Classic white"
        case .vintage: "Vintage cream"
        case .midnight: "Midnight black"
        case .none: "No frame"
        }
    }
}

enum DateStyleOption: String, CaseIterable, Identifiable {
    case medium, long, short, iso, retro
    var id: String { rawValue }

    func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        switch self {
        case .medium: f.dateStyle = .medium
        case .long: f.dateStyle = .long
        case .short: f.dateStyle = .short
        case .iso: f.dateFormat = "yyyy-MM-dd"
        case .retro: f.dateFormat = "dd.MM.yy"
        }
        return f.string(from: date)
    }
}

enum ImageFileFormat: String, CaseIterable, Identifiable {
    case png, jpeg
    var id: String { rawValue }
    var label: String { self == .png ? "PNG" : "JPEG" }
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

enum MenuBarIcon: String, CaseIterable, Identifiable {
    case handMirror, ovalPortrait, camera, face, eye, sparkles, viewfinder, person, aperture
    var id: String { rawValue }
    /// nil → the custom-drawn hand mirror.
    var symbolName: String? {
        switch self {
        case .handMirror: nil
        case .ovalPortrait: "oval.portrait"
        case .camera: "camera.fill"
        case .face: "face.smiling"
        case .eye: "eye"
        case .sparkles: "sparkles"
        case .viewfinder: "viewfinder.circle"
        case .person: "person.crop.circle"
        case .aperture: "camera.aperture"
        }
    }
    /// Skips symbols this macOS doesn't ship.
    static var available: [MenuBarIcon] {
        allCases.filter { opt in
            guard let name = opt.symbolName else { return true }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        }
    }
}

enum DockIconStyle: String, CaseIterable, Identifiable {
    case classic, sunset, mint, midnight, mono, polaroid
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Prefs {
    private static var d: UserDefaults { .standard }

    static var defaultSaveFolder: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Pictures/Looking Glass")
    }

    static func registerDefaults() {
        d.register(defaults: [
            Key.menuBarIcon: MenuBarIcon.handMirror.rawValue,
            Key.hideMenuBarIcon: false,
            Key.showDockIcon: false,
            Key.dockIconStyle: DockIconStyle.classic.rawValue,
            Key.shape: MaskShape.rounded.rawValue,
            Key.zoom: 1.0,
            Key.rotation: 0.0,
            Key.mirrorSize: 320.0,
            Key.format: WindowFormat.square.rawValue,
            Key.customAspect: 1.25,
            Key.photoAspect: "match",
            Key.frameWidth: FrameWidth.regular.rawValue,
            Key.captionPreset: CaptionPreset.classic.rawValue,
            Key.windowOpacity: 1.0,
            Key.flipPreview: true,
            Key.cameraID: "",
            Key.flipPhotos: true,
            Key.maskPhotos: true,
            Key.saveFolder: defaultSaveFolder,
            Key.autoSave: true,
            Key.frameStyle: FrameStyle.classic.rawValue,
            Key.showDate: true,
            Key.dateFormat: DateStyleOption.medium.rawValue,
            Key.showTime: false,
            Key.caption: "",
            Key.fileFormat: ImageFileFormat.png.rawValue,
            Key.shutterSound: true,
            Key.flashEffect: true,
            Key.countdown: 0,
            Key.notchTrigger: false,
            Key.notchAutoHide: true,
            Key.micMeter: false,
            Key.reactions: true,
            Key.poppedOut: false,
            Key.reopenPoppedOut: true,
        ])
    }

    static var menuBarIcon: MenuBarIcon { MenuBarIcon(rawValue: d.string(forKey: Key.menuBarIcon) ?? "") ?? .handMirror }
    static var hideMenuBarIcon: Bool { d.bool(forKey: Key.hideMenuBarIcon) }
    static var showDockIcon: Bool { d.bool(forKey: Key.showDockIcon) }
    static var dockIconStyle: DockIconStyle { DockIconStyle(rawValue: d.string(forKey: Key.dockIconStyle) ?? "") ?? .classic }
    static var shape: MaskShape { MaskShape(rawValue: d.string(forKey: Key.shape) ?? "") ?? .rounded }   // old "square" falls back to rounded
    static var zoom: Double { d.double(forKey: Key.zoom) }
    static var rotation: Double { d.double(forKey: Key.rotation) }
    static var mirrorSize: CGFloat { CGFloat(d.double(forKey: Key.mirrorSize)) }
    static var customAspect: CGFloat { min(2.5, max(0.4, CGFloat(d.double(forKey: Key.customAspect)))) }
    static var frameWidth: FrameWidth { FrameWidth(rawValue: d.string(forKey: Key.frameWidth) ?? "") ?? .regular }
    /// "match" follows the window; otherwise the photo uses that format's proportions.
    static func photoAspect(window: CGFloat) -> CGFloat {
        let raw = d.string(forKey: Key.photoAspect) ?? "match"
        if raw == "match" { return window }
        return (WindowFormat(rawValue: raw) ?? .square).aspect
    }
    static var format: WindowFormat { WindowFormat(rawValue: d.string(forKey: Key.format) ?? "") ?? .square }
    static var captionPreset: CaptionPreset { CaptionPreset(rawValue: d.string(forKey: Key.captionPreset) ?? "") ?? .classic }

    /// A circle needs a square window, so it overrides the chosen format.
    static func effectiveFormat(_ f: WindowFormat, shape: MaskShape) -> WindowFormat { shape == .circle ? .square : f }

    /// Window size in points. `size` is the "area" size: width × height == size², so every format
    /// feels equally big, with a floor so the controls always fit.
    static func dimensions(format: WindowFormat, size: CGFloat) -> CGSize {
        let a = format.aspect
        var w = size * a.squareRoot(), h = size / a.squareRoot()
        let scale = max(1, 210 / min(w, h))
        w *= scale; h *= scale
        return CGSize(width: w.rounded(), height: h.rounded())
    }
    static var windowDimensions: CGSize {
        dimensions(format: effectiveFormat(format, shape: shape), size: mirrorSize)
    }
    static var windowOpacity: Double { d.double(forKey: Key.windowOpacity) }
    static var flipPhotos: Bool { d.bool(forKey: Key.flipPhotos) }
    static var maskPhotos: Bool { d.bool(forKey: Key.maskPhotos) }
    static var saveFolder: String { d.string(forKey: Key.saveFolder) ?? defaultSaveFolder }
    static var autoSave: Bool { d.bool(forKey: Key.autoSave) }
    static var frameStyle: FrameStyle { FrameStyle(rawValue: d.string(forKey: Key.frameStyle) ?? "") ?? .classic }
    static var showDate: Bool { d.bool(forKey: Key.showDate) }
    static var dateStyle: DateStyleOption { DateStyleOption(rawValue: d.string(forKey: Key.dateFormat) ?? "") ?? .medium }
    static var showTime: Bool { d.bool(forKey: Key.showTime) }
    static var caption: String { d.string(forKey: Key.caption) ?? "" }
    static var fileFormat: ImageFileFormat { ImageFileFormat(rawValue: d.string(forKey: Key.fileFormat) ?? "") ?? .png }
    static var shutterSound: Bool { d.bool(forKey: Key.shutterSound) }
    static var flashEffect: Bool { d.bool(forKey: Key.flashEffect) }
    static var countdown: Int { d.integer(forKey: Key.countdown) }
    static var notchTrigger: Bool { d.bool(forKey: Key.notchTrigger) }
    static var notchAutoHide: Bool { d.bool(forKey: Key.notchAutoHide) }
    static var micMeter: Bool { d.bool(forKey: Key.micMeter) }
    static var reopenPoppedOut: Bool { d.bool(forKey: Key.reopenPoppedOut) }

    static var poppedOut: Bool {
        get { d.bool(forKey: Key.poppedOut) }
        set { d.set(newValue, forKey: Key.poppedOut) }
    }
    /// Top-left corner of the pop-out window (top-left, so it stays put when the settings drawer opens).
    static var panelTopLeft: NSPoint? {
        get { d.string(forKey: Key.panelTopLeft).map(NSPointFromString) }
        set { d.set(newValue.map(NSStringFromPoint), forKey: Key.panelTopLeft) }
    }
}
