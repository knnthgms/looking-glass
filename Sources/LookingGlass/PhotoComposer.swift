import AppKit
import CoreGraphics

struct PhotoOptions {
    var zoom = 1.0
    var rotation = 0.0
    var shape = MaskShape.rounded
    var applyMask = true
    var flip = true
    /// width / height of the picture area (not counting the frame).
    var aspect: CGFloat = 1
    var frame = FrameStyle.classic
    var frameScale: CGFloat = 1
    var preset = CaptionPreset.classic
    var showDate = true
    var dateStyle = DateStyleOption.medium
    var showTime = false
    var caption = ""
    var date = Date()
    /// Longest edge of the picture area, in pixels.
    var maxPhotoSide = 2400

    static func fromPrefs(date: Date = Date()) -> PhotoOptions {
        let shape = Prefs.shape
        let format = Prefs.effectiveFormat(Prefs.format, shape: shape)
        return PhotoOptions(zoom: Prefs.zoom, rotation: Prefs.rotation, shape: shape,
                            applyMask: Prefs.maskPhotos, flip: Prefs.flipPhotos,
                            aspect: Prefs.photoAspect(window: format.aspect),
                            frame: Prefs.frameStyle, frameScale: Prefs.frameWidth.scale, preset: Prefs.captionPreset,
                            showDate: Prefs.showDate, dateStyle: Prefs.dateStyle, showTime: Prefs.showTime,
                            caption: Prefs.caption, date: date)
    }

    /// The text lines for the frame, as (string, size relative to the picture's short side).
    var captionLines: [(String, CGFloat)] {
        let spec = preset.spec
        var lines: [(String, CGFloat)] = []
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { lines.append((spec.decorate(trimmed), 0.085 * spec.size)) }
        if showDate {
            var text = dateStyle.format(date)
            if showTime {
                let t = DateFormatter(); t.timeStyle = .short; t.dateStyle = .none
                text += "  ·  " + t.string(from: date)
            }
            lines.append((spec.decorate(text), (trimmed.isEmpty ? 0.085 : 0.062) * spec.size))
        }
        return lines
    }
}

// MARK: - Presets

enum Decor { case none, tape, corners, hearts, stars, rule }

struct CaptionSpec {
    var fonts: [String]
    var size: CGFloat = 1
    var kern: CGFloat = 0
    var uppercase = false
    var ink: NSColor? = nil
    var decor: Decor = .none
    var tilt: CGFloat = 0
    /// Drawn on the photo itself (bottom-right) like a film camera's date back.
    var stampOnPhoto = false

    func decorate(_ text: String) -> String {
        let t = uppercase ? text.uppercased() : text
        switch decor {
        case .hearts: return "♥  \(t)  ♥"
        case .stars: return "✦  \(t)  ✦"
        default: return t
        }
    }

    func font(_ size: CGFloat) -> NSFont {
        for name in fonts { if let f = NSFont(name: name, size: size) { return f } }
        return .systemFont(ofSize: size, weight: .medium)
    }
}

extension CaptionPreset {
    var spec: CaptionSpec {
        switch self {
        case .classic:
            return CaptionSpec(fonts: ["Bradley Hand Bold", "BradleyHandITCTT-Bold", "Noteworthy-Bold"])
        case .typewriter:
            return CaptionSpec(fonts: ["AmericanTypewriter", "AmericanTypewriter-Semibold", "CourierNewPSMT"],
                               size: 0.76, kern: 1.2, decor: .rule)
        case .scrapbook:
            return CaptionSpec(fonts: ["MarkerFelt-Wide", "MarkerFelt-Thin", "Chalkduster"], size: 0.95,
                               ink: NSColor(srgbRed: 0.16, green: 0.30, blue: 0.68, alpha: 1), decor: .tape, tilt: -2)
        case .filmStamp:
            return CaptionSpec(fonts: ["Menlo-Bold", "Courier-Bold"], size: 0.62, kern: 1,
                               ink: NSColor(srgbRed: 1.0, green: 0.55, blue: 0.1, alpha: 1), stampOnPhoto: true)
        case .sweet:
            return CaptionSpec(fonts: ["ChalkboardSE-Bold", "Noteworthy-Bold", "MarkerFelt-Thin"], size: 0.9,
                               ink: NSColor(srgbRed: 0.92, green: 0.34, blue: 0.55, alpha: 1), decor: .hearts)
        case .minimal:
            return CaptionSpec(fonts: ["HelveticaNeue-Light", "HelveticaNeue"], size: 0.55, kern: 3, uppercase: true,
                               ink: NSColor(white: 0.42, alpha: 1))
        case .elegant:
            return CaptionSpec(fonts: ["SnellRoundhand-Bold", "SnellRoundhand", "Zapfino"], size: 1.25,
                               ink: NSColor(srgbRed: 0.5, green: 0.36, blue: 0.14, alpha: 1), decor: .stars)
        }
    }
}

// MARK: - Composer

/// Turns a raw camera frame into the finished photo: the same crop, zoom, rotation and mask as the live
/// view, then a polaroid-style frame with a styled caption.
enum PhotoComposer {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func compose(source: CGImage, options o: PhotoOptions) -> CGImage? {
        guard let photo = croppedPhoto(source: source, options: o) else { return nil }
        return o.frame == .none ? stamped(photo, options: o) : framed(photo: photo, options: o)
    }

    // MARK: Crop

    /// Scale that keeps a rotated viewport (w×h) inside a video drawn at (vw×vh).
    static func coverScale(viewW w: CGFloat, viewH h: CGFloat, videoW vw: CGFloat, videoH vh: CGFloat, theta: CGFloat) -> CGFloat {
        let c = abs(cos(theta)), s = abs(sin(theta))
        return max((w * c + h * s) / vw, (w * s + h * c) / vh, 1)
    }

    static func croppedPhoto(source: CGImage, options o: PhotoOptions) -> CGImage? {
        let a = o.aspect
        var W: CGFloat, H: CGFloat
        if a >= 1 { W = CGFloat(min(o.maxPhotoSide, source.width)); H = W / a }
        else { H = CGFloat(min(o.maxPhotoSide, source.height)); W = H * a }
        W = W.rounded(); H = H.rounded()

        guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let full = CGRect(x: 0, y: 0, width: W, height: H)

        if o.applyMask {
            switch o.shape {
            case .rounded:
                let r = min(W, H) * (o.frame == .none ? 0.07 : 0.025)
                ctx.addPath(CGPath(roundedRect: full, cornerWidth: r, cornerHeight: r, transform: nil)); ctx.clip()
            case .circle:
                ctx.addPath(CGPath(ellipseIn: full, transform: nil)); ctx.clip()
            }
        }

        // Aspect-fill the video into the picture area (mirrors the live preview exactly).
        let va = CGFloat(source.width) / CGFloat(source.height)
        let (vw, vh): (CGFloat, CGFloat) = va >= W / H ? (H * va, H) : (W, W / va)
        let theta = -CGFloat(o.rotation) * .pi / 180   // positive = clockwise
        let cover = o.shape == .circle ? 1 : coverScale(viewW: W, viewH: H, videoW: vw, videoH: vh, theta: theta)
        let scale = CGFloat(o.zoom) * cover

        ctx.translateBy(x: W / 2, y: H / 2)
        ctx.rotate(by: theta)
        ctx.scaleBy(x: scale, y: scale)
        if o.flip { ctx.scaleBy(x: -1, y: 1) }
        ctx.draw(source, in: CGRect(x: -vw / 2, y: -vh / 2, width: vw, height: vh))
        return ctx.makeImage()
    }

    // MARK: Frame

    struct Look { let paper: NSColor; let ink: NSColor; let well: NSColor; let dark: Bool }

    static func look(_ f: FrameStyle) -> Look {
        switch f {
        case .classic, .none:
            return Look(paper: NSColor(srgbRed: 0.975, green: 0.972, blue: 0.96, alpha: 1),
                        ink: NSColor(srgbRed: 0.18, green: 0.19, blue: 0.26, alpha: 0.92),
                        well: NSColor(white: 0.1, alpha: 1), dark: false)
        case .vintage:
            return Look(paper: NSColor(srgbRed: 0.955, green: 0.915, blue: 0.82, alpha: 1),
                        ink: NSColor(srgbRed: 0.36, green: 0.22, blue: 0.12, alpha: 0.92),
                        well: NSColor(srgbRed: 0.16, green: 0.1, blue: 0.06, alpha: 1), dark: false)
        case .midnight:
            return Look(paper: NSColor(srgbRed: 0.075, green: 0.075, blue: 0.09, alpha: 1),
                        ink: NSColor(white: 0.92, alpha: 0.92), well: NSColor(white: 0.03, alpha: 1), dark: true)
        }
    }

    /// Margins as fractions of the picture's width.
    static func margins(photoW W: CGFloat, photoH H: CGFloat, scale: CGFloat = 1) -> (side: CGFloat, top: CGFloat, bottom: CGFloat) {
        let side = (W * 0.07 * scale).rounded()
        // The caption strip never gets so thin that text can't fit.
        return (side, side, max(W * 0.22, min(W, H) * 0.30).rounded() * max(scale, 0.8))
    }

    static func inkColor(_ spec: CaptionSpec, _ look: Look) -> NSColor {
        guard let ink = spec.ink else { return look.ink }
        // Dark inks vanish on black paper, so fall back to the paper's own ink there.
        let l = ink.usingColorSpace(.sRGB).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent } ?? 0.5
        return look.dark && l < 0.5 ? look.ink : ink
    }

    static func framed(photo: CGImage, options o: PhotoOptions) -> CGImage? {
        let pw = CGFloat(photo.width), ph = CGFloat(photo.height)
        let m = margins(photoW: pw, photoH: ph, scale: o.frameScale)
        let W = Int(pw + m.side * 2), H = Int(ph + m.top + m.bottom)
        let look = look(o.frame)
        let spec = o.preset.spec

        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high

        ctx.setFillColor(look.paper.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        if let g = CGGradient(colorsSpace: sRGB,
                              colors: [NSColor.black.withAlphaComponent(0.05).cgColor,
                                       NSColor.white.withAlphaComponent(look.dark ? 0.03 : 0.25).cgColor] as CFArray,
                              locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: CGFloat(H)), options: [])
        }

        let photoRect = CGRect(x: m.side, y: m.bottom, width: pw, height: ph)
        let masked = o.applyMask   // rounded / circle photos sit straight on the paper
        if !masked {
            ctx.setFillColor(look.well.cgColor)
            ctx.fill(photoRect)
        }
        ctx.draw(photo, in: photoRect)
        if !masked {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
            ctx.setLineWidth(max(pw / 800, 1))
            ctx.stroke(photoRect.insetBy(dx: -0.5, dy: -0.5))
        }

        let P = min(pw, ph)
        let band = CGRect(x: 0, y: 0, width: CGFloat(W), height: m.bottom)
        if spec.stampOnPhoto { drawStamp(in: ctx, photoRect: photoRect, P: P, options: o, spec: spec) }
        else { drawCaption(in: ctx, band: band, P: P, ink: inkColor(spec, look), options: o, spec: spec) }
        drawDecor(in: ctx, spec: spec, canvas: CGSize(width: W, height: H), photoRect: photoRect, band: band, look: look, P: P)
        return ctx.makeImage()
    }

    /// Frameless photos still get a film-stamp date if that preset is chosen.
    static func stamped(_ photo: CGImage, options o: PhotoOptions) -> CGImage? {
        let spec = o.preset.spec
        guard spec.stampOnPhoto, !o.captionLines.isEmpty,
              let ctx = CGContext(data: nil, width: photo.width, height: photo.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return photo }
        let rect = CGRect(x: 0, y: 0, width: photo.width, height: photo.height)
        ctx.draw(photo, in: rect)
        drawStamp(in: ctx, photoRect: rect, P: min(rect.width, rect.height), options: o, spec: spec)
        return ctx.makeImage()
    }

    // MARK: Text & decor

    private static func drawCaption(in ctx: CGContext, band: CGRect, P: CGFloat, ink: NSColor, options o: PhotoOptions, spec: CaptionSpec) {
        let lines = o.captionLines
        guard !lines.isEmpty else { return }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let rendered = lines.map { text, size in
            NSAttributedString(string: text, attributes: [
                .font: spec.font(P * size), .foregroundColor: ink, .paragraphStyle: para, .kern: spec.kern * P / 400])
        }
        let heights = rendered.map { $0.size().height }
        let total = heights.reduce(0, +)
        var y = band.midY + total / 2 - P * 0.015

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ctx.saveGState()
        ctx.translateBy(x: band.midX, y: band.midY)
        ctx.rotate(by: spec.tilt * .pi / 180)
        ctx.translateBy(x: -band.midX, y: -band.midY)
        for (str, h) in zip(rendered, heights) {
            y -= h
            str.draw(in: CGRect(x: P * 0.05, y: y, width: band.width - P * 0.1, height: h))
        }
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Orange date-back lettering, bottom-right of the picture.
    private static func drawStamp(in ctx: CGContext, photoRect: CGRect, P: CGFloat, options o: PhotoOptions, spec: CaptionSpec) {
        let text = o.captionLines.map(\.0).joined(separator: "   ")
        guard !text.isEmpty, let ink = spec.ink else { return }
        let font = spec.font(P * 0.05)
        let shadow = NSShadow()
        shadow.shadowColor = ink.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = P * 0.012
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .shadow: shadow, .kern: 1])
        let size = str.size()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: CGPoint(x: photoRect.maxX - size.width - P * 0.05, y: photoRect.minY + P * 0.045))
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawDecor(in ctx: CGContext, spec: CaptionSpec, canvas: CGSize, photoRect: CGRect, band: CGRect, look: Look, P: CGFloat) {
        switch spec.decor {
        case .tape:
            ctx.saveGState()
            ctx.translateBy(x: canvas.width / 2, y: canvas.height - P * 0.05)
            ctx.rotate(by: -4 * .pi / 180)
            let tape = CGRect(x: -P * 0.15, y: -P * 0.04, width: P * 0.3, height: P * 0.085)
            ctx.setFillColor(NSColor(srgbRed: 1.0, green: 0.88, blue: 0.4, alpha: 0.82).cgColor)
            ctx.fill(tape)
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            ctx.fill(CGRect(x: tape.minX, y: tape.midY - P * 0.006, width: tape.width, height: P * 0.012))
            ctx.restoreGState()
        case .corners:
            let c = P * 0.09
            ctx.setFillColor(NSColor(white: 0.16, alpha: 0.9).cgColor)
            for (x, y, dx, dy) in [(photoRect.minX, photoRect.minY, 1.0, 1.0), (photoRect.maxX, photoRect.minY, -1.0, 1.0),
                                   (photoRect.minX, photoRect.maxY, 1.0, -1.0), (photoRect.maxX, photoRect.maxY, -1.0, -1.0)] {
                ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + dx * c, y: y))
                ctx.addLine(to: CGPoint(x: x, y: y + dy * c)); ctx.closePath()
            }
            ctx.fillPath()
        case .rule:
            ctx.setStrokeColor(look.ink.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(max(P / 500, 1))
            let y = band.maxY - P * 0.06
            ctx.move(to: CGPoint(x: canvas.width * 0.3, y: y)); ctx.addLine(to: CGPoint(x: canvas.width * 0.7, y: y))
            ctx.strokePath()
        case .hearts, .stars, .none:
            break   // glyphs are part of the text itself (see CaptionSpec.decorate)
        }
    }

    // MARK: Encoding

    static func encode(_ image: CGImage, as format: ImageFileFormat) -> Data? {
        var cg = image
        if format == .jpeg { cg = flattenedOnWhite(image) ?? image }
        let rep = NSBitmapImageRep(cgImage: cg)
        switch format {
        case .png: return rep.representation(using: .png, properties: [:])
        case .jpeg: return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.93])
        }
    }

    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        let r = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.fill(r)
        ctx.draw(image, in: r)
        return ctx.makeImage()
    }
}
