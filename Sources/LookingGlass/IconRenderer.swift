import AppKit

/// Draws every icon in code: the menu bar glyph, and the dock/app icon variants.
enum IconRenderer {

    // MARK: Menu bar

    static func menuBarImage(_ option: MenuBarIcon) -> NSImage {
        if let name = option.symbolName,
           let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Looking Glass") {
            let configured = symbol.withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? symbol
            configured.isTemplate = true
            return configured
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawGlyph(in: rect.insetBy(dx: 0.5, dy: 0.5), color: .black, lineWidth: 1.5, tilt: 0, glassFill: nil)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Looking Glass"
        return image
    }

    /// A hand mirror: oval glass ring, solid handle, small highlight arc. Unit-square layout.
    static func drawGlyph(in r: NSRect, color: NSColor, lineWidth lw: CGFloat, tilt: CGFloat, glassFill: NSColor?) {
        func u(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: r.minX + x * r.width, y: r.minY + y * r.height, width: w * r.width, height: h * r.height)
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        if tilt != 0 {
            let t = NSAffineTransform()
            t.translateX(by: r.midX, yBy: r.midY)
            t.rotate(byDegrees: tilt)
            t.translateX(by: -r.midX, yBy: -r.midY)
            t.concat()
        }

        let glass = u(0.14, 0.29, 0.72, 0.70)
        let handle = u(0.425, 0.01, 0.15, 0.30)
        let collar = u(0.375, 0.25, 0.25, 0.08)

        color.setFill()
        NSBezierPath(roundedRect: handle, xRadius: handle.width / 2, yRadius: handle.width / 2).fill()
        NSBezierPath(roundedRect: collar, xRadius: collar.height / 2, yRadius: collar.height / 2).fill()

        let ring = NSBezierPath(ovalIn: glass.insetBy(dx: lw / 2, dy: lw / 2))
        if let fill = glassFill { fill.setFill(); ring.fill() }
        color.setStroke()
        ring.lineWidth = lw
        ring.stroke()

        // Two glare streaks, upper-left of the glass — the cue that says "mirror", not "magnifier".
        func g(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: glass.minX + x * glass.width, y: glass.minY + y * glass.height)
        }
        let streaks = NSBezierPath()
        streaks.move(to: g(0.27, 0.70)); streaks.line(to: g(0.45, 0.86))
        streaks.move(to: g(0.20, 0.52)); streaks.line(to: g(0.33, 0.64))
        streaks.lineWidth = max(lw * 0.85, 1)
        streaks.lineCapStyle = .round
        color.withAlphaComponent(0.8).setStroke()
        streaks.stroke()
    }

    // MARK: Dock / app icon

    private struct Palette { let top: NSColor; let bottom: NSColor; let glyph: NSColor }

    private static func palette(_ s: DockIconStyle) -> Palette {
        func c(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        switch s {
        case .classic: return Palette(top: c(0x7C93FF), bottom: c(0x7B3FF2), glyph: .white)
        case .sunset: return Palette(top: c(0xFFA45C), bottom: c(0xFF3D77), glyph: .white)
        case .mint: return Palette(top: c(0x6BEBC0), bottom: c(0x1D9BC9), glyph: .white)
        case .midnight: return Palette(top: c(0x34396B), bottom: c(0x0A0C1C), glyph: c(0xBFC8FF))
        case .mono: return Palette(top: c(0xF6F6F8), bottom: c(0xC4C7CF), glyph: c(0x2A2C33))
        case .polaroid: return Palette(top: c(0xF3E4CC), bottom: c(0xDDC3A3), glyph: .white)
        }
    }

    static func dockIcon(_ style: DockIconStyle, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            let pal = palette(style)
            let body = rect.insetBy(dx: s * 0.098, dy: s * 0.098)
            let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
            shadow.shadowBlurRadius = s * 0.03
            shadow.set()
            pal.bottom.setFill()
            squircle.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            squircle.addClip()
            NSGradient(starting: pal.top, ending: pal.bottom)?.draw(in: body, angle: -90)
            // Soft top sheen.
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), .clear])?
                .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

            if style == .polaroid {
                drawPolaroidCard(in: body)
            } else {
                let glyphRect = body.insetBy(dx: body.width * 0.17, dy: body.height * 0.13)
                // Drop shadow under the glyph.
                let gs = NSShadow()
                gs.shadowColor = NSColor.black.withAlphaComponent(0.25)
                gs.shadowOffset = NSSize(width: 0, height: -s * 0.012)
                gs.shadowBlurRadius = s * 0.02
                gs.set()
                drawGlyph(in: glyphRect, color: pal.glyph, lineWidth: s * 0.036, tilt: -16,
                          glassFill: pal.glyph.withAlphaComponent(0.18))
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    private static func drawPolaroidCard(in body: NSRect) {
        let w = body.width * 0.56, h = body.width * 0.68
        let card = NSRect(x: body.midX - w / 2, y: body.midY - h / 2, width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: body.midX, yBy: body.midY)
        t.rotate(byDegrees: 7)
        t.translateX(by: -body.midX, yBy: -body.midY)
        t.concat()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -body.width * 0.012)
        shadow.shadowBlurRadius = body.width * 0.03
        shadow.set()
        NSColor(white: 0.99, alpha: 1).setFill()
        NSBezierPath(roundedRect: card, xRadius: w * 0.03, yRadius: w * 0.03).fill()

        NSShadow().set()
        let pad = w * 0.075
        let photo = NSRect(x: card.minX + pad, y: card.maxY - pad - (w - 2 * pad), width: w - 2 * pad, height: w - 2 * pad)
        NSGradient(starting: NSColor(srgbRed: 0.45, green: 0.55, blue: 1, alpha: 1),
                   ending: NSColor(srgbRed: 0.55, green: 0.25, blue: 0.9, alpha: 1))?.draw(in: photo, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: photo).addClip()
        drawGlyph(in: photo.insetBy(dx: photo.width * 0.16, dy: photo.height * 0.1), color: .white,
                  lineWidth: body.width * 0.022, tilt: -12, glassFill: NSColor.white.withAlphaComponent(0.15))
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Export

    static func pngData(of image: NSImage, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
