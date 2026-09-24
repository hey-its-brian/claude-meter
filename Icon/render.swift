// Renders the ClaudeMeter app icon with plain Core Graphics paths (no fonts or SF Symbols).
// Usage: swift render.swift <out.png>                 (1024px preview)
//        swift render.swift --appiconset <dir>        (all macOS sizes plus Contents.json)
import AppKit

let S: CGFloat = 1024
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let bgTop = hex(0x2E2824), bgBottom = hex(0x171412)
let track = hex(0x3D3530), cream = hex(0xF4EDE4)
let peach = hex(0xF0B48F), clay = hex(0xD97757), ember = hex(0xB8482A)

// macOS icon grid: 824pt body centered on a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

// Gauge geometry: a 270 degree arc opening at the bottom.
let center = CGPoint(x: 512, y: 488)
let arcRadius: CGFloat = 268
let arcWidth: CGFloat = 74
let startAngle: CGFloat = 225, sweep: CGFloat = 270
let usage: CGFloat = 0.64   // how full the gauge reads
let pace: CGFloat = 0.42    // the "time elapsed" tick, matching the widget bars

func angle(at fraction: CGFloat) -> CGFloat { startAngle - sweep * fraction }
func point(_ deg: CGFloat, _ r: CGFloat) -> CGPoint {
    let rad = deg * .pi / 180
    return CGPoint(x: center.x + cos(rad) * r, y: center.y + sin(rad) * r)
}
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}

func arc(from: CGFloat, to: CGFloat, color: NSColor, width: CGFloat = arcWidth, cap: NSBezierPath.LineCapStyle = .round) {
    let p = NSBezierPath()
    p.appendArc(withCenter: center, radius: arcRadius, startAngle: angle(at: from), endAngle: angle(at: to), clockwise: true)
    p.lineWidth = width
    p.lineCapStyle = cap
    color.setStroke()
    p.stroke()
}

func draw() {
    // Squircle body with a soft drop shadow.
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: bgTop, ending: bgBottom)!.draw(in: body, angle: -90)
    // Warm glow behind the gauge.
    NSGradient(colors: [clay.withAlphaComponent(0.22), clay.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: 430, options: [])

    // Track, then the filled portion as short segments so the color ramps peach -> clay -> ember.
    arc(from: 0, to: 1, color: track)
    let steps = 90
    for i in 0..<steps {
        let a = usage * CGFloat(i) / CGFloat(steps), b = usage * CGFloat(i + 1) / CGFloat(steps)
        let t = CGFloat(i) / CGFloat(steps - 1)
        let color = t < 0.5 ? mix(peach, clay, t * 2) : mix(clay, ember, (t - 0.5) * 2)
        arc(from: a, to: min(b + 0.004, usage), color: color, cap: i == 0 ? .round : .butt)
    }
    // Rounded end cap on the fill.
    ember.setFill()
    let end = point(angle(at: usage), arcRadius)
    NSBezierPath(ovalIn: CGRect(x: end.x - arcWidth / 2, y: end.y - arcWidth / 2, width: arcWidth, height: arcWidth)).fill()

    // Minor ticks inside the arc.
    for i in 0...10 {
        let deg = angle(at: CGFloat(i) / 10)
        let major = i % 5 == 0
        let p = NSBezierPath()
        p.move(to: point(deg, arcRadius - arcWidth / 2 - 26))
        p.line(to: point(deg, arcRadius - arcWidth / 2 - (major ? 70 : 50)))
        p.lineWidth = major ? 12 : 8
        p.lineCapStyle = .round
        cream.withAlphaComponent(major ? 0.55 : 0.3).setStroke()
        p.stroke()
    }

    // Pace tick crossing the arc.
    let paceDeg = angle(at: pace)
    let tick = NSBezierPath()
    tick.move(to: point(paceDeg, arcRadius - arcWidth / 2 - 8))
    tick.line(to: point(paceDeg, arcRadius + arcWidth / 2 + 8))
    tick.lineWidth = 14
    tick.lineCapStyle = .round
    cream.setStroke()
    tick.stroke()

    // Needle: tapered wedge from the hub toward the usage level.
    let needleDeg = angle(at: usage)
    let rad = needleDeg * .pi / 180
    let perp = CGPoint(x: -sin(rad), y: cos(rad))
    let tip = point(needleDeg, 196)
    let tail = point(needleDeg + 180, 40)
    let needle = NSBezierPath()
    needle.move(to: tip)
    needle.line(to: CGPoint(x: center.x + perp.x * 22, y: center.y + perp.y * 22))
    needle.line(to: CGPoint(x: tail.x + perp.x * 12, y: tail.y + perp.y * 12))
    needle.line(to: CGPoint(x: tail.x - perp.x * 12, y: tail.y - perp.y * 12))
    needle.line(to: CGPoint(x: center.x - perp.x * 22, y: center.y - perp.y * 22))
    needle.close()
    NSGraphicsContext.saveGraphicsState()
    let needleShadow = NSShadow()
    needleShadow.shadowColor = .black.withAlphaComponent(0.4)
    needleShadow.shadowBlurRadius = 14
    needleShadow.shadowOffset = NSSize(width: 0, height: -6)
    needleShadow.set()
    cream.setFill(); needle.fill()
    NSBezierPath(ovalIn: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88)).fill()
    NSGraphicsContext.restoreGraphicsState()
    clay.setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)).fill()

    // Two small usage bars in the gauge's opening, echoing the widget.
    func bar(_ y: CGFloat, _ fill: CGFloat, _ color: NSColor) {
        let x: CGFloat = 392, w: CGFloat = 240, h: CGFloat = 22
        track.setFill()
        NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
        color.setFill()
        NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w * fill, height: h), xRadius: h / 2, yRadius: h / 2).fill()
    }
    bar(236, 0.64, clay)
    bar(194, 0.3, peach)

    // Subtle top highlight.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
if args.count == 3, args[1] == "--appiconset" {
    let dir = URL(fileURLWithPath: args[2])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var images: [String] = []
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
            try render(size: pt * scale).write(to: dir.appendingPathComponent(name))
            images.append(#"    { "idiom" : "mac", "size" : "\#(pt)x\#(pt)", "scale" : "\#(scale)x", "filename" : "\#(name)" }"#)
        }
    }
    let contents = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    try contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
} else if args.count == 2 {
    try render(size: 1024).write(to: URL(fileURLWithPath: args[1]))
} else {
    print("usage: swift render.swift <out.png> | --appiconset <dir>")
}
