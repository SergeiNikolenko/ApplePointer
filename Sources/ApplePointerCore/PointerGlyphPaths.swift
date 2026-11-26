import CoreGraphics
import Foundation

/// Shared iPadOS / Liquid Glass translucent vector glyph geometry for resize cursors,
/// screenshot reticles, macOS special cursors, creative tool cursors, and slider/stepper accessories.
/// All paths use even-odd fill rules so interior cutouts (+, -, ?, /, camera lens) stay crisp.
public enum IPadResizePaths {
    public static let canvasSize = CGSize(width: 44.0, height: 44.0)

    public static func makeCenteredPath(kind: ResizeCursorKind) -> CGPath {
        let raw: CGPath
        switch kind {
        case .none:
            return CGPath(rect: .zero, transform: nil)
        case .splitHorizontal:
            raw = makeSplitPath(vertical: false)
        case .splitVertical:
            raw = makeSplitPath(vertical: true)
        case .horizontal:
            raw = makeDotAccessoryPath(angle: 0)
        case .vertical:
            raw = makeDotAccessoryPath(angle: .pi * 0.5)
        case .diagonalNWSE:
            raw = makeDotAccessoryPath(angle: -.pi * 0.25)
        case .diagonalNESW:
            raw = makeDotAccessoryPath(angle: .pi * 0.25)
        case .cornerNW:
            raw = makeCurvedCornerResizePath(angle: .pi * 0.75)
        case .cornerNE:
            raw = makeCurvedCornerResizePath(angle: .pi * 0.25)
        case .cornerSW:
            raw = makeCurvedCornerResizePath(angle: -.pi * 0.75)
        case .cornerSE:
            raw = makeCurvedCornerResizePath(angle: -.pi * 0.25)
        case .left:
            raw = makeSingleEdgePath(angle: .pi)
        case .right:
            raw = makeSingleEdgePath(angle: 0)
        case .up:
            raw = makeSingleEdgePath(angle: .pi * 0.5)
        case .down:
            raw = makeSingleEdgePath(angle: -.pi * 0.5)
        }
        var shift = CGAffineTransform(translationX: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
        return raw.copy(using: &shift) ?? raw
    }

    private static func makeSplitPath(vertical: Bool) -> CGPath {
        let combined = CGMutablePath()
        let pill = CGPath(
            roundedRect: CGRect(x: -1.7, y: -10.0, width: 3.4, height: 20.0),
            cornerWidth: 1.7,
            cornerHeight: 1.7,
            transform: nil
        )
        combined.addPath(pill)
        combined.addPath(makeAccessoryTriangle(tipX: -12.2, baseX: -6.2, halfHeight: 4.3))
        combined.addPath(makeAccessoryTriangle(tipX: 12.2, baseX: 6.2, halfHeight: 4.3))
        if vertical {
            var rot = CGAffineTransform(rotationAngle: .pi * 0.5)
            return combined.copy(using: &rot) ?? combined
        }
        return combined
    }

    private static func makeDotAccessoryPath(angle: CGFloat) -> CGPath {
        let combined = CGMutablePath()
        let dotR: CGFloat = 3.7
        combined.addEllipse(in: CGRect(x: -dotR, y: -dotR, width: dotR * 2.0, height: dotR * 2.0))
        combined.addPath(makeAccessoryTriangle(tipX: -12.6, baseX: -6.5, halfHeight: 4.3))
        combined.addPath(makeAccessoryTriangle(tipX: 12.6, baseX: 6.5, halfHeight: 4.3))
        if abs(angle) < 1e-4 {
            return combined
        }
        var rot = CGAffineTransform(rotationAngle: angle)
        return combined.copy(using: &rot) ?? combined
    }

    /// Curved window-corner resize glyph matching SpringBoard fancyResizePointerShapeHoveringOverEdge:cornerRadii:
    private static func makeCurvedCornerResizePath(angle: CGFloat) -> CGPath {
        let combined = CGMutablePath()
        let arcStroke = CGMutablePath()
        let radius: CGFloat = 11.5
        let halfSweep: CGFloat = 0.54
        arcStroke.addArc(
            center: CGPoint(x: -radius * 0.96, y: 0),
            radius: radius,
            startAngle: -halfSweep,
            endAngle: halfSweep,
            clockwise: false
        )
        let strokedArc = arcStroke.copy(
            strokingWithWidth: 3.2,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 2.0
        )
        combined.addPath(strokedArc)
        combined.addPath(makeAccessoryTriangle(tipX: -12.8, baseX: -6.6, halfHeight: 4.2))
        combined.addPath(makeAccessoryTriangle(tipX: 13.2, baseX: 7.0, halfHeight: 4.2))
        var rot = CGAffineTransform(rotationAngle: angle)
        return combined.copy(using: &rot) ?? combined
    }

    private static func makeSingleEdgePath(angle: CGFloat) -> CGPath {
        let combined = CGMutablePath()
        let pill = CGPath(
            roundedRect: CGRect(x: -5.4, y: -8.5, width: 3.4, height: 17.0),
            cornerWidth: 1.7,
            cornerHeight: 1.7,
            transform: nil
        )
        combined.addPath(pill)
        combined.addPath(makeAccessoryTriangle(tipX: 8.8, baseX: 2.3, halfHeight: 4.4))
        if abs(angle) < 1e-4 {
            return combined
        }
        var rot = CGAffineTransform(rotationAngle: angle)
        return combined.copy(using: &rot) ?? combined
    }

    public static func makeAccessoryTriangle(tipX: CGFloat, baseX: CGFloat, halfHeight: CGFloat) -> CGPath {
        let vertices = [
            CGPoint(x: tipX, y: 0.0),
            CGPoint(x: baseX, y: halfHeight),
            CGPoint(x: baseX, y: -halfHeight)
        ]
        return roundedPolygonPath(vertices: vertices, radii: [1.0, 0.9, 0.9])
    }

    public static func roundedPolygonPath(vertices: [CGPoint], radii: [CGFloat]) -> CGPath {
        let p = CGMutablePath()
        let count = vertices.count
        guard count >= 3 else { return p }
        let start = CGPoint(
            x: (vertices[count - 1].x + vertices[0].x) * 0.5,
            y: (vertices[count - 1].y + vertices[0].y) * 0.5
        )
        p.move(to: start)
        for i in 0..<count {
            let curr = vertices[i]
            let next = vertices[(i + 1) % count]
            let r = i < radii.count ? radii[i] : 0.8
            p.addArc(tangent1End: curr, tangent2End: next, radius: r)
        }
        p.closeSubpath()
        return p
    }

    public static func makeCrosshairPath() -> CGPath {
        let combined = CGMutablePath()
        let armLength: CGFloat = 8.5
        let armThickness: CGFloat = 2.6
        let halfThick = armThickness * 0.5
        let gap: CGFloat = 3.6
        let radius: CGFloat = halfThick

        let arms: [CGRect] = [
            CGRect(x: -gap - armLength, y: -halfThick, width: armLength, height: armThickness),
            CGRect(x: gap, y: -halfThick, width: armLength, height: armThickness),
            CGRect(x: -halfThick, y: -gap - armLength, width: armThickness, height: armLength),
            CGRect(x: -halfThick, y: gap, width: armThickness, height: armLength)
        ]
        for arm in arms {
            combined.addPath(CGPath(roundedRect: arm, cornerWidth: radius, cornerHeight: radius, transform: nil))
        }
        let dotR: CGFloat = 1.4
        combined.addEllipse(in: CGRect(x: -dotR, y: -dotR, width: dotR * 2.0, height: dotR * 2.0))

        var shift = CGAffineTransform(translationX: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
        return combined.copy(using: &shift) ?? combined
    }
}

/// Unified iPadOS / Liquid Glass translucent vector glyphs for macOS special cursors and
/// creative tool cursors (all rendered on a 44x44 canvas with even-odd cutouts & matching rim).
public enum IPadSpecialCursorPaths {
    public static let canvasSize = CGSize(width: 44.0, height: 44.0)

    /// Cutout badges use even-odd fill; solid multi-part silhouettes use non-zero winding
    /// so overlapping organic parts (fingers, clouds, pipette collar, ring+slash) fuse cleanly.
    public static func usesEvenOddFill(for kind: SpecialCursorKind) -> Bool {
        switch kind {
        case .dragCopy, .dragLink, .contextualMenu, .help, .screenshotWindow:
            return true
        default:
            return false
        }
    }

    public static func anchorPoint(for kind: SpecialCursorKind) -> CGPoint {
        switch kind {
        case .eyedropper:
            return CGPoint(x: 0.25, y: 0.25)
        default:
            return CGPoint(x: 0.5, y: 0.5)
        }
    }

    public static func makePath(kind: SpecialCursorKind) -> CGPath {
        let raw: CGPath
        switch kind {
        case .none:
            return CGPath(rect: .zero, transform: nil)
        case .openHand:
            raw = makeOpenHandPath()
        case .closedHand:
            raw = makeClosedHandPath()
        case .dragCopy:
            raw = makeBadgeWithPlusPath()
        case .dragLink:
            raw = makeBadgeWithAliasArrowPath()
        case .operationNotAllowed:
            raw = makeNotAllowedPath()
        case .contextualMenu:
            raw = makeContextualMenuPath()
        case .disappearingItem:
            raw = makeDisappearingPoofPath()
        case .zoomIn:
            raw = makeZoomPath(isZoomIn: true)
        case .zoomOut:
            raw = makeZoomPath(isZoomIn: false)
        case .move:
            raw = makeFourWayMovePath()
        case .cell:
            raw = makeCellPlusPath()
        case .help:
            raw = makeHelpPath()
        case .screenshotWindow:
            raw = makeCameraWindowPath()
        case .eyedropper:
            raw = makeEyedropperPath()
        }
        var shift = CGAffineTransform(translationX: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
        return raw.copy(using: &shift) ?? raw
    }

    private static func makeOpenHandPath() -> CGPath {
        let p = CGMutablePath()
        p.addPath(CGPath(roundedRect: CGRect(x: -7.6, y: -9.5, width: 15.2, height: 11.4), cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
        let fingers: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
            (-7.3, -1.0, 3.1, 10.2),
            (-3.4, -0.5, 3.1, 12.2),
            (0.5, -0.5, 3.1, 11.6),
            (4.4, -1.6, 3.0, 9.4)
        ]
        for f in fingers {
            p.addPath(CGPath(roundedRect: CGRect(x: f.x, y: f.y, width: f.w, height: f.h), cornerWidth: f.w * 0.5, cornerHeight: f.w * 0.5, transform: nil))
        }
        let thumb = CGPath(roundedRect: CGRect(x: -1.6, y: -1.0, width: 3.3, height: 8.6), cornerWidth: 1.65, cornerHeight: 1.65, transform: nil)
        var t = CGAffineTransform(translationX: -8.0, y: -5.2).rotated(by: 0.62)
        if let moved = thumb.copy(using: &t) {
            p.addPath(moved)
        }
        return p
    }

    private static func makeClosedHandPath() -> CGPath {
        let p = CGMutablePath()
        p.addPath(CGPath(roundedRect: CGRect(x: -8.2, y: -8.4, width: 16.4, height: 12.6), cornerWidth: 5.8, cornerHeight: 5.8, transform: nil))
        let knuckles: [CGFloat] = [-6.2, -2.1, 2.0, 5.8]
        for kx in knuckles {
            p.addPath(CGPath(roundedRect: CGRect(x: kx - 1.85, y: 1.0, width: 3.7, height: 5.6), cornerWidth: 1.85, cornerHeight: 1.85, transform: nil))
        }
        let thumb = CGPath(roundedRect: CGRect(x: -1.7, y: -1.0, width: 3.4, height: 7.4), cornerWidth: 1.7, cornerHeight: 1.7, transform: nil)
        var t = CGAffineTransform(translationX: -8.2, y: -3.2).rotated(by: 0.48)
        if let moved = thumb.copy(using: &t) {
            p.addPath(moved)
        }
        return p
    }

    /// Clean single-contour rounded plus polygon (zero self-overlap under even-odd or winding fill).
    private static func makeUnifiedPlusPath(center: CGPoint = .zero, armHalfLength a: CGFloat, barHalfWidth b: CGFloat, cornerRadius r: CGFloat) -> CGPath {
        let pts: [CGPoint] = [
            CGPoint(x: center.x - b, y: center.y + a),
            CGPoint(x: center.x + b, y: center.y + a),
            CGPoint(x: center.x + b, y: center.y + b),
            CGPoint(x: center.x + a, y: center.y + b),
            CGPoint(x: center.x + a, y: center.y - b),
            CGPoint(x: center.x + b, y: center.y - b),
            CGPoint(x: center.x + b, y: center.y - a),
            CGPoint(x: center.x - b, y: center.y - a),
            CGPoint(x: center.x - b, y: center.y - b),
            CGPoint(x: center.x - a, y: center.y - b),
            CGPoint(x: center.x - a, y: center.y + b),
            CGPoint(x: center.x - b, y: center.y + b)
        ]
        let radii: [CGFloat] = [r, r, r * 0.55, r, r, r * 0.55, r, r, r * 0.55, r, r, r * 0.55]
        return IPadResizePaths.roundedPolygonPath(vertices: pts, radii: radii)
    }

    private static func makeBadgeWithPlusPath() -> CGPath {
        let p = CGMutablePath()
        let r: CGFloat = 10.5
        p.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        p.addPath(makeUnifiedPlusPath(armHalfLength: 5.5, barHalfWidth: 1.4, cornerRadius: 1.1))
        return p
    }

    private static func makeBadgeWithAliasArrowPath() -> CGPath {
        let p = CGMutablePath()
        let r: CGFloat = 10.5
        p.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        // Single continuous non-overlapping curved alias arrow cutout
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: -4.8, y: -4.2))
        arrow.addQuadCurve(to: CGPoint(x: 1.2, y: 2.2), control: CGPoint(x: -4.2, y: 2.2))
        arrow.addLine(to: CGPoint(x: 1.2, y: 4.6))
        arrow.addLine(to: CGPoint(x: 5.8, y: 1.0))
        arrow.addLine(to: CGPoint(x: 1.2, y: -2.6))
        arrow.addLine(to: CGPoint(x: 1.2, y: -0.2))
        arrow.addQuadCurve(to: CGPoint(x: -2.7, y: -4.2), control: CGPoint(x: -2.0, y: -0.2))
        arrow.closeSubpath()
        p.addPath(arrow)
        return p
    }

    private static func makeNotAllowedPath() -> CGPath {
        let p = CGMutablePath()
        // Stroked ring + diagonal bar fuse cleanly under non-zero winding with zero overlap holes
        let ringCenterline = CGPath(ellipseIn: CGRect(x: -9.1, y: -9.1, width: 18.2, height: 18.2), transform: nil)
        p.addPath(ringCenterline.copy(strokingWithWidth: 3.3, lineCap: .round, lineJoin: .round, miterLimit: 2.0))
        let slash = CGPath(roundedRect: CGRect(x: -8.8, y: -1.6, width: 17.6, height: 3.2), cornerWidth: 1.6, cornerHeight: 1.6, transform: nil)
        var rot = CGAffineTransform(rotationAngle: -.pi * 0.25)
        if let rotated = slash.copy(using: &rot) {
            p.addPath(rotated)
        }
        return p
    }

    private static func makeContextualMenuPath() -> CGPath {
        let p = CGMutablePath()
        p.addPath(CGPath(roundedRect: CGRect(x: -9.5, y: -10.5, width: 19.0, height: 21.0), cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
        for y in [-4.8, 0.0, 4.8] as [CGFloat] {
            p.addPath(CGPath(roundedRect: CGRect(x: -5.4, y: y - 1.05, width: 10.8, height: 2.1), cornerWidth: 1.05, cornerHeight: 1.05, transform: nil))
        }
        return p
    }

    private static func makeDisappearingPoofPath() -> CGPath {
        let p = CGMutablePath()
        // Clean 5-lobe cloud silhouette + subtle orbiting puff dots (non-zero winding)
        let puffs: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
            (0.0, 4.6, 5.2),
            (-5.4, 1.0, 4.8),
            (5.4, 1.0, 4.8),
            (-3.4, -4.2, 4.7),
            (3.4, -4.2, 4.7),
            (0.0, 0.0, 5.6)
        ]
        for puff in puffs {
            p.addEllipse(in: CGRect(x: puff.x - puff.r, y: puff.y - puff.r, width: puff.r * 2, height: puff.r * 2))
        }
        return p
    }

    private static func makeZoomPath(isZoomIn: Bool) -> CGPath {
        let p = CGMutablePath()
        let lensCenter = CGPoint(x: -2.0, y: 2.0)
        let ringCenterline = CGPath(ellipseIn: CGRect(x: lensCenter.x - 7.5, y: lensCenter.y - 7.5, width: 15.0, height: 15.0), transform: nil)
        p.addPath(ringCenterline.copy(strokingWithWidth: 3.0, lineCap: .round, lineJoin: .round, miterLimit: 2.0))

        let handle = CGMutablePath()
        handle.move(to: CGPoint(x: 3.9, y: -3.9))
        handle.addLine(to: CGPoint(x: 10.4, y: -10.4))
        p.addPath(handle.copy(strokingWithWidth: 3.3, lineCap: .round, lineJoin: .round, miterLimit: 2.0))

        if isZoomIn {
            p.addPath(makeUnifiedPlusPath(center: lensCenter, armHalfLength: 3.7, barHalfWidth: 1.15, cornerRadius: 0.9))
        } else {
            p.addPath(CGPath(roundedRect: CGRect(x: lensCenter.x - 3.7, y: lensCenter.y - 1.15, width: 7.4, height: 2.3), cornerWidth: 1.15, cornerHeight: 1.15, transform: nil))
        }
        return p
    }

    private static func makeFourWayMovePath() -> CGPath {
        let p = CGMutablePath()
        let dotR: CGFloat = 3.2
        p.addEllipse(in: CGRect(x: -dotR, y: -dotR, width: dotR * 2, height: dotR * 2))
        for angle in [0.0, CGFloat.pi * 0.5, CGFloat.pi, -CGFloat.pi * 0.5] {
            let tri = IPadResizePaths.makeAccessoryTriangle(tipX: 12.6, baseX: 6.4, halfHeight: 4.0)
            var rot = CGAffineTransform(rotationAngle: angle)
            if let rotated = tri.copy(using: &rot) {
                p.addPath(rotated)
            }
        }
        return p
    }

    private static func makeCellPlusPath() -> CGPath {
        makeUnifiedPlusPath(armHalfLength: 10.2, barHalfWidth: 2.45, cornerRadius: 2.0)
    }

    private static func makeHelpPath() -> CGPath {
        let p = CGMutablePath()
        let r: CGFloat = 10.6
        p.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        let q = CGMutablePath()
        q.addArc(center: CGPoint(x: 0.0, y: 2.8), radius: 2.9, startAngle: .pi * 0.92, endAngle: -.pi * 0.25, clockwise: true)
        q.addQuadCurve(to: CGPoint(x: 0.0, y: -1.6), control: CGPoint(x: 0.2, y: -0.4))
        p.addPath(q.copy(strokingWithWidth: 2.2, lineCap: .round, lineJoin: .round, miterLimit: 2.0))
        p.addEllipse(in: CGRect(x: -1.35, y: -6.4, width: 2.7, height: 2.7))
        return p
    }

    private static func makeCameraWindowPath() -> CGPath {
        let p = CGMutablePath()
        p.addPath(CGPath(roundedRect: CGRect(x: -11.5, y: -8.0, width: 23.0, height: 14.5), cornerWidth: 4.2, cornerHeight: 4.2, transform: nil))
        p.addPath(CGPath(roundedRect: CGRect(x: -5.0, y: 4.0, width: 10.0, height: 5.5), cornerWidth: 2.4, cornerHeight: 2.4, transform: nil))
        p.addEllipse(in: CGRect(x: -4.4, y: -5.2, width: 8.8, height: 8.8))
        return p
    }

    private static func makeEyedropperPath() -> CGPath {
        let p = CGMutablePath()
        let barrel = CGMutablePath()
        barrel.move(to: CGPoint(x: -11.0, y: -11.0))
        barrel.addLine(to: CGPoint(x: -7.5, y: -9.8))
        barrel.addLine(to: CGPoint(x: 4.2, y: 1.9))
        barrel.addLine(to: CGPoint(x: 1.9, y: 4.2))
        barrel.addLine(to: CGPoint(x: -9.8, y: -7.5))
        barrel.closeSubpath()
        p.addPath(barrel)

        let collar = CGPath(roundedRect: CGRect(x: -5.6, y: -1.5, width: 11.2, height: 3.0), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        var collarT = CGAffineTransform(translationX: 3.2, y: 3.2).rotated(by: -.pi * 0.25)
        if let c = collar.copy(using: &collarT) {
            p.addPath(c)
        }

        let bulb = CGPath(roundedRect: CGRect(x: -3.2, y: -4.6, width: 6.4, height: 9.2), cornerWidth: 3.2, cornerHeight: 3.2, transform: nil)
        var bulbT = CGAffineTransform(translationX: 7.4, y: 7.4).rotated(by: -.pi * 0.25)
        if let b = bulb.copy(using: &bulbT) {
            p.addPath(b)
        }
        return p
    }
}

/// Authentic Apple UIPointerAccessory chevron arrows positioned around a snapped slider thumb or stepper.
public enum IPadAccessoryPaths {
    public static func makeAccessoriesPath(kind: PointerAccessoryKind, targetSize: CGSize, padding: CGFloat = 18.0) -> (path: CGPath, canvasSize: CGSize) {
        let canvasW = targetSize.width + padding * 2.0
        let canvasH = targetSize.height + padding * 2.0
        let cx = canvasW * 0.5
        let cy = canvasH * 0.5
        let p = CGMutablePath()

        switch kind {
        case .none:
            break
        case .horizontalArrows:
            let halfW = targetSize.width * 0.5
            let leftTri = IPadResizePaths.makeAccessoryTriangle(tipX: -(halfW + 10.5), baseX: -(halfW + 5.0), halfHeight: 3.8)
            let rightTri = IPadResizePaths.makeAccessoryTriangle(tipX: halfW + 10.5, baseX: halfW + 5.0, halfHeight: 3.8)
            var shift = CGAffineTransform(translationX: cx, y: cy)
            if let l = leftTri.copy(using: &shift) { p.addPath(l) }
            if let r = rightTri.copy(using: &shift) { p.addPath(r) }
        case .verticalArrows:
            let halfH = targetSize.height * 0.5
            let baseUp = IPadResizePaths.makeAccessoryTriangle(tipX: halfH + 10.5, baseX: halfH + 5.0, halfHeight: 3.8)
            let baseDown = IPadResizePaths.makeAccessoryTriangle(tipX: -(halfH + 10.5), baseX: -(halfH + 5.0), halfHeight: 3.8)
            var rotUp = CGAffineTransform(translationX: cx, y: cy).rotated(by: .pi * 0.5)
            var rotDown = CGAffineTransform(translationX: cx, y: cy).rotated(by: .pi * 0.5)
            if let u = baseUp.copy(using: &rotUp) { p.addPath(u) }
            if let d = baseDown.copy(using: &rotDown) { p.addPath(d) }
        }
        return (p, CGSize(width: canvasW, height: canvasH))
    }
}

