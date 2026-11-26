import CoreGraphics
import Foundation

public enum MaterialPreset: String, Codable, CaseIterable, Sendable {
    case classicIPadOS
    case liquidGlass

    public var displayName: String {
        switch self {
        case .classicIPadOS: return "Classic"
        case .liquidGlass: return "Liquid Glass"
        }
    }
}

public enum PointerShapeStyle: String, Codable, CaseIterable, Sendable {
    case appleMouse
    case ipadDot

    public var displayName: String {
        switch self {
        case .appleMouse: return "Mouse"
        case .ipadDot: return "Dot"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "appleMouse", "adaptiveArrow":
            self = .appleMouse
        case "ipadDot", "classicCircle":
            self = .ipadDot
        default:
            self = .appleMouse
        }
    }
}

public enum ResizeCursorKind: String, Codable, Equatable, Sendable {
    case none
    case splitHorizontal
    case splitVertical
    case horizontal
    case vertical
    case diagonalNWSE
    case diagonalNESW
    case cornerNW
    case cornerNE
    case cornerSW
    case cornerSE
    case left
    case right
    case up
    case down
}

public enum SpecialCursorKind: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case openHand
    case closedHand
    case dragCopy
    case dragLink
    case operationNotAllowed
    case contextualMenu
    case disappearingItem
    case zoomIn
    case zoomOut
    case move
    case cell
    case help
    case screenshotWindow
    case eyedropper
}

public enum PointerAccessoryKind: String, Codable, Equatable, Sendable {
    case none
    case horizontalArrows
    case verticalArrows
}

public struct PointerConfiguration: Codable, Equatable, Sendable {
    public static let dotSizeRange: ClosedRange<CGFloat> = 0.50...2.00
    public static let mouseSizeRange: ClosedRange<CGFloat> = 1.00...2.00
    public static let dotIntensityRange: ClosedRange<CGFloat> = 0.50...1.50
    public static let highlightContrastRange: ClosedRange<CGFloat> = 0.50...2.00
    public static let defaultHighlightContrast: CGFloat = 1.00
    public static let autohideDurationRange: ClosedRange<TimeInterval> = 1.0...15.0
    public static let defaultExcludedBundleIDs: [String] = [
        "com.apple.ScreenSharing",
        "com.apple.ScreenContinuity",
        "com.carriez.rustdesk",
        "com.parsec.client",
        "com.moonlight-stream.Moonlight",
        "com.teamviewer.TeamViewer",
        "com.anydesk.Anydesk",
        "com.realvnc.vncviewer"
    ]

    public var enabled: Bool
    public var pointerShapeStyle: PointerShapeStyle
    public var materialPreset: MaterialPreset
    public var dotLiquidGlassEnabled: Bool
    public var dotSizeMultiplier: CGFloat
    public var dotIntensity: CGFloat
    public var highlightContrast: CGFloat
    public var mouseSizeMultiplier: CGFloat
    public var magnetismEnabled: Bool
    public var inertiaEnabled: Bool
    public var specularEnabled: Bool
    public var autohideEnabled: Bool
    public var autohideDuration: TimeInterval
    public var hideWhileTyping: Bool
    public var smoothTypingCaretEnabled: Bool
    public var shakeToFindEnabled: Bool
    public var scaleWithZoomEnabled: Bool
    public var showNativeResizeCursors: Bool
    public var highContrast: Bool
    public var showCenterDot: Bool
    public var passThroughUnknownCustomCursors: Bool
    public var excludedBundleIDs: [String]

    public var liquidGlassEnabled: Bool {
        get { materialPreset == .liquidGlass }
        set { materialPreset = newValue ? .liquidGlass : .classicIPadOS }
    }

    /// Size multiplier for the currently selected pointer style, clamped to that style's valid range.
    public var activeSizeMultiplier: CGFloat {
        switch pointerShapeStyle {
        case .appleMouse:
            return Self.clampMouseSize(mouseSizeMultiplier)
        case .ipadDot:
            return Self.clampDotSize(dotSizeMultiplier)
        }
    }

    /// Convenience accessor bound to the active pointer style's size multiplier.
    public var pointerSizeMultiplier: CGFloat {
        get { activeSizeMultiplier }
        set {
            switch pointerShapeStyle {
            case .appleMouse:
                mouseSizeMultiplier = Self.clampMouseSize(newValue)
            case .ipadDot:
                dotSizeMultiplier = Self.clampDotSize(newValue)
            }
        }
    }

    public static func clampDotSize(_ value: CGFloat) -> CGFloat {
        max(dotSizeRange.lowerBound, min(dotSizeRange.upperBound, value))
    }

    public static func clampMouseSize(_ value: CGFloat) -> CGFloat {
        max(mouseSizeRange.lowerBound, min(mouseSizeRange.upperBound, value))
    }

    public static func clampDotIntensity(_ value: CGFloat) -> CGFloat {
        max(dotIntensityRange.lowerBound, min(dotIntensityRange.upperBound, value))
    }

    public static func clampHighlightContrast(_ value: CGFloat) -> CGFloat {
        max(highlightContrastRange.lowerBound, min(highlightContrastRange.upperBound, value))
    }

    public static func clampAutohideDuration(_ value: TimeInterval) -> TimeInterval {
        max(autohideDurationRange.lowerBound, min(autohideDurationRange.upperBound, value))
    }

    public init(
        enabled: Bool = true,
        pointerShapeStyle: PointerShapeStyle = .appleMouse,
        materialPreset: MaterialPreset = .liquidGlass,
        dotLiquidGlassEnabled: Bool? = nil,
        dotSizeMultiplier: CGFloat = 1.0,
        dotIntensity: CGFloat = 1.0,
        highlightContrast: CGFloat = PointerConfiguration.defaultHighlightContrast,
        mouseSizeMultiplier: CGFloat = 1.0,
        magnetismEnabled: Bool = true,
        inertiaEnabled: Bool = true,
        specularEnabled: Bool = true,
        autohideEnabled: Bool = true,
        autohideDuration: TimeInterval = ApplePointerConstants.Behavior.autohideDurationMouse,
        hideWhileTyping: Bool = true,
        smoothTypingCaretEnabled: Bool = false,
        shakeToFindEnabled: Bool = true,
        scaleWithZoomEnabled: Bool = true,
        showNativeResizeCursors: Bool = false,
        highContrast: Bool = false,
        showCenterDot: Bool = false,
        passThroughUnknownCustomCursors: Bool = true,
        excludedBundleIDs: [String] = PointerConfiguration.defaultExcludedBundleIDs
    ) {
        self.enabled = enabled
        self.pointerShapeStyle = pointerShapeStyle
        self.materialPreset = materialPreset
        self.dotLiquidGlassEnabled = dotLiquidGlassEnabled ?? (materialPreset == .liquidGlass)
        self.dotSizeMultiplier = Self.clampDotSize(dotSizeMultiplier)
        self.dotIntensity = Self.clampDotIntensity(dotIntensity)
        self.highlightContrast = Self.clampHighlightContrast(highlightContrast)
        self.mouseSizeMultiplier = Self.clampMouseSize(mouseSizeMultiplier)
        self.magnetismEnabled = magnetismEnabled
        self.inertiaEnabled = inertiaEnabled
        self.specularEnabled = specularEnabled
        self.autohideEnabled = autohideEnabled
        self.autohideDuration = Self.clampAutohideDuration(autohideDuration)
        self.hideWhileTyping = hideWhileTyping
        self.smoothTypingCaretEnabled = smoothTypingCaretEnabled
        self.shakeToFindEnabled = shakeToFindEnabled
        self.scaleWithZoomEnabled = scaleWithZoomEnabled
        self.showNativeResizeCursors = showNativeResizeCursors
        self.highContrast = highContrast
        self.showCenterDot = showCenterDot
        self.passThroughUnknownCustomCursors = passThroughUnknownCustomCursors
        self.excludedBundleIDs = excludedBundleIDs
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case pointerShapeStyle
        case materialPreset
        case dotLiquidGlassEnabled
        case dotSizeMultiplier
        case dotIntensity
        case highlightContrast
        case mouseSizeMultiplier
        case pointerSizeMultiplier
        case magnetismEnabled
        case inertiaEnabled
        case specularEnabled
        case autohideEnabled
        case autohideDuration
        case hideWhileTyping
        case smoothTypingCaretEnabled
        case shakeToFindEnabled
        case scaleWithZoomEnabled
        case showNativeResizeCursors
        case highContrast
        case showCenterDot
        case passThroughUnknownCustomCursors
        case excludedBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.pointerShapeStyle = try c.decodeIfPresent(PointerShapeStyle.self, forKey: .pointerShapeStyle) ?? .appleMouse
        self.materialPreset = try c.decodeIfPresent(MaterialPreset.self, forKey: .materialPreset) ?? .liquidGlass
        self.dotLiquidGlassEnabled = try c.decodeIfPresent(Bool.self, forKey: .dotLiquidGlassEnabled) ?? (self.materialPreset == .liquidGlass)
        let legacySize = try c.decodeIfPresent(CGFloat.self, forKey: .pointerSizeMultiplier) ?? 1.0
        self.dotSizeMultiplier = Self.clampDotSize(try c.decodeIfPresent(CGFloat.self, forKey: .dotSizeMultiplier) ?? legacySize)
        self.dotIntensity = Self.clampDotIntensity(try c.decodeIfPresent(CGFloat.self, forKey: .dotIntensity) ?? 1.0)
        self.highlightContrast = Self.clampHighlightContrast(try c.decodeIfPresent(CGFloat.self, forKey: .highlightContrast) ?? Self.defaultHighlightContrast)
        self.mouseSizeMultiplier = Self.clampMouseSize(try c.decodeIfPresent(CGFloat.self, forKey: .mouseSizeMultiplier) ?? legacySize)
        self.magnetismEnabled = try c.decodeIfPresent(Bool.self, forKey: .magnetismEnabled) ?? true
        self.inertiaEnabled = try c.decodeIfPresent(Bool.self, forKey: .inertiaEnabled) ?? true
        self.specularEnabled = try c.decodeIfPresent(Bool.self, forKey: .specularEnabled) ?? true
        self.autohideEnabled = try c.decodeIfPresent(Bool.self, forKey: .autohideEnabled) ?? true
        self.autohideDuration = Self.clampAutohideDuration(try c.decodeIfPresent(TimeInterval.self, forKey: .autohideDuration) ?? ApplePointerConstants.Behavior.autohideDurationMouse)
        self.hideWhileTyping = try c.decodeIfPresent(Bool.self, forKey: .hideWhileTyping) ?? true
        self.smoothTypingCaretEnabled = try c.decodeIfPresent(Bool.self, forKey: .smoothTypingCaretEnabled) ?? false
        self.shakeToFindEnabled = try c.decodeIfPresent(Bool.self, forKey: .shakeToFindEnabled) ?? true
        self.scaleWithZoomEnabled = try c.decodeIfPresent(Bool.self, forKey: .scaleWithZoomEnabled) ?? true
        self.showNativeResizeCursors = try c.decodeIfPresent(Bool.self, forKey: .showNativeResizeCursors) ?? false
        self.highContrast = try c.decodeIfPresent(Bool.self, forKey: .highContrast) ?? false
        self.showCenterDot = try c.decodeIfPresent(Bool.self, forKey: .showCenterDot) ?? false
        self.passThroughUnknownCustomCursors = try c.decodeIfPresent(Bool.self, forKey: .passThroughUnknownCustomCursors) ?? true
        self.excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? Self.defaultExcludedBundleIDs
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(pointerShapeStyle, forKey: .pointerShapeStyle)
        try c.encode(materialPreset, forKey: .materialPreset)
        try c.encode(dotLiquidGlassEnabled, forKey: .dotLiquidGlassEnabled)
        try c.encode(dotSizeMultiplier, forKey: .dotSizeMultiplier)
        try c.encode(dotIntensity, forKey: .dotIntensity)
        try c.encode(highlightContrast, forKey: .highlightContrast)
        try c.encode(mouseSizeMultiplier, forKey: .mouseSizeMultiplier)
        try c.encode(magnetismEnabled, forKey: .magnetismEnabled)
        try c.encode(inertiaEnabled, forKey: .inertiaEnabled)
        try c.encode(specularEnabled, forKey: .specularEnabled)
        try c.encode(autohideEnabled, forKey: .autohideEnabled)
        try c.encode(autohideDuration, forKey: .autohideDuration)
        try c.encode(hideWhileTyping, forKey: .hideWhileTyping)
        try c.encode(smoothTypingCaretEnabled, forKey: .smoothTypingCaretEnabled)
        try c.encode(shakeToFindEnabled, forKey: .shakeToFindEnabled)
        try c.encode(scaleWithZoomEnabled, forKey: .scaleWithZoomEnabled)
        try c.encode(showNativeResizeCursors, forKey: .showNativeResizeCursors)
        try c.encode(highContrast, forKey: .highContrast)
        try c.encode(showCenterDot, forKey: .showCenterDot)
        try c.encode(passThroughUnknownCustomCursors, forKey: .passThroughUnknownCustomCursors)
        try c.encode(excludedBundleIDs, forKey: .excludedBundleIDs)
    }
}

public enum TargetKind: Equatable, Sendable {
    case highlight
    case lift
    case beam
    case hover
    case menuItem
    case scrollThumb
}

public enum OverlayEffectStyle: Equatable, Sendable {
    case none
    case standard
    case prominent
}

/// Fixed-angle polar silhouette (sampleCount rays around the target centroid in Quartz screen points)
/// used to smoothly morph the pointer into organic 3D molecular shapes without axis-aligned boxiness.
public struct OrganicContour: Equatable, Sendable {
    public static let sampleCount = 24

    public let radii: [CGFloat]

    public init(radii: [CGFloat]) {
        if radii.count == Self.sampleCount {
            self.radii = radii
        } else {
            let fallback = radii.first ?? 10.0
            self.radii = Array(repeating: max(4.0, fallback), count: Self.sampleCount)
        }
    }

    public static func circle(radius: CGFloat) -> OrganicContour {
        let r = max(4.0, radius)
        return OrganicContour(radii: Array(repeating: r, count: Self.sampleCount))
    }

    /// Samples a convex 2D polygon along evenly spaced rays from center and applies one light
    /// circular smoothing pass so the resulting closed contour is organic and C1-smooth.
    public static func fromConvexPolygon(_ vertices: [CGPoint], center: CGPoint) -> OrganicContour {
        let n = vertices.count
        guard n >= 3 else {
            return .circle(radius: 10.0)
        }
        var raw = Array(repeating: CGFloat(10.0), count: Self.sampleCount)
        for k in 0..<Self.sampleCount {
            let angle = (CGFloat(k) / CGFloat(Self.sampleCount)) * (.pi * 2.0)
            let dx = cos(angle)
            let dy = sin(angle)
            var bestT: CGFloat = .greatestFiniteMagnitude
            var hit = false
            for i in 0..<n {
                let a = vertices[i]
                let b = vertices[(i + 1) % n]
                let ex = b.x - a.x
                let ey = b.y - a.y
                let denom = dx * ey - dy * ex
                if abs(denom) < 1e-6 { continue }
                let rx = a.x - center.x
                let ry = a.y - center.y
                let t = (rx * ey - ry * ex) / denom
                let u = (rx * dy - ry * dx) / denom
                if t >= 0.0 && u >= -1e-4 && u <= 1.0001 {
                    if t < bestT {
                        bestT = t
                        hit = true
                    }
                }
            }
            if hit && bestT.isFinite {
                raw[k] = max(4.0, min(180.0, bestT))
            }
        }
        var smoothed = raw
        for k in 0..<Self.sampleCount {
            let prev = raw[(k - 1 + Self.sampleCount) % Self.sampleCount]
            let curr = raw[k]
            let next = raw[(k + 1) % Self.sampleCount]
            smoothed[k] = max(4.0, min(180.0, prev * 0.16 + curr * 0.68 + next * 0.16))
        }
        return OrganicContour(radii: smoothed)
    }
}

public struct HitTarget: Equatable, Sendable {
    public let id: String
    public let rect: CGRect
    public let regionRect: CGRect
    public let cornerRadius: CGFloat
    public let kind: TargetKind
    public let slipX: CGFloat
    public let slipY: CGFloat
    public let maxSlipPoints: CGFloat
    public let overrideSlipPoints: CGPoint?
    public let scaleUpPoints: CGFloat
    public let horizontalPadding: CGFloat
    public let verticalPadding: CGFloat
    public let overlayEffectStyle: OverlayEffectStyle
    public let accessoryKind: PointerAccessoryKind
    public let perspectiveTiltY: CGFloat
    public let organicContour: OrganicContour?
    public let suppressOutline: Bool

    public init(
        id: String,
        rect: CGRect,
        regionRect: CGRect? = nil,
        cornerRadius: CGFloat,
        kind: TargetKind,
        slipX: CGFloat,
        slipY: CGFloat,
        maxSlipPoints: CGFloat,
        overrideSlipPoints: CGPoint? = nil,
        scaleUpPoints: CGFloat = 0.0,
        horizontalPadding: CGFloat = 0.0,
        verticalPadding: CGFloat = 0.0,
        overlayEffectStyle: OverlayEffectStyle,
        accessoryKind: PointerAccessoryKind = .none,
        perspectiveTiltY: CGFloat = 0.0,
        organicContour: OrganicContour? = nil,
        suppressOutline: Bool = false
    ) {
        self.id = id
        self.rect = rect
        self.regionRect = regionRect ?? rect
        self.cornerRadius = cornerRadius
        self.kind = kind
        self.slipX = slipX
        self.slipY = slipY
        self.maxSlipPoints = maxSlipPoints
        self.overrideSlipPoints = overrideSlipPoints
        self.scaleUpPoints = scaleUpPoints
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.overlayEffectStyle = overlayEffectStyle
        self.accessoryKind = accessoryKind
        self.perspectiveTiltY = perspectiveTiltY
        self.organicContour = organicContour
        self.suppressOutline = suppressOutline
    }
}

public enum SizeRuleEvaluator {
    public static func isEligible(size: CGSize, explicitControl: Bool) -> Bool {
        let minDim = min(size.width, size.height)
        let maxDim = max(size.width, size.height)
        guard minDim > 4.0, maxDim > 4.0, minDim.isFinite, maxDim.isFinite else {
            return false
        }

        let mult: CGFloat = explicitControl ? ApplePointerConstants.SizeRule.explicitRequestMultiplier : 1.0
        let generic = ApplePointerConstants.SizeRule.genericSizeRuleThreshold * mult
        let narrowMinor = ApplePointerConstants.SizeRule.narrowAspectRuleMinorDimensionThreshold * mult
        let narrowMajor = ApplePointerConstants.SizeRule.narrowAspectRuleMajorDimensionThreshold * mult
        let pointerMinor = ApplePointerConstants.SizeRule.pointerSizeRuleMinorDimensionThreshold * mult
        let pointerMajor = ApplePointerConstants.SizeRule.pointerSizeRuleMajorDimensionThreshold * mult

        if maxDim <= generic {
            return true
        }
        if minDim <= narrowMinor && maxDim <= narrowMajor {
            return true
        }
        if minDim <= pointerMinor && maxDim <= pointerMajor {
            return true
        }
        return false
    }
}

public enum Burette3DTargetParser {
    public static let tokenPrefix = "buret-pt-v2-"
    public static let legacyTokenPrefix = "buret-pt-v1-"

    public static func isToken(_ className: String) -> Bool {
        className.hasPrefix(tokenPrefix) || className.hasPrefix(legacyTokenPrefix)
    }

    public static func parse(token: String, hostFrame: CGRect, point: CGPoint) -> HitTarget? {
        let payload: Substring
        if token.hasPrefix(tokenPrefix) {
            payload = token.dropFirst(tokenPrefix.count)
        } else if token.hasPrefix(legacyTokenPrefix) {
            payload = token.dropFirst(legacyTokenPrefix.count)
        } else {
            return nil
        }
        guard hostFrame.width >= 40.0, hostFrame.height >= 40.0,
              hostFrame.minX.isFinite, hostFrame.minY.isFinite,
              hostFrame.width.isFinite, hostFrame.height.isFinite else {
            return nil
        }
        let parts = payload.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 6 else { return nil }

        let pieceID = String(parts[0])
        let shape = parts[1]
        guard !pieceID.isEmpty else { return nil }

        if shape == "p" {
            let coordCount = parts.count - 2
            guard coordCount >= 6, coordCount <= 32, coordCount % 2 == 0 else { return nil }
            var vertices: [CGPoint] = []
            vertices.reserveCapacity(coordCount / 2)
            var minX = CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            var sumX: CGFloat = 0.0
            var sumY: CGFloat = 0.0
            for i in stride(from: 2, to: parts.count, by: 2) {
                guard let u = Int(parts[i]), let v = Int(parts[i + 1]),
                      u >= 0, u <= 10000, v >= 0, v <= 10000 else {
                    return nil
                }
                let x = hostFrame.minX + (CGFloat(u) / 10000.0) * hostFrame.width
                let y = hostFrame.minY + (CGFloat(v) / 10000.0) * hostFrame.height
                vertices.append(CGPoint(x: x, y: y))
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
                sumX += x
                sumY += y
            }
            let rawRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            guard rawRect.width >= 6.0, rawRect.height >= 6.0,
                  rawRect.width <= 320.0, rawRect.height <= 320.0 else {
                return nil
            }
            guard rawRect.insetBy(dx: -24.0, dy: -24.0).contains(point) else {
                return nil
            }
            let centroid = CGPoint(x: sumX / CGFloat(vertices.count), y: sumY / CGFloat(vertices.count))
            let contour = OrganicContour.fromConvexPolygon(vertices, center: centroid)
            let halfW = max(7.0, max(centroid.x - minX, maxX - centroid.x))
            let halfH = max(7.0, max(centroid.y - minY, maxY - centroid.y))
            let centeredRect = CGRect(
                x: centroid.x - halfW,
                y: centroid.y - halfH,
                width: halfW * 2.0,
                height: halfH * 2.0
            )
            let minDim = min(rawRect.width, rawRect.height)
            let maxSlip = min(4.5, max(1.8, minDim * 0.14))
            return HitTarget(
                id: "burette-3d-\(pieceID)",
                rect: centeredRect,
                regionRect: rawRect.insetBy(dx: -6.0, dy: -6.0),
                cornerRadius: minDim * 0.5,
                kind: .highlight,
                slipX: 0.06,
                slipY: 0.06,
                maxSlipPoints: maxSlip,
                horizontalPadding: 0.0,
                verticalPadding: 0.0,
                overlayEffectStyle: .none,
                organicContour: contour,
                suppressOutline: true
            )
        }

        guard parts.count == 6,
              let u0 = Int(parts[2]),
              let v0 = Int(parts[3]),
              let u1 = Int(parts[4]),
              let v1 = Int(parts[5]),
              u0 >= 0, v0 >= 0, u1 <= 10000, v1 <= 10000,
              u1 > u0, v1 > v0 else {
            return nil
        }

        let x0 = hostFrame.minX + (CGFloat(u0) / 10000.0) * hostFrame.width
        let y0 = hostFrame.minY + (CGFloat(v0) / 10000.0) * hostFrame.height
        let x1 = hostFrame.minX + (CGFloat(u1) / 10000.0) * hostFrame.width
        let y1 = hostFrame.minY + (CGFloat(v1) / 10000.0) * hostFrame.height
        let rawRect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)

        guard rawRect.width >= 6.0, rawRect.height >= 6.0,
              rawRect.width <= 320.0, rawRect.height <= 320.0 else {
            return nil
        }
        guard rawRect.insetBy(dx: -24.0, dy: -24.0).contains(point) else {
            return nil
        }

        let visualRect: CGRect
        if shape == "c" {
            let side = max(14.0, max(rawRect.width, rawRect.height))
            visualRect = CGRect(x: rawRect.midX - side * 0.5, y: rawRect.midY - side * 0.5, width: side, height: side)
        } else {
            let w = max(22.0, rawRect.width)
            let h = max(22.0, rawRect.height)
            visualRect = CGRect(x: rawRect.midX - w * 0.5, y: rawRect.midY - h * 0.5, width: w, height: h)
        }

        let minDim = min(visualRect.width, visualRect.height)
        let cornerRadius: CGFloat
        switch shape {
        case "c", "p":
            cornerRadius = minDim * 0.5
        default:
            cornerRadius = minDim <= 30.0 ? minDim * 0.5 : min(minDim * 0.36, 16.0)
        }

        let contour = shape == "c" ? OrganicContour.circle(radius: visualRect.width * 0.5) : nil
        let maxSlip = min(4.5, max(1.8, minDim * 0.14))
        return HitTarget(
            id: "burette-3d-\(pieceID)",
            rect: visualRect,
            regionRect: visualRect.insetBy(dx: -6.0, dy: -6.0),
            cornerRadius: cornerRadius,
            kind: .highlight,
            slipX: 0.06,
            slipY: 0.06,
            maxSlipPoints: maxSlip,
            horizontalPadding: 0.0,
            verticalPadding: 0.0,
            overlayEffectStyle: .none,
            organicContour: contour,
            suppressOutline: true
        )
    }
}

public struct PointerRenderState: Equatable, Sendable {
    public let center: CGPoint
    public let size: CGSize
    public let cornerRadius: CGFloat
    public let totalScale: CGFloat
    public let intensity: CGFloat
    public let opacity: CGFloat
    public let blurRadius: CGFloat
    public let colorMatrix: PointerColorMatrix
    public let isDarkBackground: Bool
    public let lumaMix: CGFloat
    public let pointerShapeStyle: PointerShapeStyle
    public let materialPreset: MaterialPreset
    public let isDotLiquidGlass: Bool
    public let pointerSizeMultiplier: CGFloat
    public let highContrast: Bool
    public let arrowBlend: CGFloat
    public let resizeKind: ResizeCursorKind
    public let resizeBlend: CGFloat
    public let crosshairBlend: CGFloat
    public let specialCursorKind: SpecialCursorKind
    public let specialCursorBlend: CGFloat
    public let accessoryKind: PointerAccessoryKind
    public let accessoryBlend: CGFloat
    public let elasticScaleX: CGFloat
    public let elasticScaleY: CGFloat
    public let specularAlpha: CGFloat
    public let specularScale: CGFloat
    public let specularOffset: CGPoint
    public let rimSpecularAlpha: CGFloat
    public let rimLightDirection: CGPoint
    public let liftShadowAlpha: CGFloat
    public let isSnapped: Bool
    public let isBeam: Bool
    public let isCrosshair: Bool
    public let showCenterDot: Bool
    public let dotVividnessBoost: CGFloat
    public let perspectiveTiltY: CGFloat
    public let innerPointerOffset: CGPoint
    public let innerPointerAlpha: CGFloat
    public let suppressSnappedOutline: Bool
    public let organicContourRadii: [CGFloat]?

    public init(
        center: CGPoint,
        size: CGSize,
        cornerRadius: CGFloat,
        totalScale: CGFloat,
        intensity: CGFloat,
        opacity: CGFloat,
        blurRadius: CGFloat,
        colorMatrix: PointerColorMatrix,
        isDarkBackground: Bool,
        lumaMix: CGFloat = 0.0,
        pointerShapeStyle: PointerShapeStyle = .appleMouse,
        materialPreset: MaterialPreset = .classicIPadOS,
        isDotLiquidGlass: Bool? = nil,
        pointerSizeMultiplier: CGFloat = 1.0,
        highContrast: Bool = false,
        arrowBlend: CGFloat = 0.0,
        resizeKind: ResizeCursorKind = .none,
        resizeBlend: CGFloat = 0.0,
        crosshairBlend: CGFloat = 0.0,
        specialCursorKind: SpecialCursorKind = .none,
        specialCursorBlend: CGFloat = 0.0,
        accessoryKind: PointerAccessoryKind = .none,
        accessoryBlend: CGFloat = 0.0,
        elasticScaleX: CGFloat = 1.0,
        elasticScaleY: CGFloat = 1.0,
        specularAlpha: CGFloat,
        specularScale: CGFloat,
        specularOffset: CGPoint,
        rimSpecularAlpha: CGFloat = 0.0,
        rimLightDirection: CGPoint = CGPoint(x: -0.7, y: 0.7),
        liftShadowAlpha: CGFloat = 0.0,
        isSnapped: Bool,
        isBeam: Bool,
        isCrosshair: Bool = false,
        showCenterDot: Bool,
        dotVividnessBoost: CGFloat = 0.0,
        perspectiveTiltY: CGFloat = 0.0,
        innerPointerOffset: CGPoint = .zero,
        innerPointerAlpha: CGFloat = 0.0,
        suppressSnappedOutline: Bool = false,
        organicContourRadii: [CGFloat]? = nil
    ) {
        self.center = center
        self.size = size
        self.cornerRadius = cornerRadius
        self.totalScale = totalScale
        self.intensity = intensity
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.colorMatrix = colorMatrix
        self.isDarkBackground = isDarkBackground
        self.lumaMix = lumaMix
        self.pointerShapeStyle = pointerShapeStyle
        self.materialPreset = materialPreset
        self.isDotLiquidGlass = isDotLiquidGlass ?? (materialPreset == .liquidGlass)
        self.pointerSizeMultiplier = pointerSizeMultiplier
        self.highContrast = highContrast
        self.arrowBlend = arrowBlend
        self.resizeKind = resizeKind
        self.resizeBlend = resizeBlend
        self.crosshairBlend = crosshairBlend
        self.specialCursorKind = specialCursorKind
        self.specialCursorBlend = specialCursorBlend
        self.accessoryKind = accessoryKind
        self.accessoryBlend = accessoryBlend
        self.elasticScaleX = elasticScaleX
        self.elasticScaleY = elasticScaleY
        self.specularAlpha = specularAlpha
        self.specularScale = specularScale
        self.specularOffset = specularOffset
        self.rimSpecularAlpha = rimSpecularAlpha
        self.rimLightDirection = rimLightDirection
        self.liftShadowAlpha = liftShadowAlpha
        self.isSnapped = isSnapped
        self.isBeam = isBeam
        self.isCrosshair = isCrosshair
        self.showCenterDot = showCenterDot
        self.dotVividnessBoost = dotVividnessBoost
        self.perspectiveTiltY = perspectiveTiltY
        self.innerPointerOffset = innerPointerOffset
        self.innerPointerAlpha = innerPointerAlpha
        self.suppressSnappedOutline = suppressSnappedOutline
        self.organicContourRadii = organicContourRadii
    }
}

public struct SmoothCaretRenderState: Equatable, Sendable {
    public let rect: CGRect
    public let opacity: CGFloat
    public let isVisible: Bool
    public let isDarkBackground: Bool

    public init(rect: CGRect, opacity: CGFloat, isVisible: Bool, isDarkBackground: Bool = false) {
        self.rect = rect
        self.opacity = opacity
        self.isVisible = isVisible
        self.isDarkBackground = isDarkBackground
    }

    public static let hidden = SmoothCaretRenderState(rect: .zero, opacity: 0.0, isVisible: false, isDarkBackground: false)
}

public enum CaretMoveSource: Sendable {
    case typing
    case keyboardNavigation
    case mouseClick
}

public struct ShakeToFindDetector: Sendable {
    private var reversalTimestamps: [TimeInterval] = []
    private var lastVelocitySign: Int = 0
    private var lastPoint: CGPoint?
    private var lastTimestamp: TimeInterval?
    private var lastGestureActiveTime: TimeInterval = -.infinity

    public private(set) var targetMultiplier: CGFloat = 1.0

    public init() {}

    public mutating func reset() {
        reversalTimestamps.removeAll()
        lastVelocitySign = 0
        lastPoint = nil
        lastTimestamp = nil
        lastGestureActiveTime = -.infinity
        targetMultiplier = 1.0
    }

    public mutating func recordMove(point: CGPoint, timestamp: TimeInterval) {
        defer {
            lastPoint = point
            lastTimestamp = timestamp
        }

        guard let prev = lastPoint, let prevT = lastTimestamp else { return }
        let dt = timestamp - prevT
        guard dt > 0 && dt < 0.25 else {
            lastVelocitySign = 0
            return
        }

        let dx = point.x - prev.x
        let dy = point.y - prev.y
        let speed = hypot(dx, dy) / CGFloat(dt)

        guard speed > 180.0 else { return }

        let dominant = abs(dx) >= abs(dy) ? dx : dy
        let sign = dominant > 0 ? 1 : (dominant < 0 ? -1 : 0)
        guard sign != 0 else { return }

        if lastVelocitySign != 0 && sign != lastVelocitySign {
            reversalTimestamps.append(timestamp)
            let cutoff = timestamp - ApplePointerConstants.Behavior.shakeToFindGestureInterval * Double(ApplePointerConstants.Behavior.shakeToFindWiggleCount)
            reversalTimestamps.removeAll { $0 < cutoff }

            if reversalTimestamps.count >= ApplePointerConstants.Behavior.shakeToFindWiggleCount {
                lastGestureActiveTime = timestamp
                let extraWiggles = CGFloat(reversalTimestamps.count - ApplePointerConstants.Behavior.shakeToFindWiggleCount + 1)
                let candidate = 1.0 + extraWiggles * ApplePointerConstants.Behavior.shakeToFindScaleFactor
                targetMultiplier = min(ApplePointerConstants.Behavior.shakeToFindMaxScaleUpFactor, max(targetMultiplier, candidate))
            }
        }
        lastVelocitySign = sign
    }

    public mutating func update(at timestamp: TimeInterval) {
        if timestamp - lastGestureActiveTime > ApplePointerConstants.Behavior.shakeToFindDecayInterval {
            targetMultiplier = 1.0
        }
    }
}
