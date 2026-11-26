import CoreGraphics
import Foundation

/// Pure, cross-app geometry, eligibility, and corner-radius resolver for macOS AppKit, SwiftUI,
/// WebKit, Chromium, and Electron accessibility elements.
public enum ElementGeometryResolver {
    private static let macOSApplicablePrefixes: [String] = [
        "electron:",
        "not-windows:",
        "macos:",
        "darwin:"
    ]

    /// Evaluates whether an interactive control or clickable row should receive a magnetic pointer snap.
    /// Preserves Apple's SizeRuleEvaluator thresholds while also allowing wide macOS buttons, sidebar rows,
    /// primary CTA buttons, clickable cards/tiles, and tabs that macOS & web apps routinely use.
    public static func isControlSizeEligible(
        size: CGSize,
        role: String,
        subrole: String,
        isExplicitControl: Bool,
        isInsideToolbar: Bool,
        isSidebarRow: Bool
    ) -> Bool {
        let minDim = min(size.width, size.height)
        let maxDim = max(size.width, size.height)
        guard minDim > 4.0, maxDim > 4.0, minDim.isFinite, maxDim.isFinite else {
            return false
        }
        if SizeRuleEvaluator.isEligible(size: size, explicitControl: isExplicitControl || isInsideToolbar || isSidebarRow) {
            return true
        }
        // 1. Wide horizontal semantic buttons & primary CTAs (e.g. 596x50 modal buttons, dropdown bars)
        if isExplicitControl && size.width >= size.height && size.height >= 14.0 && size.height <= 64.0 && size.width <= 720.0 {
            return true
        }
        // 2. Sidebar/chat/Settings/Finder list rows
        let isRowLike = isSidebarRow || role == "AXRow" || role == "AXOutlineRow" || role == "AXCell" || subrole == "AXApplicationGroup" || subrole == "AXOutlineRow" || subrole == "AXTableRow"
        if isRowLike && size.width >= size.height && size.height >= 16.0 && size.height <= 72.0 && size.width <= 460.0 {
            return true
        }
        // 3. Interactive cards, media tiles, product cards, and Control Center modules (e.g. 219x184)
        if (isExplicitControl || role == "AXLayoutItem" || role == "AXImage")
            && size.width >= 14.0 && size.width <= 360.0
            && size.height >= 14.0 && size.height <= 280.0 {
            return true
        }
        return false
    }

    /// Resolves CSS/Tailwind border-radius classes (including macOS/Electron platform prefixes and
    /// arbitrary pixel/rem/token declarations) from AXDOMClassList.
    public static func domCornerRadius(
        classes: [String],
        minDim: CGFloat,
        ancestorTokenClasses: [String] = []
    ) -> CGFloat? {
        let maxR = max(0.0, minDim * 0.5)
        guard maxR > 0 else { return nil }

        var uniformResolved: CGFloat?
        var directionalResolved: CGFloat?
        var cssVarRadius: CGFloat?

        for rawClass in classes {
            let cls = stripMacOSPlatformPrefix(rawClass)
            // Ignore interactive/state/breakpoint variants (hover:, focus:, dark:, sm:, group-data-[...]:, etc.)
            if cls.contains(":") {
                // Still inspect explicit CSS custom property tokens like [--radius-token-row:10px]
                if let varR = parseCSSRadiusVariable(cls, maxR: maxR) {
                    cssVarRadius = varR
                }
                continue
            }
            if let r = parseUniformRoundedClass(cls, maxR: maxR) {
                uniformResolved = r
            } else if let dr = parseDirectionalRoundedClass(cls, maxR: maxR) {
                directionalResolved = dr
            }
        }

        if let uniformResolved {
            return uniformResolved
        }
        if let directionalResolved {
            return directionalResolved
        }
        if let cssVarRadius {
            return cssVarRadius
        }

        // Check ancestor custom radius tokens (e.g. Codex rail wrapper's [--radius-token-row:10px])
        for rawClass in ancestorTokenClasses {
            let cls = stripMacOSPlatformPrefix(rawClass)
            if let varR = parseCSSRadiusVariable(cls, maxR: maxR) {
                return varR
            }
        }
        return nil
    }

    /// Resolves the most faithful visual corner radius for a control when no explicit CSS class exists,
    /// matching native macOS 26/27 & iPadOS control geometry instead of forcing all controls <= 44pt into pills.
    public static func resolveCornerRadius(
        visualRect: CGRect,
        role: String,
        subrole: String,
        isInsideToolbar: Bool,
        isSidebarRow: Bool,
        isCircularCloseOrDelete: Bool,
        isNotchButton: Bool,
        domRadius: CGFloat?
    ) -> CGFloat {
        let minDim = max(1.0, min(visualRect.width, visualRect.height))
        let maxDim = max(visualRect.width, visualRect.height)
        let maxR = minDim * 0.5

        if let domRadius {
            return max(0.0, min(maxR, domRadius))
        }

        // 1. Controls that are genuinely circular or full capsule pills on macOS/iPadOS
        if isNotchButton
            || isCircularCloseOrDelete
            || role == "AXSwitch"
            || role == "AXHandle"
            || role == "AXRulerMarker"
            || subrole == "AXSwitch"
            || subrole == "AXSegment"
            || subrole == "AXCloseButton"
            || (role == "AXRadioButton" && subrole != "AXTabButton" && maxDim <= minDim * 1.25) {
            return maxR
        }

        // 2. Native macOS 26/27 toolbar buttons and compact circular icons (<= 22pt)
        let isSquareish = abs(visualRect.width - visualRect.height) <= 5.0
        if isInsideToolbar && minDim <= 40.0 && !isSidebarRow {
            return maxR
        }
        if isSquareish && maxDim <= 22.0 && role != "AXCheckBox" {
            return maxR
        }

        // 3. True checkbox square (not AXSwitch, not AXToggleButton)
        if role == "AXCheckBox" && subrole != "AXToggleButton" && subrole != "AXSwitch" {
            return min(maxR, min(minDim * 0.26, 5.0))
        }

        // 4. Tabs (AXTab / AXTabButton)
        if role == "AXTab" || subrole == "AXTabButton" {
            return min(maxR, min(minDim * 0.30, 8.0))
        }

        // 5. Square / near-square icon & toggle buttons (e.g. 28x28, 32x32, 36x36, 40x40 rail/header icons)
        if isSquareish && minDim <= 56.0 {
            return min(maxR, min(minDim * 0.28, 10.0))
        }

        // 6. Sidebar rows, chat list rows, Settings rows
        if isSidebarRow || role == "AXRow" || role == "AXOutlineRow" || role == "AXCell" || subrole == "AXApplicationGroup" || subrole == "AXOutlineRow" || subrole == "AXTableRow" {
            return min(maxR, min(minDim * 0.30, 10.0))
        }

        // 7. Interactive cards / tiles (e.g. 219x184 product cards, Control Center tiles)
        if visualRect.width >= 110.0 && visualRect.height >= 72.0 {
            return min(maxR, min(minDim * 0.14, 16.0))
        }

        // 8. Standard rectangular buttons, popups, date/time fields, level indicators, and links
        if minDim <= 20.0 {
            return min(maxR, min(minDim * 0.32, 6.0))
        }
        if minDim <= 34.0 {
            return min(maxR, ApplePointerConstants.Geometry.defaultPointerCornerRadius)
        }
        if minDim <= 52.0 {
            return min(maxR, min(minDim * 0.26, 10.0))
        }
        return min(maxR, min(minDim * 0.22, 14.0))
    }

    /// Resolves natural iPadOS breathing padding around compact icons and tight inline text controls.
    public static func resolvePadding(
        visualRect: CGRect,
        role: String,
        isInsideToolbar: Bool,
        isSidebarRow: Bool,
        isNotchButton: Bool
    ) -> (horizontal: CGFloat, vertical: CGFloat) {
        guard !isInsideToolbar && !isSidebarRow && !isNotchButton else {
            return (0.0, 0.0)
        }
        let maxDim = max(visualRect.width, visualRect.height)
        let minDim = min(visualRect.width, visualRect.height)
        if maxDim <= 20.0 {
            return (3.0, 3.0)
        }
        if maxDim <= 24.0 {
            return (2.0, 2.0)
        }
        // Tight inline text buttons / mentions (e.g. 122x17 InlineMentionFocusRing) match AXLink breathing room
        if (role == "AXButton" || role == "AXLink") && visualRect.height <= 20.0 && visualRect.width >= 24.0 && minDim <= 20.0 {
            return (4.0, 2.0)
        }
        return (0.0, 0.0)
    }

    /// Trims oversized macOS 26/27 NSToolbarItem frames (~48-64pt tall) to the visible centered glass pill (~36pt).
    public static func normalizeToolbarRect(_ rect: CGRect, isInsideToolbar: Bool) -> CGRect {
        guard isInsideToolbar,
              rect.height >= 46.0,
              rect.height <= 64.0,
              rect.width <= 260.0 else {
            return rect
        }
        let pillHeight = min(36.0, max(28.0, rect.height - 14.0))
        return CGRect(
            x: rect.minX,
            y: rect.midY - pillHeight * 0.5,
            width: rect.width,
            height: pillHeight
        )
    }

    private static func stripMacOSPlatformPrefix(_ cls: String) -> String {
        var current = cls
        var changed = true
        while changed {
            changed = false
            for prefix in macOSApplicablePrefixes where current.hasPrefix(prefix) {
                current = String(current.dropFirst(prefix.count))
                changed = true
            }
        }
        return current
    }

    private static func parseUniformRoundedClass(_ cls: String, maxR: CGFloat) -> CGFloat? {
        switch cls {
        case "rounded-none":
            return 0.0
        case "rounded-full", "rounded-pill", "rounded-circle":
            return maxR
        case "rounded-3xl":
            return min(maxR, 24.0)
        case "rounded-2xl":
            return min(maxR, 16.0)
        case "rounded-xl", "rounded-xl-base":
            return min(maxR, 12.0)
        case "rounded-lg":
            return min(maxR, 8.0)
        case "rounded-md":
            return min(maxR, 6.0)
        case "rounded", "rounded-sm":
            return min(maxR, 4.0)
        case "rounded-xs":
            return min(maxR, 2.0)
        case "rounded-button-action", "rounded-button", "rounded-control":
            return min(maxR, 10.0)
        default:
            return parseArbitraryRoundedValue(cls, prefix: "rounded-[", maxR: maxR)
        }
    }

    private static func parseDirectionalRoundedClass(_ cls: String, maxR: CGFloat) -> CGFloat? {
        let prefixes = ["rounded-t-", "rounded-b-", "rounded-l-", "rounded-r-", "rounded-s-", "rounded-e-"]
        for prefix in prefixes where cls.hasPrefix(prefix) {
            let tail = String(cls.dropFirst(prefix.count))
            if let r = parseUniformRoundedClass("rounded-\(tail)", maxR: maxR) {
                return r
            }
        }
        return nil
    }

    private static func parseArbitraryRoundedValue(_ cls: String, prefix: String, maxR: CGFloat) -> CGFloat? {
        guard cls.hasPrefix(prefix), cls.hasSuffix("]") else { return nil }
        let inner = String(cls.dropFirst(prefix.count).dropLast())
        return parseCSSLength(inner, maxR: maxR)
    }

    private static func parseCSSRadiusVariable(_ cls: String, maxR: CGFloat) -> CGFloat? {
        // Matches Tailwind arbitrary CSS vars like "[--radius-token-row:10px]" or "browser:[--radius-token-row:10px]"
        guard let bracketStart = cls.firstIndex(of: "["),
              cls.hasSuffix("]") else {
            return nil
        }
        let inside = String(cls[cls.index(after: bracketStart)..<cls.index(before: cls.endIndex)])
        guard inside.hasPrefix("--"),
              let colon = inside.firstIndex(of: ":") else {
            return nil
        }
        let varName = inside[..<colon].lowercased()
        guard varName.contains("radius") else { return nil }
        let valueStr = String(inside[inside.index(after: colon)...])
        return parseCSSLength(valueStr, maxR: maxR)
    }

    private static func parseCSSLength(_ value: String, maxR: CGFloat) -> CGFloat? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "0" || trimmed == "0px" || trimmed == "0rem" {
            return 0.0
        }
        if trimmed == "50%" || trimmed == "9999px" || trimmed == "999px" {
            return maxR
        }
        if trimmed.hasSuffix("px"), let v = Double(trimmed.dropLast(2)), v >= 0 {
            return min(maxR, CGFloat(v))
        }
        if trimmed.hasSuffix("rem"), let v = Double(trimmed.dropLast(3)), v >= 0 {
            return min(maxR, CGFloat(v * 16.0))
        }
        return nil
    }
}
