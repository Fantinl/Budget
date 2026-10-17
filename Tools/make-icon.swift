#!/usr/bin/env swift
// Génère l'icône de l'app : Support/AppIcon.icns (+ Support/AppIcon-1024.png).
// Usage, depuis la racine du projet :
//     swift Tools/make-icon.swift
// (avec Xcode : DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift Tools/make-icon.swift)
// Variable optionnelle ICONSET_DIR : dossier de travail du .iconset (défaut : dossier temporaire système).
import AppKit

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
            blue: CGFloat(v & 255) / 255, alpha: 1)
}

// Parts : (fraction, couleur) — palette de l'app. La 2e part est « explosée ».
let slices: [(Double, NSColor)] = [
    (0.34, hex(0x5FB58A)), (0.24, hex(0x5B8DEF)), (0.18, hex(0xF0A04B)),
    (0.14, hex(0x9B7FE6)), (0.10, hex(0xE58BB8)),
]
let explodedIndex = 1

/// Squircle (superellipse) centré dans le rect.
func squircle(_ r: NSRect, n: Double = 5) -> NSBezierPath {
    let p = NSBezierPath()
    let a = r.width / 2, cx = r.midX, cy = r.midY
    let steps = 360
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * CGFloat(copysign(pow(abs(c), 2 / n), c))
        let y = cy + a * CGFloat(copysign(pow(abs(s), 2 / n), s))
        i == 0 ? p.move(to: NSPoint(x: x, y: y)) : p.line(to: NSPoint(x: x, y: y))
    }
    p.close()
    return p
}

func draw(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let k = CGFloat(px) / 1024
    let xf = NSAffineTransform(); xf.scaleX(by: k, yBy: k); xf.concat()
    let small = px <= 32
    let tiny = px <= 16

    // Forme de base
    let base = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(base)
    if !small {
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.4)
        sh.shadowBlurRadius = 24; sh.shadowOffset = NSSize(width: 0, height: -12)
        sh.set()
        hex(0x16213E).setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: hex(0x2A3A6B), ending: hex(0x0E1530))!.draw(in: base, angle: -90)
    if !small { // léger reflet en haut
        NSGradient(starting: NSColor.white.withAlphaComponent(0.10), ending: .clear)!
            .draw(in: NSRect(x: 100, y: 520, width: 824, height: 404), angle: -90)
    }
    NSGraphicsContext.restoreGraphicsState()

    // Camembert
    let center = NSPoint(x: 512 - 14, y: 512 + 10)
    let radius: CGFloat = 290
    let gap: CGFloat = small ? 0 : 14
    let explode: CGFloat = tiny ? 20 : 34
    var start = 90.0 // en degrés, sens horaire depuis le haut
    for (i, s) in slices.enumerated() {
        let sweep = s.0 * 360
        let mid = start - sweep / 2
        let half = sweep / 2 * .pi / 180
        var d: CGFloat = gap > 0 ? gap / (2 * CGFloat(sin(half))) : 0
        if i == explodedIndex { d += explode }
        let mr = mid * .pi / 180
        let c = NSPoint(x: center.x + d * CGFloat(cos(mr)), y: center.y + d * CGFloat(sin(mr)))
        let p = NSBezierPath()
        p.move(to: c)
        p.appendArc(withCenter: c, radius: radius, startAngle: CGFloat(start),
                    endAngle: CGFloat(start - sweep), clockwise: true)
        p.close()
        p.lineJoinStyle = .round
        NSGraphicsContext.saveGraphicsState()
        if !small {
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
            sh.shadowBlurRadius = 18; sh.shadowOffset = NSSize(width: 0, height: -8)
            sh.set()
        }
        s.1.setFill(); p.fill()
        NSGraphicsContext.restoreGraphicsState()
        if !small {
            NSGraphicsContext.saveGraphicsState()
            p.addClip()
            let light = s.1.blended(withFraction: 0.28, of: .white)!
            let dark = s.1.blended(withFraction: 0.18, of: .black)!
            NSGradient(starting: light, ending: dark)!.draw(in: p.bounds, angle: -60)
            NSGraphicsContext.restoreGraphicsState()
        }
        start -= sweep
    }
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = fm.currentDirectoryPath
let work = ProcessInfo.processInfo.environment["ICONSET_DIR"]
    ?? NSTemporaryDirectory() + "budget-icon"
let iconset = work + "/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try draw(px: base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try draw(px: base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
try draw(px: 1024).write(to: URL(fileURLWithPath: "\(root)/Support/AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "\(root)/Support/AppIcon.icns"]
try task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "OK : Support/AppIcon.icns" : "iconutil a échoué")
exit(task.terminationStatus)
