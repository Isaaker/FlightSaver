import AppKit
import ScreenSaver

// Siluetas apuntando hacia arriba (coordenadas locales, y hacia abajo).
enum Glyphs {
    private static func make(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }

    static let jet: CGPath = make([
        (0, -9), (1.6, -3), (9, 2), (9, 4), (1.6, 2), (1.2, 6.5), (4, 8), (4, 9.5),
        (0, 8.5), (-4, 9.5), (-4, 8), (-1.2, 6.5), (-1.6, 2), (-9, 4), (-9, 2), (-1.6, -3),
    ])

    static let light: CGPath = make([
        (0, -8), (1.3, -5), (1.3, -1.5), (9.5, -1), (9.5, 1.5), (1.3, 2), (1.0, 6), (4, 6.5),
        (4, 8.2), (0, 7.6), (-4, 8.2), (-4, 6.5), (-1.0, 6), (-1.3, 2), (-9.5, 1.5), (-9.5, -1),
        (-1.3, -1.5), (-1.3, -5),
    ])
}

@objc(FlightSaverView)
final class FlightSaverView: ScreenSaverView {
    private var settings = Settings()
    private var running = false
    private var redrawTimer: Timer?
    private var stopObserver: NSObjectProtocol?
    private var configController: ConfigController?

    private var mapImage: CGImage?
    private var mapSignature = ""
    private var mapIncomplete = false
    private var featuredHex: String?
    private var featuredSlot = -1
    private var featuredPhotoRect = CGRect.zero
    private var featuredPhotoLink: URL?
    private static let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.85)
        s.shadowBlurRadius = 4
        s.shadowOffset = NSSize(width: 0, height: 0)
        return s
    }()

    // MARK: Inicio

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Workaround conocido: legacyScreenSaver no siempre destruye la vista al salir.
        stopObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screensaver.willstop"),
            object: nil, queue: .main
        ) { [weak self] _ in
            if self?.isPreview == false { NSApp.terminate(nil) }
        }
    }

    deinit {
        stopRunning()
        if let o = stopObserver { DistributedNotificationCenter.default().removeObserver(o) }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    // En macOS 26 startAnimation no siempre se llama: arrancamos también al entrar en una ventana.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startRunning() } else { stopRunning() }
    }
    override func startAnimation() { super.startAnimation(); startRunning() }
    override func stopAnimation() { super.stopAnimation(); stopRunning() }

    private func startRunning() {
        guard !running else { return }
        running = true
        settings = Settings.load()
        mapSignature = ""
        FlightFeed.shared.start(settings: settings, radiusNm: Int(queryRadiusNm().rounded(.up)))
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        RunLoop.main.add(t, forMode: .common)
        redrawTimer = t
    }

    private func stopRunning() {
        guard running else { return }
        running = false
        redrawTimer?.invalidate()
        redrawTimer = nil
        FlightFeed.shared.stop()
    }

    // MARK: Geometría

    private var uiScale: CGFloat { min(max(bounds.width / 1512, 0.45), 1.8) }

    private var metersPerPoint: Double {
        156543.03392 * cos(settings.lat * .pi / 180) / pow(2.0, settings.zoom)
    }

    private func queryRadiusNm() -> Double {
        let halfDiag = Double(hypot(bounds.width, bounds.height)) / 2
        return min(250, max(10, halfDiag * metersPerPoint / 1852.0 * 1.05))
    }

    private func screenPoint(lat: Double, lon: Double) -> CGPoint {
        let p = Geo.worldPx(lat: lat, lon: lon, z: settings.zoom)
        let c = Geo.worldPx(lat: settings.lat, lon: settings.lon, z: settings.zoom)
        return CGPoint(x: bounds.midX + CGFloat(p.x - c.x), y: bounds.midY + CGFloat(p.y - c.y))
    }

    // MARK: Color por altitud

    private func altColor(_ alt: Double) -> NSColor {
        let t = min(max(alt / 40000.0, 0), 1)
        return NSColor(calibratedHue: CGFloat(0.04 + 0.62 * t), saturation: 0.85, brightness: 1.0, alpha: 1)
    }

    private func color(for a: Aircraft) -> NSColor {
        if a.onGround { return NSColor(white: 0.6, alpha: 1) }
        return altColor(a.alt ?? 0)
    }

    // MARK: Texto y paneles

    @discardableResult
    private func drawText(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat,
                          weight: NSFont.Weight = .regular, color: NSColor = .white,
                          mono: Bool = false, align: NSTextAlignment = .left,
                          shadow: Bool = false) -> CGSize {
        let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                        : NSFont.systemFont(ofSize: size, weight: weight)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if shadow { attrs[.shadow] = FlightSaverView.textShadow }
        let str = s as NSString
        let sz = str.size(withAttributes: attrs)
        var ox = x
        if align == .right { ox = x - sz.width } else if align == .center { ox = x - sz.width / 2 }
        str.draw(at: CGPoint(x: ox, y: y), withAttributes: attrs)
        return sz
    }

    private func panel(_ r: CGRect, radius: CGFloat) {
        let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.065, alpha: 0.78).setFill()
        p.fill()
        NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
        p.lineWidth = 1
        p.stroke()
    }

    // MARK: Mapa base (se renderiza a un bitmap y solo se rehace cuando cambia algo)

    private func ensureMapImage() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let retryBucket = mapIncomplete ? Int(Date().timeIntervalSince1970 / 20) : 0
        let sig = "\(Int(bounds.width))x\(Int(bounds.height))|\(TileStore.shared.version)|\(retryBucket)|\(settings.zoom)|\(settings.lat)|\(settings.lon)|\(settings.rings)|\(settings.mapStyle)|\(settings.mapApiKey.hashValue)"
        if sig == mapSignature && mapImage != nil { return }
        mapSignature = sig
        renderMapImage()
    }

    private func renderMapImage() {
        let w = bounds.width, h = bounds.height
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pw = Int(w * scale), ph = Int(h * scale)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let cg = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: info) else { return }
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: h)
        cg.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        NSColor(calibratedRed: 0.035, green: 0.045, blue: 0.065, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
        mapIncomplete = false
        drawTiles()
        if settings.rings { drawRings(cg) }
        drawVignette(cg)
        NSGraphicsContext.restoreGraphicsState()

        mapImage = cg.makeImage()
    }

    private func drawTiles() {
        let tz = min(max(Int(settings.zoom.rounded()), 1), 18)
        let scale = pow(2.0, settings.zoom - Double(tz))
        let c = Geo.worldPx(lat: settings.lat, lon: settings.lon, z: Double(tz))
        let n = 1 << tz
        let w = Double(bounds.width), h = Double(bounds.height)
        let x0 = Int(floor((c.x - w / 2 / scale) / 256.0))
        let x1 = Int(floor((c.x + w / 2 / scale) / 256.0))
        let y0 = Int(floor((c.y - h / 2 / scale) / 256.0))
        let y1 = Int(floor((c.y + h / 2 / scale) / 256.0))
        guard x1 >= x0, y1 >= y0 else { return }

        for ty in y0...y1 where ty >= 0 && ty < n {
            for tx in x0...x1 {
                let wrapped = ((tx % n) + n) % n
                guard let img = TileStore.shared.image(z: tz, x: wrapped, y: ty,
                                                       style: settings.mapStyle, apiKey: settings.mapApiKey) else {
                    mapIncomplete = true
                    continue
                }
                let sx = Double(bounds.midX) + (Double(tx) * 256.0 - c.x) * scale
                let sy = Double(bounds.midY) + (Double(ty) * 256.0 - c.y) * scale
                let size = 256.0 * scale + 0.5      // +0.5 evita rendijas entre tiles
                img.draw(in: NSRect(x: CGFloat(sx), y: CGFloat(sy), width: CGFloat(size), height: CGFloat(size)),
                         from: .zero, operation: .sourceOver, fraction: 1.0,
                         respectFlipped: true, hints: nil)
            }
        }
    }

    private func drawRings(_ cg: CGContext) {
        let u = uiScale
        let ptsPerNm = 1852.0 / metersPerPoint
        let steps: [Double] = [1, 2, 5, 10, 20, 25, 50, 100]
        guard let step = steps.first(where: { $0 * ptsPerNm >= 110 * Double(u) }) else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let maxR = Double(hypot(bounds.width, bounds.height)) / 2

        cg.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: [4, 6])
        var k = 1
        while Double(k) * step * ptsPerNm < maxR && k < 12 {
            let r = CGFloat(Double(k) * step * ptsPerNm)
            cg.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            drawText("\(Int(Double(k) * step)) NM", x: c.x + 6 * u, y: c.y - r - 15 * u, size: 10 * u,
                     weight: .medium, color: NSColor.white.withAlphaComponent(0.38))
            k += 1
        }
        cg.setLineDash(phase: 0, lengths: [])
    }

    private func drawVignette(_ cg: CGContext) {
        let colors = [NSColor.black.withAlphaComponent(0).cgColor,
                      NSColor.black.withAlphaComponent(0).cgColor,
                      NSColor.black.withAlphaComponent(0.6).cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let r = hypot(bounds.width, bounds.height) / 2
        cg.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: .drawsAfterEndLocation)
    }

    // MARK: Dibujo principal

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()

        ensureMapImage()
        if let img = mapImage {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(origin: .zero, size: bounds.size))
            ctx.restoreGState()
        }

        let now = Date()
        let list = FlightFeed.shared.aircraft.values.sorted { ($0.alt ?? -1) < ($1.alt ?? -1) }   // los más altos encima
        if settings.trails { drawTrails(ctx, list, now) }
        let featured = pickFeatured(list, now)
        drawAircraft(ctx, list, now)
        drawHome(ctx)
        if bounds.width >= 700 && settings.hud { drawHUD(list, featured) }
        drawBanner(now)
        drawFooter(count: list.count)
    }

    private func drawTrails(_ ctx: CGContext, _ list: [Aircraft], _ now: Date) {
        ctx.setLineWidth(1.3 * uiScale)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        for a in list where a.trail.count > 1 {
            var pts = a.trail.map { screenPoint(lat: $0.lat, lon: $0.lon) }
            let cur = a.displayed(at: now)
            pts.append(screenPoint(lat: cur.lat, lon: cur.lon))
            let mid = pts.count / 2
            let col = color(for: a)

            ctx.beginPath()
            ctx.move(to: pts[0])
            for p in pts[1...mid] { ctx.addLine(to: p) }
            ctx.setStrokeColor(col.withAlphaComponent(0.16).cgColor)
            ctx.strokePath()

            ctx.beginPath()
            ctx.move(to: pts[mid])
            for p in pts[(mid + 1)...] { ctx.addLine(to: p) }
            ctx.setStrokeColor(col.withAlphaComponent(0.5).cgColor)
            ctx.strokePath()
        }
    }

    private func pickFeatured(_ list: [Aircraft], _ now: Date) -> Aircraft? {
        let airborne = list.filter { !$0.onGround }
        guard !airborne.isEmpty else { featuredHex = nil; return nil }
        if let e = airborne.first(where: { $0.emergency }) { featuredHex = e.hex; return e }

        let slot = Int(now.timeIntervalSince1970 / 14)
        if slot == featuredSlot, let h = featuredHex, let cur = airborne.first(where: { $0.hex == h }) { return cur }

        let ranked = airborne.sorted {
            Geo.distanceNm(settings.lat, settings.lon, $0.lat, $0.lon) < Geo.distanceNm(settings.lat, settings.lon, $1.lat, $1.lon)
        }
        let top = Array(ranked.prefix(5))
        let pick = top[slot % top.count]
        featuredSlot = slot
        featuredHex = pick.hex
        return pick
    }

    private func drawAircraft(_ ctx: CGContext, _ list: [Aircraft], _ now: Date) {
        let u = uiScale
        let t = now.timeIntervalSinceReferenceDate
        let visible = bounds.insetBy(dx: -50, dy: -50)
        let compact = list.count > 70

        for a in list {
            let pos = a.displayed(at: now)
            let pt = screenPoint(lat: pos.lat, lon: pos.lon)
            guard visible.contains(pt) else { continue }

            let col = color(for: a)
            let fade = CGFloat(min(max(now.timeIntervalSince(a.firstSeen) / 1.5, 0), 1))
            var g = 1.15 * u
            switch a.category {
            case "A5": g *= 1.25
            case "A4": g *= 1.12
            case "A1", "B1", "B4": g *= 0.85
            default: break
            }

            ctx.saveGState()
            ctx.setAlpha(fade)

            // resplandor
            ctx.setFillColor(col.withAlphaComponent(0.10).cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - 17 * g, y: pt.y - 17 * g, width: 34 * g, height: 34 * g))
            ctx.setFillColor(col.withAlphaComponent(0.16).cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - 10 * g, y: pt.y - 10 * g, width: 20 * g, height: 20 * g))

            // emergencia: anillo rojo pulsante
            if a.emergency {
                let pulse = CGFloat(0.5 + 0.5 * sin(t * 5))
                ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.4 + 0.5 * pulse).cgColor)
                ctx.setLineWidth(2 * u)
                let r = (17 + 7 * pulse) * g
                ctx.strokeEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r))
            }
            // destacado: anillo blanco
            if a.hex == featuredHex {
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
                ctx.setLineWidth(1.5 * u)
                let r = 21 * g
                ctx.strokeEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r))
            }

            // silueta
            ctx.saveGState()
            ctx.translateBy(x: pt.x, y: pt.y)
            ctx.rotate(by: CGFloat(a.track * .pi / 180))
            ctx.scaleBy(x: g, y: g)
            if a.isHelicopter {
                drawHelicopter(ctx, col, t)
            } else {
                ctx.addPath(a.isLight ? Glyphs.light : Glyphs.jet)
                ctx.setFillColor(col.cgColor)
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(1.0)
                ctx.drawPath(using: .fillStroke)
            }
            ctx.restoreGState()

            if settings.labels { drawLabel(a, at: pt, glyph: g, compact: compact, u: u) }
            ctx.restoreGState()
        }
    }

    private func drawHelicopter(_ ctx: CGContext, _ col: NSColor, _ t: Double) {
        ctx.setFillColor(col.cgColor)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1)
        ctx.addEllipse(in: CGRect(x: -3.2, y: -6, width: 6.4, height: 11))
        ctx.drawPath(using: .fillStroke)

        ctx.setStrokeColor(col.cgColor)
        ctx.setLineWidth(1.6)
        ctx.move(to: CGPoint(x: 0, y: 4))
        ctx.addLine(to: CGPoint(x: 0, y: 12))
        ctx.strokePath()

        ctx.setStrokeColor(col.withAlphaComponent(0.28).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: CGRect(x: -10, y: -10, width: 20, height: 20))

        ctx.setStrokeColor(col.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1.3)
        let ang = CGFloat(t * 9)
        for k in 0..<2 {
            let a = ang + CGFloat(k) * (.pi / 2)
            ctx.move(to: CGPoint(x: -10 * cos(a), y: -10 * sin(a)))
            ctx.addLine(to: CGPoint(x: 10 * cos(a), y: 10 * sin(a)))
        }
        ctx.strokePath()
    }

    private func drawLabel(_ a: Aircraft, at pt: CGPoint, glyph g: CGFloat, compact: Bool, u: CGFloat) {
        var parts: [String] = []
        if a.onGround {
            parts.append("GND")
        } else if let alt = a.alt {
            var s = alt >= 18000 ? "FL\(Int((alt / 100).rounded()))" : "\(Int(alt)) ft"
            if let vr = a.vRate { s += vr > 300 ? " ↑" : (vr < -300 ? " ↓" : "") }
            parts.append(s)
        }
        if a.gs > 0 { parts.append("\(Int(a.gs)) kt") }
        if !a.type.isEmpty { parts.append(a.type) }
        if a.military { parts.append("MIL") }
        if a.emergency { parts.append("EMERG \(a.squawk)") }
        let info = parts.joined(separator: " · ")

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11 * u, weight: .semibold),
            .foregroundColor: a.emergency ? NSColor.systemRed : NSColor.white,
        ]
        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10 * u, weight: .regular),
            .foregroundColor: NSColor(white: 0.8, alpha: 1),
        ]
        let name = a.callsign as NSString
        let infoNS = info as NSString
        let ns = name.size(withAttributes: nameAttrs)
        let isz = infoNS.size(withAttributes: infoAttrs)
        let boxW = max(ns.width, compact ? 0 : isz.width) + 10 * u
        let boxH = ns.height + (compact ? 0 : isz.height) + 4 * u

        var ox = pt.x + 15 * g
        if ox + boxW > bounds.maxX - 6 { ox = pt.x - 15 * g - boxW }
        let oy = pt.y - boxH / 2

        NSColor.black.withAlphaComponent(0.52).setFill()
        NSBezierPath(roundedRect: NSRect(x: ox, y: oy, width: boxW, height: boxH), xRadius: 4 * u, yRadius: 4 * u).fill()
        name.draw(at: CGPoint(x: ox + 5 * u, y: oy + 2 * u), withAttributes: nameAttrs)
        if !compact {
            infoNS.draw(at: CGPoint(x: ox + 5 * u, y: oy + 2 * u + ns.height), withAttributes: infoAttrs)
        }
    }

    private func drawHome(_ ctx: CGContext) {
        let u = uiScale
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1.5 * u)
        ctx.strokeEllipse(in: CGRect(x: c.x - 6 * u, y: c.y - 6 * u, width: 12 * u, height: 12 * u))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - 1.8 * u, y: c.y - 1.8 * u, width: 3.6 * u, height: 3.6 * u))
        if !settings.homeLabel.isEmpty {
            drawText(settings.homeLabel, x: c.x + 11 * u, y: c.y + 7 * u, size: 11 * u, weight: .semibold,
                     color: NSColor.white.withAlphaComponent(0.8), shadow: true)
        }
    }

    // MARK: HUD

    private func drawHUD(_ list: [Aircraft], _ featured: Aircraft?) {
        let u = uiScale
        // El reloj y la fecha se omiten: macOS ya presenta esa información en el salvapantallas.
        drawStats(list, u: u)
        if let f = featured { drawFeatured(f, u: u) }
        else {
            featuredPhotoRect = .zero
            featuredPhotoLink = nil
            AircraftPhotoService.shared.clearFeatured()
        }
    }

    private func drawStats(_ list: [Aircraft], u: CGFloat) {
        let w = 250 * u, h = 104 * u
        let r = CGRect(x: bounds.maxX - w - 28 * u, y: 24 * u, width: w, height: h)
        panel(r, radius: 14 * u)

        let air = list.filter { !$0.onGround }.count
        let gnd = list.count - air
        let big = drawText("\(list.count)", x: r.minX + 16 * u, y: r.minY + 8 * u, size: 36 * u, weight: .semibold, mono: true)
        drawText("aeronaves", x: r.minX + 16 * u + big.width + 8 * u, y: r.minY + 24 * u, size: 13 * u, weight: .medium,
                 color: NSColor.white.withAlphaComponent(0.7))
        drawText("\(air) en vuelo · \(gnd) en tierra", x: r.minX + 16 * u, y: r.minY + 52 * u, size: 11 * u,
                 color: NSColor.white.withAlphaComponent(0.55))

        // Leyenda de altitud
        let barX = r.minX + 16 * u, barW = r.width - 32 * u, barY = r.maxY - 30 * u, barH = 6 * u
        let segs = 48
        for i in 0..<segs {
            altColor(Double(i) / Double(segs - 1) * 40000).setFill()
            NSBezierPath(rect: CGRect(x: barX + CGFloat(i) * barW / CGFloat(segs), y: barY,
                                      width: barW / CGFloat(segs) + 0.5, height: barH)).fill()
        }
        for (frac, text) in [(0.0, "0"), (0.25, "FL100"), (0.625, "FL250"), (1.0, "FL400")] {
            let tx = barX + CGFloat(frac) * barW
            drawText(text, x: tx, y: barY + barH + 3 * u, size: 9 * u, color: NSColor.white.withAlphaComponent(0.5),
                     align: frac == 0 ? .left : (frac == 1 ? .right : .center))
        }
    }

    private func drawFeatured(_ a: Aircraft, u: CGFloat) {
        // Tarjeta más ancha y alta: la foto ocupa el lateral izquierdo y las métricas
        // quedan en una cuadrícula estable, sin invadir los bordes.
        let w = 520 * u, h = 250 * u
        let r = CGRect(x: 28 * u, y: bounds.height - h - 44 * u, width: w, height: h)
        panel(r, radius: 16 * u)

        let photoService = AircraftPhotoService.shared
        photoService.setFeatured(hex: a.hex, registration: a.reg)
        let photoRect = CGRect(x: r.minX + 16 * u, y: r.minY + 62 * u, width: 166 * u, height: 132 * u)
        featuredPhotoRect = photoRect
        featuredPhotoLink = photoService.currentInfo?.pageURL
        drawAircraftPhoto(photoService.currentImage, in: photoRect, u: u)

        let credit: String
        if let info = photoService.currentInfo {
            let providerLabel = " · Planespotters.net ↗"
            let providerWidth = (providerLabel as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 8.5 * u)]).width
            let photographerLabel = fit("© " + info.photographer,
                                         maxWidth: max(20 * u, photoRect.width - providerWidth - 5 * u),
                                         size: 8.5 * u, mono: false)
            credit = photographerLabel + providerLabel
        } else if photoService.isLookupFinishedForFeatured {
            credit = "Sin foto disponible · Planespotters"
        } else {
            credit = "Buscando foto · Planespotters.net"
        }
        let creditText = fit(credit, maxWidth: photoRect.width - 4 * u, size: 8.5 * u, mono: false)
        drawText(creditText, x: photoRect.minX + 2 * u, y: photoRect.maxY + 5 * u,
                 size: 8.5 * u, color: NSColor.white.withAlphaComponent(0.62))

        let x = r.minX + 200 * u
        let right = r.maxX - 18 * u
        let title = fit(a.callsign, maxWidth: 210 * u, size: 25 * u, mono: false)
        drawText(title, x: x, y: r.minY + 14 * u, size: 25 * u, weight: .semibold)
        if !a.type.isEmpty {
            drawText(a.type, x: right, y: r.minY + 21 * u, size: 14 * u, weight: .semibold,
                     color: color(for: a), mono: true, align: .right)
        }

        var sub: [String] = []
        if !a.reg.isEmpty { sub.append(a.reg) }
        if a.military { sub.append("MILITAR") }
        if a.emergency { sub.append("EMERGENCIA · SQK \(a.squawk)") }
        if sub.isEmpty && !a.squawk.isEmpty { sub.append("SQK \(a.squawk)") }
        let subtitle = fit(sub.joined(separator: " · "), maxWidth: right - x, size: 11 * u, mono: false)
        drawText(subtitle, x: x, y: r.minY + 45 * u, size: 11 * u, weight: .medium,
                 color: a.emergency ? NSColor.systemRed : NSColor.white.withAlphaComponent(0.62))

        let dist = Geo.distanceNm(settings.lat, settings.lon, a.lat, a.lon)
        let brg = Geo.bearing(settings.lat, settings.lon, a.lat, a.lon)
        var altText = "—"
        if a.onGround { altText = "TIERRA" }
        else if let alt = a.alt { altText = alt >= 18000 ? "FL\(Int((alt / 100).rounded()))" : "\(Int(alt)) ft" }
        var vsText = "—"
        if let vr = a.vRate { vsText = "\(vr > 0 ? "+" : "")\(Int(vr)) fpm" }

        let col2 = x + 145 * u
        let row1 = r.minY + 79 * u
        let row2 = r.minY + 132 * u
        let row3 = r.minY + 185 * u
        drawStat("ALTITUD", altText, x: x, y: row1, u: u)
        drawStat("VELOCIDAD", "\(Int(a.gs)) kt", x: col2, y: row1, u: u)
        drawStat("V/S", vsText, x: x, y: row2, u: u)
        drawStat("RUMBO", String(format: "%03d°", Int(a.track.rounded()) % 360), x: col2, y: row2, u: u)
        drawStat("DISTANCIA", String(format: "%.1f NM", dist), x: x, y: row3, u: u)
        drawStat("MARCACIÓN", String(format: "%03d°", Int(brg.rounded()) % 360), x: col2, y: row3, u: u)
    }

    private func drawAircraftPhoto(_ image: NSImage?, in rect: CGRect, u: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 9 * u, yRadius: 9 * u)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let image = image, image.size.width > 0, image.size.height > 0 {
            let targetAspect = rect.width / rect.height
            let imageAspect = image.size.width / image.size.height
            var source = CGRect(origin: .zero, size: image.size)
            if imageAspect > targetAspect {
                source.size.width = image.size.height * targetAspect
                source.origin.x = (image.size.width - source.width) / 2
            } else {
                source.size.height = image.size.width / targetAspect
                source.origin.y = (image.size.height - source.height) / 2
            }
            image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        } else {
            NSColor(calibratedWhite: 0.12, alpha: 0.95).setFill()
            path.fill()
            if let symbol = NSImage(systemSymbolName: "airplane", accessibilityDescription: "Avión") {
                symbol.draw(in: CGRect(x: rect.midX - 20 * u, y: rect.midY - 18 * u,
                                       width: 40 * u, height: 36 * u),
                            from: .zero, operation: .sourceOver, fraction: 0.62)
            }
            drawText("FOTO NO DISPONIBLE", x: rect.midX, y: rect.maxY - 22 * u,
                     size: 8.5 * u, weight: .semibold, color: NSColor.white.withAlphaComponent(0.58), align: .center)
        }
        NSGraphicsContext.restoreGraphicsState()
        path.lineWidth = 1 * u
        NSColor.white.withAlphaComponent(0.15).setStroke()
        path.stroke()
    }

    private func fit(_ value: String, maxWidth: CGFloat, size: CGFloat, mono: Bool) -> String {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                        : NSFont.systemFont(ofSize: size, weight: .regular)
        var result = value
        while !result.isEmpty && (result as NSString).size(withAttributes: [.font: font]).width > maxWidth {
            result.removeLast()
        }
        if result != value && !result.isEmpty { result.removeLast(); result += "…" }
        return result
    }

    private func drawStat(_ label: String, _ value: String, x: CGFloat, y: CGFloat, u: CGFloat) {
        drawText(label, x: x, y: y, size: 9 * u, weight: .semibold, color: NSColor.white.withAlphaComponent(0.45))
        let fitted = fit(value, maxWidth: 132 * u, size: 15.5 * u, mono: true)
        drawText(fitted, x: x, y: y + 12 * u, size: 15.5 * u, weight: .medium, mono: true)
    }

    // MARK: Avisos y pie

    private func drawBanner(_ now: Date) {
        let feed = FlightFeed.shared
        var message: String?
        var isError = false
        if feed.statusIsError {
            message = "⚠︎ " + feed.statusText
            isError = true
        } else if let ok = feed.lastOK, now.timeIntervalSince(ok) > 25 {
            message = "⚠︎ Sin actualizar desde hace \(Int(now.timeIntervalSince(ok))) s"
            isError = true
        } else if feed.lastOK == nil {
            message = "Cargando tráfico aéreo…"
        } else if feed.aircraft.isEmpty {
            message = "Sin tráfico en un radio de \(feed.radius) NM"
        }
        guard let text = message else { return }

        let u = uiScale
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13 * u, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let sz = (text as NSString).size(withAttributes: attrs)
        let r = CGRect(x: bounds.midX - sz.width / 2 - 16 * u, y: 22 * u, width: sz.width + 32 * u, height: sz.height + 14 * u)
        let p = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        (isError ? NSColor(calibratedRed: 0.75, green: 0.25, blue: 0.1, alpha: 0.9)
                 : NSColor(calibratedWhite: 0.1, alpha: 0.75)).setFill()
        p.fill()
        (text as NSString).draw(at: CGPoint(x: r.minX + 16 * u, y: r.minY + 7 * u), withAttributes: attrs)
    }

    private func drawFooter(count: Int) {
        let u = uiScale
        let feed = FlightFeed.shared
        let source = feed.providerName.isEmpty ? "adsb.fi" : feed.providerName
        let mapCredit = settings.usesCartoMap ? "© OpenStreetMap contributors © CARTO" : "© OpenStreetMap contributors · mapa oscuro gratuito"
        drawText("\(mapCredit) · Datos: \(source)",
                 x: bounds.maxX - 10 * u, y: bounds.maxY - 18 * u, size: 10 * u,
                 color: NSColor.white.withAlphaComponent(0.5), align: .right, shadow: true)

        guard settings.status, bounds.width >= 700 else { return }
        let text = "\(source) · \(count) aeronaves · radio \(feed.radius) NM"
        drawText(text, x: bounds.midX, y: bounds.maxY - 18 * u, size: 10 * u,
                 color: NSColor.white.withAlphaComponent(0.4), mono: true, align: .center, shadow: true)
    }

    // La fotografía actúa como enlace directo a su página original en Planespotters.net.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if featuredPhotoRect.contains(point), let url = featuredPhotoLink {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: Opciones

    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        let c = ConfigController()
        configController = c
        return c.window
    }
}
