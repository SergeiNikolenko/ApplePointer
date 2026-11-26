import AppKit
import CoreGraphics
import Foundation

func makeContinuousRoundedRectPath(in rect: CGRect, cornerRadius r: CGFloat) -> CGPath {
    // Smooth macOS-style continuous squircle approximation via BezierPath
    let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    let cgPath = CGMutablePath()
    var pts = [NSPoint](repeating: .zero, count: 3)
    for i in 0..<path.elementCount {
        let type = path.element(at: i, associatedPoints: &pts)
        switch type {
        case .moveTo: cgPath.move(to: pts[0])
        case .lineTo: cgPath.addLine(to: pts[0])
        case .curveTo: cgPath.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
        case .cubicCurveTo: cgPath.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
        case .quadraticCurveTo: cgPath.addQuadCurve(to: pts[1], control: pts[0])
        case .closePath: cgPath.closeSubpath()
        @unknown default: break
        }
    }
    return cgPath
}

func makeArrowPath(origin: CGPoint, scale s: CGFloat) -> CGPath {
    // Sleek iPadOS 26 / macOS pointer arrow with subtly softened corners (in AppKit Y-up coords, tip at top-left)
    let p = CGMutablePath()
    // Tip at (0, 0), pointing up-left in Y-up coordinate space:
    // Tip is at (origin.x, origin.y), body extends +x and -y.
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * s, y: origin.y - y * s)
    }

    // Sleek iPadOS 26 / macOS pointer vertices (in 0..100 normalized Y-down space)
    let tip = pt(0, 0)
    let leftBottom = pt(0, 78)
    let innerLeft = pt(19.5, 60.5)
    let tailLeft = pt(31.5, 89.5)
    let tailRight = pt(43.5, 84.0)
    let innerRight = pt(31.5, 55.5)
    let rightWing = pt(56.5, 55.5)

    // Use crisp Apple-proportioned rounded corners
    let vertices = [tip, leftBottom, innerLeft, tailLeft, tailRight, innerRight, rightWing]
    let radii: [CGFloat] = [1.8 * s, 2.8 * s, 2.0 * s, 3.0 * s, 3.0 * s, 2.0 * s, 2.8 * s]

    let count = vertices.count
    let midStart = CGPoint(
        x: (vertices[count - 1].x + vertices[0].x) * 0.5,
        y: (vertices[count - 1].y + vertices[0].y) * 0.5
    )
    p.move(to: midStart)
    for i in 0..<count {
        let curr = vertices[i]
        let next = vertices[(i + 1) % count]
        p.addArc(tangent1End: curr, tangent2End: next, radius: radii[i])
    }
    p.closeSubpath()
    return p
}

func renderIcon(size: Int, outputPath: String) {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CGContext")
    }

    let fSize = CGFloat(size)
    let s = fSize / 1024.0

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS HIG icon canvas: 824x824 centered squircle inside 1024x1024
    let iconRect = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = makeContinuousRoundedRectPath(in: iconRect, cornerRadius: 186 * s)

    // 1. Subtle ambient icon shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18 * s), blur: 36 * s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clip to squircle and draw rich Tahoe-style obsidian-indigo glass background
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let bgColors = [
        CGColor(red: 0.15, green: 0.19, blue: 0.34, alpha: 1.0), // Top luminous indigo-slate
        CGColor(red: 0.09, green: 0.11, blue: 0.20, alpha: 1.0), // Mid deep slate
        CGColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1.0)  // Bottom rich obsidian
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: 512 * s, y: 924 * s),
        end: CGPoint(x: 512 * s, y: 100 * s),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Ambient blue-cyan magnetic glow behind the center pill
    let glowColors = [
        CGColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 0.42),
        CGColor(red: 0.42, green: 0.46, blue: 1.0, alpha: 0.16),
        CGColor(red: 0.20, green: 0.35, blue: 0.90, alpha: 0.0)
    ] as CFArray
    let glowGrad = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0.0, 0.45, 1.0])!
    ctx.drawRadialGradient(
        glowGrad,
        startCenter: CGPoint(x: 485 * s, y: 565 * s),
        startRadius: 0,
        endCenter: CGPoint(x: 485 * s, y: 565 * s),
        endRadius: 360 * s,
        options: []
    )

    // Subtle secondary warm-violet glass sheen bottom-right
    let sheenColors = [
        CGColor(red: 0.56, green: 0.44, blue: 1.0, alpha: 0.20),
        CGColor(red: 0.56, green: 0.44, blue: 1.0, alpha: 0.0)
    ] as CFArray
    let sheenGrad = CGGradient(colorsSpace: cs, colors: sheenColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        sheenGrad,
        startCenter: CGPoint(x: 740 * s, y: 260 * s),
        startRadius: 0,
        endCenter: CGPoint(x: 740 * s, y: 260 * s),
        endRadius: 320 * s,
        options: []
    )

    // 3. Magnetic frosted-glass button pill (symbolizing iPadOS adaptive snapping)
    let pillRect = CGRect(x: 222 * s, y: 468 * s, width: 410 * s, height: 214 * s)
    let pillPath = makeContinuousRoundedRectPath(in: pillRect, cornerRadius: 56 * s)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 32 * s, color: CGColor(red: 0.02, green: 0.04, blue: 0.12, alpha: 0.55))
    ctx.addPath(pillPath)
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.10))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.clip()
    let pillColors = [
        CGColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.28),
        CGColor(red: 0.65, green: 0.78, blue: 1.0, alpha: 0.14),
        CGColor(red: 0.80, green: 0.88, blue: 1.0, alpha: 0.08)
    ] as CFArray
    let pillGrad = CGGradient(colorsSpace: cs, colors: pillColors, locations: [0.0, 0.5, 1.0])!
    ctx.drawLinearGradient(
        pillGrad,
        start: CGPoint(x: pillRect.minX, y: pillRect.maxY),
        end: CGPoint(x: pillRect.maxX, y: pillRect.minY),
        options: []
    )

    // Specular radial highlight inside the frosted button pill where arrow hovers
    let specColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.34),
        CGColor(red: 0.75, green: 0.88, blue: 1.0, alpha: 0.10),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    let specGrad = CGGradient(colorsSpace: cs, colors: specColors, locations: [0.0, 0.45, 1.0])!
    ctx.drawRadialGradient(
        specGrad,
        startCenter: CGPoint(x: 470 * s, y: 565 * s),
        startRadius: 0,
        endCenter: CGPoint(x: 470 * s, y: 565 * s),
        endRadius: 210 * s,
        options: []
    )
    ctx.restoreGState()

    // Crisp Liquid Glass rim on pill
    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.setStrokeColor(CGColor(red: 0.88, green: 0.94, blue: 1.0, alpha: 0.48))
    ctx.setLineWidth(4.5 * s)
    ctx.strokePath()
    ctx.restoreGState()

    // Subtle minimalist UI indicator inside left of pill (a tiny rounded dot + bar like a UI control)
    ctx.saveGState()
    let miniDot = CGRect(x: 274 * s, y: 552 * s, width: 46 * s, height: 46 * s)
    ctx.setFillColor(CGColor(red: 0.50, green: 0.78, blue: 1.0, alpha: 0.72))
    ctx.fillEllipse(in: miniDot)
    let miniBar = CGRect(x: 342 * s, y: 565 * s, width: 118 * s, height: 20 * s)
    ctx.addPath(makeContinuousRoundedRectPath(in: miniBar, cornerRadius: 10 * s))
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.32))
    ctx.fillPath()
    ctx.restoreGState()

    // 4. Sculptural iPadOS 26 Adaptive Pointer Arrow overlapping the pill
    let arrowPath = makeArrowPath(origin: CGPoint(x: 472 * s, y: 608 * s), scale: 4.35 * s)

    // Deep elevation shadow beneath arrow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 8 * s, height: -22 * s), blur: 36 * s, color: CGColor(red: 0.0, green: 0.02, blue: 0.08, alpha: 0.65))
    ctx.addPath(arrowPath)
    ctx.setFillColor(CGColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Pearl-white glass gradient fill on arrow
    ctx.saveGState()
    ctx.addPath(arrowPath)
    ctx.clip()
    let arrowColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        CGColor(red: 0.90, green: 0.94, blue: 0.99, alpha: 1.0),
        CGColor(red: 0.78, green: 0.85, blue: 0.96, alpha: 1.0)
    ] as CFArray
    let arrowGrad = CGGradient(colorsSpace: cs, colors: arrowColors, locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(
        arrowGrad,
        start: CGPoint(x: 454 * s, y: 618 * s),
        end: CGPoint(x: 690 * s, y: 200 * s),
        options: []
    )
    ctx.restoreGState()

    // Subtle crisp bevel stroke around arrow
    ctx.saveGState()
    ctx.addPath(arrowPath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
    ctx.setLineWidth(5.0 * s)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Outer glass inner-rim bezel of the app squircle
    ctx.saveGState()
    let innerBezel = makeContinuousRoundedRectPath(in: iconRect.insetBy(dx: 3 * s, dy: 3 * s), cornerRadius: 183 * s)
    ctx.addPath(innerBezel)
    ctx.setStrokeColor(CGColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.26))
    ctx.setLineWidth(5.5 * s)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState() // End squircle clip

    guard let image = ctx.makeImage() else {
        fatalError("Failed to create CGImage")
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG")
    }
    try! png.write(to: URL(fileURLWithPath: outputPath))
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: generate-icon.swift <out_iconset_dir>\n", stderr)
    exit(1)
}
let outDir = args[1]
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    renderIcon(size: px, outputPath: "\(outDir)/\(name)")
}
print("Generated iconset in \(outDir)")
