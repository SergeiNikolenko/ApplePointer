import AppKit
import ApplePointerCore
import ApplicationServices
import Foundation
import QuartzCore

struct StageManagerCardWindow: Sendable {
    let rect: CGRect
    let tiltY: CGFloat
    let occludingRects: [CGRect]
}

final class AccessibilityHitTester: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.nikolenko.ApplePointer.ax", qos: .userInteractive)
    private let lock = NSLock()
    private var pendingPoint: CGPoint?
    private var pendingGeneration: UInt64 = 0
    private var latestGeneration: UInt64 = 0
    private var isProcessing = false
    private var configuredManualAXPIDs: Set<pid_t> = []
    private var notificationCenterPIDCache: [pid_t: Bool] = [:]
    private var codexPIDCache: [pid_t: Bool] = [:]
    private var windowManagerPIDCache: [pid_t: Bool] = [:]

    private let systemWideElement: AXUIElement
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private static let debugLoggingEnabled = ProcessInfo.processInfo.environment["APPLEPOINTER_DEBUG"] == "1"
    private var lastLoggedTargetID: String?
    private var lastHitTestTime: CFTimeInterval = 0
    private var lastHitTestPoint: CGPoint = .zero
    private var lastHitTarget: HitTarget?
    private var lastHitIBeamActive: Bool = false
    private var lastHitWasDynamic3DViewport: Bool = false
    private var systemIBeamActive = false
    private var ownInteractiveWindowRects: [CGRect] = []
    private var cameraNotchRects: [CGRect] = []
    private var stageManagerCards: [StageManagerCardWindow] = []
    private var screenQuartzRects: [CGRect] = []

    var onResult: (@Sendable (HitTarget?) -> Void)?

    private static let semanticInteractiveRoles: Set<String> = [
        "AXButton",
        "AXPopUpButton",
        "AXMenuButton",
        "AXMenuItem",
        "AXRadioButton",
        "AXCheckBox",
        "AXSwitch",
        "AXTab",
        "AXTabButton",
        "AXToolbarButton",
        "AXMenuBarItem",
        "AXMenuExtra",
        "AXDockItem",
        "AXLink",
        "AXDisclosureTriangle",
        "AXColorWell",
        "AXIncrementor",
        "AXSlider",
        "AXScrollBar",
        "AXLevelIndicator",
        "AXDateField",
        "AXTimeField",
        "AXHandle",
        "AXRulerMarker",
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXComboBox"
    ]

    private static let semanticInteractiveSubroles: Set<String> = [
        "AXSegment",
        "AXToggle",
        "AXToggleButton",
        "AXSwitch",
        "AXTabButton",
        "AXToolbarButton",
        "AXSortButton",
        "AXSearchButton",
        "AXClearButton",
        "AXIncrementArrow",
        "AXDecrementArrow",
        "AXIncrementPage",
        "AXDecrementPage",
        "AXRatingIndicator",
        "AXTimeline"
    ]

    /// Never treat an entire native AXMenu container itself as a giant snap target.
    private static let excludedNativeMenuContainerRoles: Set<String> = [
        "AXMenu"
    ]

    private static let textInputRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXComboBox"
    ]

    private static let pureTextRoles: Set<String> = [
        "AXStaticText",
        "AXHeading",
        "AXListMarker"
    ]

    private static let passiveOrWrapperRoles: Set<String> = [
        "AXStaticText",
        "AXImage",
        "AXGroup",
        "AXUnknown",
        "AXHeading",
        "AXGenericElement",
        "AXListMarker",
        "AXLayoutItem",
        "AXCell",
        "AXRow",
        "AXOutlineRow"
    ]

    private static let containerRoles: Set<String> = [
        "AXWebArea",
        "AXWindow",
        "AXGroup",
        "AXScrollArea",
        "AXSplitGroup",
        "AXToolbar",
        "AXTabGroup",
        "AXRadioGroup",
        "AXSegmentedControl",
        "AXList",
        "AXTable",
        "AXOutline",
        "AXBrowser",
        "AXGrid",
        "AXLayoutArea",
        "AXPopover",
        "AXSheet",
        "AXDrawer"
    ]

    private static let dockSubroles: Set<String> = [
        "AXApplicationDockItem",
        "AXDocumentDockItem",
        "AXFolderDockItem",
        "AXURLDockItem",
        "AXMinimizedWindowDockItem",
        "AXDockExtraDockItem",
        "AXTrashDockItem"
    ]

    private static let trafficLightSubroles: Set<String> = [
        "AXCloseButton",
        "AXMinimizeButton",
        "AXFullScreenButton",
        "AXZoomButton"
    ]

    private static let chromiumBundlePrefixes: [String] = [
        "com.google.Chrome",
        "com.openai.codex",
        "com.openai.chat",
        "com.microsoft.VSCode",
        "com.microsoft.edgemac",
        "com.todesktop.",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "app.zen-browser",
        "org.mozilla.firefox",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.figma.Desktop",
        "com.linear",
        "md.obsidian",
        "notion.id",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "com.electron.",
        "com.anthropic."
    ]

    init() {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.05)
        self.systemWideElement = sys
    }

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPrompt() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue!] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func updateSystemIBeamActive(_ active: Bool) {
        lock.lock()
        systemIBeamActive = active
        lock.unlock()
    }

    func updateOwnWindowRects(_ rects: [CGRect]) {
        lock.lock()
        ownInteractiveWindowRects = rects
        lock.unlock()
    }

    func updateCameraNotchRects(_ rects: [CGRect]) {
        lock.lock()
        cameraNotchRects = rects
        lock.unlock()
    }

    func updateStageManagerCards(_ cards: [StageManagerCardWindow]) {
        lock.lock()
        stageManagerCards = cards
        lock.unlock()
    }

    func updateScreenQuartzRects(_ rects: [CGRect]) {
        lock.lock()
        screenQuartzRects = rects
        lock.unlock()
    }

    var isLastHitInDynamic3DViewport: Bool {
        lock.lock()
        let value = lastHitWasDynamic3DViewport
        lock.unlock()
        return value
    }

    private func makeStageManagerCardTarget(at point: CGPoint) -> HitTarget? {
        lock.lock()
        let cards = stageManagerCards
        lock.unlock()
        for card in cards {
            guard card.rect.contains(point) else { continue }
            if card.occludingRects.contains(where: { $0.contains(point) }) {
                continue
            }
            return Self.buildStageManagerTarget(cardRect: card.rect, tiltY: card.tiltY)
        }
        return nil
    }

    private static func buildStageManagerTarget(cardRect: CGRect, tiltY: CGFloat) -> HitTarget {
        // Compensate 3D perspective foreshortening so the rotated trapezoid aligns cleanly with the card edges.
        let preW = cardRect.width * 1.07
        let preH = cardRect.height * 0.94
        let centerShiftX: CGFloat = (tiltY > 0 ? 1.0 : -1.0) * cardRect.width * 0.025
        let tiltedRect = CGRect(
            x: cardRect.midX + centerShiftX - preW * 0.5,
            y: cardRect.midY - preH * 0.5,
            width: preW,
            height: preH
        )
        return HitTarget(
            id: "stagemanager-\(Int(cardRect.minX))-\(Int(cardRect.minY))-\(Int(cardRect.width))x\(Int(cardRect.height))",
            rect: tiltedRect,
            regionRect: cardRect,
            cornerRadius: min(min(preW, preH) * 0.13, 14.0),
            kind: .highlight,
            slipX: 0.025,
            slipY: 0.025,
            maxSlipPoints: 4.0,
            horizontalPadding: 0.0,
            verticalPadding: 0.0,
            overlayEffectStyle: .standard,
            perspectiveTiltY: tiltY
        )
    }

    private func inferredStageManagerTiltY(for rect: CGRect) -> CGFloat? {
        lock.lock()
        let screens = screenQuartzRects
        lock.unlock()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = screens.first(where: { $0.contains(center) }) ?? screens.first else {
            return nil
        }
        let tiltRad: CGFloat = 24.0 * .pi / 180.0
        if center.x < screen.minX + screen.width * 0.35 {
            return tiltRad
        }
        if center.x > screen.maxX - screen.width * 0.35 {
            return -tiltRad
        }
        return nil
    }

    private func makeCameraNotchTarget(at point: CGPoint) -> HitTarget? {
        lock.lock()
        let rects = cameraNotchRects
        lock.unlock()
        for notch in rects {
            let catchRect = notch.insetBy(dx: -4.0, dy: -3.0)
            if catchRect.contains(point) {
                let padded = CGRect(x: notch.minX - 2.0, y: notch.minY, width: notch.width + 4.0, height: notch.height + 2.0)
                return HitTarget(
                    id: "camera-notch-\(Int(notch.minX))-\(Int(notch.minY))-\(Int(notch.width))x\(Int(notch.height))",
                    rect: padded,
                    regionRect: catchRect,
                    cornerRadius: min(padded.height * 0.5, 11.0),
                    kind: .highlight,
                    slipX: 0.04,
                    slipY: 0.04,
                    maxSlipPoints: 3.0,
                    horizontalPadding: 2.0,
                    verticalPadding: 1.0,
                    overlayEffectStyle: .standard
                )
            }
        }
        return nil
    }

    private func isPointInOwnWindow(_ point: CGPoint) -> Bool {
        lock.lock()
        let rects = ownInteractiveWindowRects
        lock.unlock()
        return rects.contains { $0.contains(point) }
    }

    func probe(at point: CGPoint) {
        lock.lock()
        latestGeneration &+= 1
        pendingGeneration = latestGeneration
        pendingPoint = point
        let shouldStart = !isProcessing
        if shouldStart {
            isProcessing = true
        }
        lock.unlock()

        if shouldStart {
            queue.async { [weak self] in
                self?.drainLoop()
            }
        }
    }

    func reset() {
        lock.lock()
        latestGeneration &+= 1
        pendingPoint = nil
        lastHitTarget = nil
        lastHitTestTime = 0
        lastHitWasDynamic3DViewport = false
        lock.unlock()
    }

    func invalidateSpatialCache() {
        lock.lock()
        lastHitTestTime = 0
        lock.unlock()
    }

    private func drainLoop() {
        while true {
            lock.lock()
            guard let point = pendingPoint else {
                isProcessing = false
                lock.unlock()
                return
            }
            let generation = pendingGeneration
            let iBeamActive = systemIBeamActive
            pendingPoint = nil
            let prevTime = lastHitTestTime
            let prevPoint = lastHitTestPoint
            let prevTarget = lastHitTarget
            let prevIBeam = lastHitIBeamActive
            let prevWasDynamic3D = lastHitWasDynamic3DViewport
            lock.unlock()

            let now = CACurrentMediaTime()
            let distFromLast = hypot(point.x - prevPoint.x, point.y - prevPoint.y)
            let sameBeam = (iBeamActive == prevIBeam)
            let prevIsDynamic3D = prevWasDynamic3D || (prevTarget?.id.hasPrefix("burette-3d-") ?? false)
            // Fast spatial reuse: if still comfortably inside the last resolved target and cursor barely moved,
            // skip expensive cross-process AX IPC until either leaving the region or 250 ms elapses.
            if sameBeam,
               !prevIsDynamic3D,
               let prevTarget,
               (now - prevTime) < 0.25,
               distFromLast < 6.0,
               prevTarget.regionRect.insetBy(dx: 1.0, dy: 1.0).contains(point) {
                continue
            }

            // Coalesce high-frequency (120–240 Hz) mouse moves to <= 30 Hz AX IPC unless cursor jumped or I-beam changed.
            let minInterval: CFTimeInterval = prevIsDynamic3D ? 0.016 : 0.032
            let elapsed = now - prevTime
            if sameBeam && elapsed < minInterval && distFromLast < 18.0 {
                Thread.sleep(forTimeInterval: minInterval - elapsed)
                lock.lock()
                let hasNewer = pendingPoint != nil
                let isResetNow = (generation != latestGeneration && pendingPoint == nil)
                lock.unlock()
                if hasNewer || isResetNow {
                    continue
                }
            }

            let (target, inDynamic3D) = hitTest(
                point: point,
                isSystemIBeamActive: iBeamActive
            )
            let completedAt = CACurrentMediaTime()

            lock.lock()
            lastHitTestTime = completedAt
            lastHitTestPoint = point
            lastHitTarget = target
            lastHitIBeamActive = iBeamActive
            lastHitWasDynamic3DViewport = inDynamic3D
            let nextPending = pendingPoint
            let isReset = (generation != latestGeneration && nextPending == nil)
            lock.unlock()
            if isReset {
                continue
            }
            if let nextPending {
                let movedDist = hypot(nextPending.x - point.x, nextPending.y - point.y)
                let stillInsideTarget = target?.regionRect.insetBy(dx: -4.0, dy: -4.0).contains(nextPending) ?? false
                if movedDist > 12.0 && !stillInsideTarget {
                    continue
                }
            }

            if Self.debugLoggingEnabled && target?.id != lastLoggedTargetID {
                lastLoggedTargetID = target?.id
                if let target {
                    fputs("[ApplePointer] AX hit target id=\(target.id) kind=\(target.kind) rect=\(target.rect) region=\(target.regionRect)\n", stderr)
                } else {
                    fputs("[ApplePointer] AX hit target cleared\n", stderr)
                }
                fflush(stderr)
            }
            onResult?(target)
        }
    }

    private func hitTest(point: CGPoint, isSystemIBeamActive: Bool) -> (HitTarget?, Bool) {
        // Never call AXUIElementCopyElementAtPosition over our own SwiftUI popover / status item:
        // macOS synchronously runs NSHostingView.hitTest on this background queue and traps MainActor.assumeIsolated.
        if isPointInOwnWindow(point) {
            return (nil, false)
        }

        if !isSystemIBeamActive, let stageCard = makeStageManagerCardTarget(at: point) {
            return (stageCard, false)
        }

        guard AXIsProcessTrusted() else {
            return (makeFallbackIBeamIfNeeded(at: point, active: isSystemIBeamActive), false)
        }

        var rawElement: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &rawElement)
        guard err == .success, let leaf = rawElement else {
            if !isSystemIBeamActive, let notchTarget = makeCameraNotchTarget(at: point) {
                return (notchTarget, false)
            }
            return (makeFallbackIBeamIfNeeded(at: point, active: isSystemIBeamActive), false)
        }

        var pid: pid_t = 0
        var isInsideNotificationCenter = false
        var isInsideCodex = false
        var isInsideWindowManager = false
        if AXUIElementGetPid(leaf, &pid) == .success {
            if pid == ownPID {
                return (nil, false)
            }
            enableManualAXIfNeeded(
                for: pid,
                encounteringRole: Self.stringAttribute(leaf, kAXRoleAttribute),
                encounteringSubrole: Self.stringAttribute(leaf, kAXSubroleAttribute)
            )
            isInsideNotificationCenter = isNotificationCenterProcess(pid)
            isInsideCodex = isCodexProcess(pid)
            isInsideWindowManager = isWindowManagerProcess(pid)
        }

        if !isSystemIBeamActive && isInsideWindowManager,
           let frame = Self.frameAttribute(leaf),
           frame.width >= 56.0 && frame.width <= 420.0,
           frame.height >= 44.0 && frame.height <= 420.0,
           let tiltY = inferredStageManagerTiltY(for: frame) {
            return (Self.buildStageManagerTarget(cardRect: frame, tiltY: tiltY), false)
        }

        // Stage 2: Collect ancestor chain UP (up to 12 levels) so we know container context
        // (e.g. inside AXToolbar / AXRadioGroup / AXDesktop) when shaping corner radii and slots.
        var candidate: AXUIElement? = leaf
        var chain: [(elem: AXUIElement, role: String, subrole: String)] = []
        var isInsideToolbar = false
        var isInsideDesktop = false

        let maxChainDepth = isInsideNotificationCenter ? 20 : 16
        for depth in 0...maxChainDepth {
            guard let elem = candidate else { break }
            let role = Self.stringAttribute(elem, kAXRoleAttribute) ?? ""
            let subrole = Self.stringAttribute(elem, kAXSubroleAttribute) ?? ""
            chain.append((elem, role, subrole))

            if role == "AXToolbar" || role == "AXRadioGroup" || role == "AXSegmentedControl" {
                isInsideToolbar = true
            }
            if subrole == "AXDesktop" {
                isInsideDesktop = true
            }
            if (role == "AXWebArea" || subrole == "AXEmptyGroup"), pid != 0 {
                enableManualAXIfNeeded(for: pid, encounteringRole: role, encounteringSubrole: subrole)
            }
            if depth < maxChainDepth && role != "AXWindow" && role != "AXApplication" {
                candidate = Self.parentAttribute(elem)
            } else {
                break
            }
        }

        var passiveFallbackTarget: HitTarget?
        var largeInteractiveFallbackTarget: HitTarget?

        for (idx, item) in chain.enumerated() {
            let elem = item.elem
            let role = item.role
            let subrole = item.subrole
            let directParent = (idx + 1 < chain.count) ? chain[idx + 1].elem : nil
            if Self.excludedNativeMenuContainerRoles.contains(role) {
                // If we hit AXMenu directly (e.g. separator or margin between items), do not snap the whole menu box
                continue
            }

            // When macOS already reports an I-beam cursor over text, only inspect text elements for line height
            // and vertical line center (exact Apple UIAxisVertical constrained beam), and never let an enclosing
            // clickable wrapper hijack the I-beam into a highlight rectangle.
            if isSystemIBeamActive {
                if Self.textInputRoles.contains(role) || role == "AXStaticText" {
                    if let beamTarget = Self.makeConstrainedTextBeamTarget(elem: elem, role: role, at: point, fallbackRect: Self.frameAttribute(elem)) {
                        return (beamTarget, false)
                    }
                }
            } else if Self.semanticInteractiveRoles.contains(role)
                        || Self.semanticInteractiveSubroles.contains(subrole)
                        || Self.dockSubroles.contains(subrole)
                        || Self.trafficLightSubroles.contains(subrole) {
                if let target = Self.evaluateElement(
                    elem,
                    at: point,
                    prefetchedRole: role,
                    prefetchedSubrole: subrole,
                    directParent: directParent,
                    isInsideToolbar: isInsideToolbar,
                    isInsideDesktop: isInsideDesktop,
                    isInsideNotificationCenter: isInsideNotificationCenter,
                    isInsideCodex: isInsideCodex,
                    allowExplicitPressFallback: false
                ) {
                    let isLargeCardTarget = target.id.hasPrefix("nc-")
                        || (isInsideNotificationCenter && max(target.rect.width, target.rect.height) > 84.0)
                        || (max(target.rect.width, target.rect.height) >= 110.0 && min(target.rect.width, target.rect.height) >= 44.0)
                    if isLargeCardTarget {
                        if largeInteractiveFallbackTarget == nil {
                            largeInteractiveFallbackTarget = target
                        }
                    } else {
                        return (target, false)
                    }
                }
            } else if passiveFallbackTarget == nil,
                      (Self.passiveOrWrapperRoles.contains(role) || isInsideNotificationCenter),
                      subrole != "AXEmptyGroup",
                      !subrole.hasPrefix("AXLandmark") {
                if let fallback = Self.evaluateElement(
                    elem,
                    at: point,
                    prefetchedRole: role,
                    prefetchedSubrole: subrole,
                    directParent: directParent,
                    isInsideToolbar: isInsideToolbar,
                    isInsideDesktop: isInsideDesktop,
                    isInsideNotificationCenter: isInsideNotificationCenter,
                    isInsideCodex: isInsideCodex,
                    allowExplicitPressFallback: true
                ) {
                    passiveFallbackTarget = fallback
                }
            }
        }

        if isSystemIBeamActive {
            if let rootContainer = Self.findDescentContainer(from: chain, at: point),
               let beam = Self.spatialDescendForTextBeam(from: rootContainer, at: point) {
                return (beam, false)
            }
            return (makeFallbackIBeamIfNeeded(at: point, active: true), false)
        }

        // Stage 3: Spatial tree descent DOWN for segmented toolbars, custom AppKit/SwiftUI views,
        // Electron/Chromium overlays, Notification Center banner close/action buttons,
        // or when the only hit so far is a large container/card.
        let fallbackCardTarget = largeInteractiveFallbackTarget ?? passiveFallbackTarget
        let isNotificationCard = fallbackCardTarget?.id.hasPrefix("nc-") ?? false
        let shouldPreferDescend = (fallbackCardTarget == nil)
            || (fallbackCardTarget.map { max($0.rect.width, $0.rect.height) > 84.0 } ?? false)
            || isNotificationCard
        if shouldPreferDescend, let rootContainer = Self.findDescentContainer(from: chain, at: point) {
            if let descended = Self.spatialDescend(
                from: rootContainer,
                at: point,
                initialInsideToolbar: isInsideToolbar,
                initialInsideDesktop: isInsideDesktop,
                isInsideNotificationCenter: isInsideNotificationCenter,
                isInsideCodex: isInsideCodex
            ) {
                if let card = fallbackCardTarget {
                    let descArea = descended.rect.width * descended.rect.height
                    let cardArea = card.rect.width * card.rect.height
                    if descArea < cardArea * 0.85 || !descended.id.hasPrefix("nc-") {
                        return (descended, false)
                    }
                } else {
                    return (descended, false)
                }
            }
        }

        if let largeInteractiveFallbackTarget {
            return (largeInteractiveFallbackTarget, false)
        }

        if let passiveFallbackTarget {
            return (passiveFallbackTarget, false)
        }

        // Stage 3a: Dynamic 3D scene pieces (e.g. Burette Mol* hovered atoms/residues/ligands/waters)
        let (burette3DTarget, isDynamic3DViewport) = Self.makeBurette3DTarget(from: chain, at: point)
        if let burette3DTarget {
            return (burette3DTarget, true)
        }

        // Stage 3b: Web / Electron scrollable container edge scrollbar (Chromium exposes CSS overflow scrollbars
        // on the container AXGroup via AXDOMClassList rather than a separate AXScrollBar node).
        for item in chain {
            if let f = Self.frameAttribute(item.elem),
               let sb = Self.makeWebScrollbarTargetIfEdge(item.elem, role: item.role, frame: f, at: point) {
                return (sb, isDynamic3DViewport)
            }
        }

        // Stage 4: Hardware camera notch magnetic target (e.g. bare MacBook notch or collapsed notch utility).
        if !isSystemIBeamActive, let notchTarget = makeCameraNotchTarget(at: point) {
            return (notchTarget, false)
        }

        return (nil, isDynamic3DViewport)
    }

    private static func makeBurette3DTarget(
        from chain: [(elem: AXUIElement, role: String, subrole: String)],
        at point: CGPoint
    ) -> (HitTarget?, Bool) {
        var sawMolstarViewport = false
        for item in chain {
            guard item.role == "AXGroup" || item.role == "AXWebArea" || item.role == "AXGenericElement" || item.role == "AXUnknown" else {
                continue
            }
            let classes = stringArrayAttribute(item.elem, "AXDOMClassList")
            guard !classes.isEmpty else { continue }
            if !sawMolstarViewport && classes.contains(where: { $0 == "msp-viewport" || $0 == "msp-layout-main" || $0 == "msp-plugin" }) {
                sawMolstarViewport = true
            }
            if let token = classes.first(where: { Burette3DTargetParser.isToken($0) }),
               let hostFrame = frameAttribute(item.elem),
               let target = Burette3DTargetParser.parse(token: token, hostFrame: hostFrame, point: point) {
                return (target, true)
            }
        }
        return (nil, sawMolstarViewport)
    }

    private func makeFallbackIBeamIfNeeded(at point: CGPoint, active: Bool) -> HitTarget? {
        guard active else { return nil }
        return HitTarget(
            id: "system-ibeam",
            rect: CGRect(x: point.x - 1.5, y: point.y - 12.0, width: ApplePointerConstants.Geometry.beamWidth, height: ApplePointerConstants.Geometry.beamMinLength),
            cornerRadius: ApplePointerConstants.Geometry.beamWidth * 0.5,
            kind: .beam,
            slipX: ApplePointerConstants.Effect.beamSlipX,
            slipY: ApplePointerConstants.Effect.beamSlipY,
            maxSlipPoints: .greatestFiniteMagnitude,
            overlayEffectStyle: .none
        )
    }

    private func enableManualAXIfNeeded(for pid: pid_t, encounteringRole role: String?, encounteringSubrole subrole: String? = nil) {
        lock.lock()
        let alreadyConfigured = configuredManualAXPIDs.contains(pid)
        lock.unlock()
        if alreadyConfigured { return }

        var shouldEnable = (role == "AXWebArea" || subrole == "AXEmptyGroup")
        if !shouldEnable, let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier {
            shouldEnable = Self.chromiumBundlePrefixes.contains { bundleID.hasPrefix($0) }
        }
        guard shouldEnable else { return }

        lock.lock()
        let inserted = configuredManualAXPIDs.insert(pid).inserted
        lock.unlock()
        guard inserted else { return }

        let appElem = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElem, 0.05)
        _ = AXUIElementSetAttributeValue(appElem, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private func isNotificationCenterProcess(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        lock.lock()
        if let cached = notificationCenterPIDCache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let isNC = bid == "com.apple.notificationcenterui"
            || bid == "com.apple.UserNotificationCenter"
            || bid.hasPrefix("com.apple.notificationcenter")
        lock.lock()
        if notificationCenterPIDCache.count > 64 {
            notificationCenterPIDCache.removeAll(keepingCapacity: true)
        }
        notificationCenterPIDCache[pid] = isNC
        lock.unlock()
        return isNC
    }

    private func isCodexProcess(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        lock.lock()
        if let cached = codexPIDCache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let isCodex = bid == "com.openai.codex" || bid.hasPrefix("com.openai.codex.")
        lock.lock()
        if codexPIDCache.count > 64 {
            codexPIDCache.removeAll(keepingCapacity: true)
        }
        codexPIDCache[pid] = isCodex
        lock.unlock()
        return isCodex
    }

    private func isWindowManagerProcess(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        lock.lock()
        if let cached = windowManagerPIDCache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let isWM = bid == "com.apple.WindowManager"
        lock.lock()
        if windowManagerPIDCache.count > 64 {
            windowManagerPIDCache.removeAll(keepingCapacity: true)
        }
        windowManagerPIDCache[pid] = isWM
        lock.unlock()
        return isWM
    }

    private static func findDescentContainer(
        from chain: [(elem: AXUIElement, role: String, subrole: String)],
        at point: CGPoint
    ) -> AXUIElement? {
        // 1. Prefer the tightest local container (AXRadioGroup, AXSegmentedControl, AXToolbar, AXTabGroup, AXGroup)
        // that contains `point` and actually has children so we find toolbar/segmented icons in 1-2 hops
        // instead of crawling the entire AXWindow.
        for item in chain.prefix(6) {
            if item.role == "AXRadioGroup"
                || item.role == "AXSegmentedControl"
                || item.role == "AXToolbar"
                || item.role == "AXTabGroup"
                || item.role == "AXPopover"
                || item.role == "AXSheet" {
                if let rect = frameAttribute(item.elem),
                   rect.insetBy(dx: -2.0, dy: -2.0).contains(point),
                   !visibleOrAllChildren(item.elem).isEmpty {
                    return item.elem
                }
            }
        }

        var looksLikeOverlayContainer = false
        for item in chain.prefix(6) {
            if item.subrole == "AXEmptyGroup" || item.role == "AXWebArea" {
                looksLikeOverlayContainer = true
                break
            }
            if containerRoles.contains(item.role),
               let rect = frameAttribute(item.elem),
               max(rect.width, rect.height) > 64.0,
               rect.insetBy(dx: -2.0, dy: -2.0).contains(point) {
                looksLikeOverlayContainer = true
                break
            }
        }
        guard looksLikeOverlayContainer else { return nil }

        // 2. Prefer nearest non-empty AXGroup/AXList/AXOutline or AXWebArea in ancestor chain
        for item in chain {
            if item.role == "AXWebArea" {
                return item.elem
            }
            if (item.role == "AXGroup" || item.role == "AXList" || item.role == "AXOutline" || item.role == "AXTable" || item.role == "AXBrowser" || item.role == "AXGrid" || item.role == "AXLayoutArea"),
               item.subrole != "AXEmptyGroup",
               let rect = frameAttribute(item.elem),
               rect.insetBy(dx: -2.0, dy: -2.0).contains(point),
               !visibleOrAllChildren(item.elem).isEmpty {
                return item.elem
            }
        }
        var cur: AXUIElement? = chain.last?.elem
        for _ in 0..<6 {
            guard let elem = cur else { break }
            let role = stringAttribute(elem, kAXRoleAttribute) ?? ""
            if role == "AXWebArea" || role == "AXWindow" {
                return elem
            }
            cur = parentAttribute(elem)
        }
        return chain.last?.elem
    }

    /// Cheap 5-attribute geometry pre-check: avoids serializing kAXChildrenAttribute across XPC
    /// for hundreds of off-point sibling rows/messages so deep Electron/Web/SwiftUI trees (depth 30-50)
    /// stay fast and never exhaust the visit budget before reaching the hovered control.
    private static let spatialGeometryAttributeNames: [String] = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute,
        kAXEnabledAttribute
    ]

    private struct LightNodeGeometry {
        let role: String
        let subrole: String
        let frame: CGRect?
        let enabled: Bool?
    }

    private static func readLightNodeGeometry(_ elem: AXUIElement) -> LightNodeGeometry? {
        var rawValues: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(elem, spatialGeometryAttributeNames as CFArray, [], &rawValues)
        guard err == .success, let arr = rawValues as? [AnyObject], arr.count == 5 else {
            return nil
        }
        let role = arr[0] as? String ?? ""
        let subrole = arr[1] as? String ?? ""
        var frame: CGRect?
        if CFGetTypeID(arr[2]) == AXValueGetTypeID(), CFGetTypeID(arr[3]) == AXValueGetTypeID() {
            let posAX = unsafeDowncast(arr[2], to: AXValue.self)
            let sizeAX = unsafeDowncast(arr[3], to: AXValue.self)
            if AXValueGetType(posAX) == .cgPoint && AXValueGetType(sizeAX) == .cgSize {
                var pt = CGPoint.zero
                var sz = CGSize.zero
                if AXValueGetValue(posAX, .cgPoint, &pt), AXValueGetValue(sizeAX, .cgSize, &sz) {
                    frame = CGRect(origin: pt, size: sz)
                }
            }
        }
        let enabled = (arr[4] as? NSNumber)?.boolValue
        return LightNodeGeometry(role: role, subrole: subrole, frame: frame, enabled: enabled)
    }

    private static func spatialDescend(
        from root: AXUIElement,
        at point: CGPoint,
        initialInsideToolbar: Bool,
        initialInsideDesktop: Bool,
        isInsideNotificationCenter: Bool = false,
        isInsideCodex: Bool = false
    ) -> HitTarget? {
        let startTime = CACurrentMediaTime()
        let maxChecked = 1200
        let maxExpanded = 180
        let maxDepth = 52
        let timeBudget: CFTimeInterval = 0.032
        var checked = 0
        var expanded = 0

        var bestTarget: HitTarget?
        var bestArea: CGFloat = .greatestFiniteMagnitude
        var bestIsSemantic = false
        var fallbackScrollbarTarget: HitTarget?
        var bestScrollbarArea: CGFloat = .greatestFiniteMagnitude

        func dfs(_ elem: AXUIElement, parent: AXUIElement?, depth: Int, clipRect: CGRect?, inToolbar: Bool, inDesktop: Bool) {
            if checked >= maxChecked || expanded >= maxExpanded || depth > maxDepth || (CACurrentMediaTime() - startTime) > timeBudget {
                return
            }
            checked += 1

            let info = readLightNodeGeometry(elem)
            let role = info?.role ?? (stringAttribute(elem, kAXRoleAttribute) ?? "")
            let subrole = info?.subrole ?? (stringAttribute(elem, kAXSubroleAttribute) ?? "")
            let frame = info?.frame ?? frameAttribute(elem)
            let nextInToolbar = inToolbar || role == "AXToolbar" || role == "AXRadioGroup" || role == "AXSegmentedControl"
            let nextInDesktop = inDesktop || subrole == "AXDesktop"

            var nextClip = clipRect
            var hasValidFrame = false
            if let frame {
                if frame.width > 0 && frame.height > 0 && frame.width.isFinite && frame.height.isFinite {
                    hasValidFrame = true
                    let hitPad: CGFloat = isInsideNotificationCenter ? 18.0 : 3.0
                    if !frame.insetBy(dx: -hitPad, dy: -hitPad).contains(point) {
                        return
                    }
                    if !isInsideNotificationCenter && (role == "AXScrollArea" || role == "AXWindow" || role == "AXWebArea") {
                        nextClip = clipRect.map { $0.intersection(frame) } ?? frame
                        if let c = nextClip, (c.isNull || !c.insetBy(dx: -3.0, dy: -3.0).contains(point)) {
                            return
                        }
                    }
                } else if role != "AXGroup" && role != "AXGenericElement" && role != "AXUnknown" && role != "AXWebArea" {
                    // Allow 0x0 CSS display:contents / floating portal wrappers to still descend into children,
                    // while pruning genuinely invisible 0x0 leaves.
                    return
                }
            }
            if role == "AXPopover" || role == "AXSheet" || subrole == "AXApplicationDialog" {
                nextClip = nil
            }

            let isSemantic = semanticInteractiveRoles.contains(role)
                || semanticInteractiveSubroles.contains(subrole)
                || dockSubroles.contains(subrole)
                || trafficLightSubroles.contains(subrole)
            let isCandidatePassive = !isSemantic
                && passiveOrWrapperRoles.contains(role)
                && !pureTextRoles.contains(role)
                && subrole != "AXEmptyGroup"
                && !subrole.hasPrefix("AXLandmark")

            if (isSemantic || isCandidatePassive), !excludedNativeMenuContainerRoles.contains(role), hasValidFrame, let frame {
                let clipped = nextClip.map { frame.intersection($0) } ?? frame
                let passiveFitsControlOrRow = !isCandidatePassive
                    || (clipped.width <= 360.0 && clipped.height <= 280.0)
                    || (clipped.width <= 460.0 && clipped.height >= 16.0 && clipped.height <= 72.0)
                    || (isInsideNotificationCenter && clipped.width <= 480.0 && clipped.height <= 440.0)
                if !clipped.isNull,
                   clipped.width > 4.0,
                   clipped.height > 4.0,
                   clipped.insetBy(dx: -2.0, dy: -2.0).contains(point),
                   passiveFitsControlOrRow,
                   let candidate = evaluateElement(
                       elem,
                       at: point,
                       overrideRect: clipped,
                       prefetchedRole: role,
                       prefetchedSubrole: subrole,
                       prefetchedEnabled: info?.enabled,
                       directParent: parent,
                       isInsideToolbar: nextInToolbar,
                       isInsideDesktop: nextInDesktop,
                       isInsideNotificationCenter: isInsideNotificationCenter,
                       isInsideCodex: isInsideCodex,
                       allowExplicitPressFallback: isCandidatePassive
                   ) {
                    // Never let a passive child wrapper inside an AXTextArea/AXTextField overwrite an active .beam target
                    if !(bestTarget?.kind == .beam && isCandidatePassive) {
                        let area = candidate.rect.width * candidate.rect.height
                        let strictlySmaller = area < bestArea * 0.96
                        let semanticBeatsSameSizePassive = isSemantic && !bestIsSemantic && area <= bestArea * 1.04
                        if strictlySmaller || semanticBeatsSameSizePassive || (candidate.kind == .beam && bestTarget == nil) {
                            bestArea = area
                            bestTarget = candidate
                            bestIsSemantic = isSemantic
                        }
                    }
                    // Do not descend into inner AXStaticText / wrapper nodes inside a resolved text input (.beam)
                    if candidate.kind == .beam {
                        return
                    }
                }
            }

            if bestTarget == nil, hasValidFrame, let frame {
                let clipped = nextClip.map { frame.intersection($0) } ?? frame
                if !clipped.isNull,
                   let sb = makeWebScrollbarTargetIfEdge(elem, role: role, frame: clipped, at: point) {
                    let sbArea = clipped.width * clipped.height
                    if sbArea < bestScrollbarArea {
                        bestScrollbarArea = sbArea
                        fallbackScrollbarTarget = sb
                    }
                }
            }

            expanded += 1
            let children = visibleOrAllChildren(elem)
            for child in children {
                if checked >= maxChecked || expanded >= maxExpanded || (CACurrentMediaTime() - startTime) > timeBudget {
                    break
                }
                dfs(child, parent: elem, depth: depth + 1, clipRect: nextClip, inToolbar: nextInToolbar, inDesktop: nextInDesktop)
            }
        }

        dfs(root, parent: parentAttribute(root), depth: 0, clipRect: isInsideNotificationCenter ? nil : frameAttribute(root), inToolbar: initialInsideToolbar, inDesktop: initialInsideDesktop)
        return bestTarget ?? fallbackScrollbarTarget
    }

    /// Fast pruned descent used when macOS already reports an I-beam cursor over Electron/Chromium/WebKit
    /// overlays (e.g. Codex, Chrome, Slack, VS Code) so we reach deep AXStaticText/AXTextArea nodes (depth 30+)
    /// and lock the iPadOS vertical beam to exact line centers for crisp line-to-line & chunk-to-chunk spring jumps.
    private static func spatialDescendForTextBeam(
        from root: AXUIElement,
        at point: CGPoint
    ) -> HitTarget? {
        let startTime = CACurrentMediaTime()
        let maxVisited = 220
        let maxDepth = 42
        let timeBudget: CFTimeInterval = 0.018
        var visited = 0
        var bestBeam: HitTarget?
        var bestHeightDiff: CGFloat = .greatestFiniteMagnitude

        func dfs(_ elem: AXUIElement, depth: Int) {
            if visited >= maxVisited || depth > maxDepth || (CACurrentMediaTime() - startTime) > timeBudget {
                return
            }
            visited += 1

            let info = readLightNodeGeometry(elem)
            let role = info?.role ?? (stringAttribute(elem, kAXRoleAttribute) ?? "")
            let frame = info?.frame ?? frameAttribute(elem)

            if let frame, frame.width > 0, frame.height > 0, frame.width.isFinite, frame.height.isFinite {
                if !frame.insetBy(dx: -4.0, dy: -4.0).contains(point) {
                    return
                }
            }

            if role == "AXStaticText" || textInputRoles.contains(role) {
                if let candidate = makeConstrainedTextBeamTarget(elem: elem, role: role, at: point, fallbackRect: frame),
                   candidate.slipY < 1.0 {
                    let dy = abs(point.y - candidate.rect.midY)
                    if dy < bestHeightDiff {
                        bestHeightDiff = dy
                        bestBeam = candidate
                        if dy <= 2.0 { return }
                    }
                }
            }

            let children = visibleOrAllChildren(elem)
            for child in children {
                if visited >= maxVisited || (CACurrentMediaTime() - startTime) > timeBudget {
                    break
                }
                dfs(child, depth: depth + 1)
            }
        }

        dfs(root, depth: 0)
        return bestBeam
    }

    private static func evaluateElement(
        _ elem: AXUIElement,
        at point: CGPoint,
        overrideRect: CGRect? = nil,
        prefetchedRole: String? = nil,
        prefetchedSubrole: String? = nil,
        prefetchedEnabled: Bool? = nil,
        directParent: AXUIElement? = nil,
        isInsideToolbar: Bool = false,
        isInsideDesktop: Bool = false,
        isInsideNotificationCenter: Bool = false,
        isInsideCodex: Bool = false,
        allowExplicitPressFallback: Bool
    ) -> HitTarget? {
        if let enabled = prefetchedEnabled ?? boolAttribute(elem, kAXEnabledAttribute), !enabled {
            return nil
        }

        let role = prefetchedRole ?? (stringAttribute(elem, kAXRoleAttribute) ?? "")
        let subrole = prefetchedSubrole ?? (stringAttribute(elem, kAXSubroleAttribute) ?? "")
        guard let rect = overrideRect ?? frameAttribute(elem) else { return nil }
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else { return nil }

        if !rect.insetBy(dx: -2.0, dy: -2.0).contains(point) {
            return nil
        }

        // 1. Text inputs -> I-beam (including Electron/Chromium contenteditable AXGroup/AXGenericElement)
        let isEditableContainer = (role == "AXGroup" || role == "AXGenericElement" || role == "AXWebArea")
            && (subrole == "AXTextArea" || subrole == "AXSecureTextField" || subrole == "AXSearchField" || boolAttribute(elem, "AXEditable") == true)
        if textInputRoles.contains(role) || isEditableContainer {
            if let constrained = makeConstrainedTextBeamTarget(elem: elem, role: role, at: point, fallbackRect: rect) {
                return constrained
            }
            let clampedH = ApplePointerConstants.Geometry.beamMinLength
            return HitTarget(
                id: "\(role)-\(Int(rect.minX))-\(Int(rect.minY))",
                rect: CGRect(x: point.x - 1.5, y: point.y - clampedH * 0.5, width: ApplePointerConstants.Geometry.beamWidth, height: clampedH),
                regionRect: rect,
                cornerRadius: ApplePointerConstants.Geometry.beamWidth * 0.5,
                kind: .beam,
                slipX: ApplePointerConstants.Effect.beamSlipX,
                slipY: ApplePointerConstants.Effect.beamSlipY,
                maxSlipPoints: .greatestFiniteMagnitude,
                overlayEffectStyle: .none
            )
        }

        // 2. Dock items -> Lift effect fitted tightly to the visible macOS squircle icon
        if role == "AXDockItem" || dockSubroles.contains(subrole) {
            if subrole == "AXSeparatorDockItem" {
                return nil
            }
            let tileSize = min(rect.width, rect.height)
            // macOS app icons sit on Apple's 824/1024 (~80.5%) squircle grid inside the AXDockItem slot.
            // On macOS 26/27 floating glass Dock, the visible icon is centered directly at (rect.midX, rect.midY).
            let visibleSide = tileSize * 0.81
            let centerX = rect.midX
            let centerY = rect.midY
            let iconSquare = CGRect(
                x: centerX - visibleSide * 0.5,
                y: centerY - visibleSide * 0.5,
                width: visibleSide,
                height: visibleSide
            )
            return HitTarget(
                id: "dock-\(subrole)-\(Int(rect.minX))-\(Int(rect.minY))",
                rect: iconSquare,
                regionRect: rect,
                cornerRadius: visibleSide * 0.225,
                kind: .lift,
                slipX: ApplePointerConstants.Effect.liftSlipX,
                slipY: ApplePointerConstants.Effect.liftSlipY,
                maxSlipPoints: ApplePointerConstants.Effect.liftMaxSlipPoints,
                overrideSlipPoints: CGPoint(
                    x: 3.5,
                    y: 3.5
                ),
                scaleUpPoints: 2.0,
                horizontalPadding: 0.0,
                verticalPadding: 0.0,
                overlayEffectStyle: .prominent
            )
        }

        // 3. Window traffic lights
        if trafficLightSubroles.contains(subrole) {
            return HitTarget(
                id: "traffic-\(subrole)-\(Int(rect.minX))-\(Int(rect.minY))",
                rect: rect,
                regionRect: rect,
                cornerRadius: min(rect.width, rect.height) * 0.5,
                kind: .highlight,
                slipX: ApplePointerConstants.Effect.highlightSlipX,
                slipY: ApplePointerConstants.Effect.highlightSlipY,
                maxSlipPoints: ApplePointerConstants.Effect.highlightMaxSlipPoints,
                horizontalPadding: 2.0,
                verticalPadding: 2.0,
                overlayEffectStyle: .standard
            )
        }

        // 4. Menu bar items (tight slip so highlight stays neatly inside the top menu bar)
        if role == "AXMenuBarItem" || role == "AXMenuExtra" {
            return HitTarget(
                id: "menubar-\(Int(rect.minX))-\(Int(rect.minY))",
                rect: rect,
                regionRect: rect,
                cornerRadius: min(rect.height * 0.5, 8.0),
                kind: .highlight,
                slipX: ApplePointerConstants.Effect.highlightSlipX,
                slipY: ApplePointerConstants.Effect.highlightSlipY,
                maxSlipPoints: 2.5,
                horizontalPadding: 0.0,
                verticalPadding: 0.0,
                overlayEffectStyle: .standard
            )
        }

        // 5. Native context & dropdown menu items: dissolve Dot cleanly into the row with zero edge overflow
        if role == "AXMenuItem" {
            guard rect.height >= 14.0 && rect.height <= 54.0 && rect.width >= 32.0 else {
                return nil
            }
            return HitTarget(
                id: "menuitem-\(Int(rect.minX))-\(Int(rect.minY))-\(Int(rect.width))x\(Int(rect.height))",
                rect: rect,
                regionRect: rect,
                cornerRadius: min(rect.height * 0.5, 8.0),
                kind: .menuItem,
                slipX: 0.0,
                slipY: 0.0,
                maxSlipPoints: 0.0,
                horizontalPadding: 0.0,
                verticalPadding: 0.0,
                overlayEffectStyle: .standard
            )
        }

        if excludedNativeMenuContainerRoles.contains(role) {
            return nil
        }

        // 6. Desktop / Finder / app icons & clickable media thumbnails (AXImage or AXLayoutItem)
        if (role == "AXImage" || role == "AXLayoutItem") && rect.width >= 20.0 && rect.height >= 20.0 && rect.width <= 260.0 && rect.height <= 260.0 {
            let actions = actionNames(elem)
            let hasIconAction = actions.contains("AXOpen")
                || actions.contains(kAXPressAction as String)
                || actions.contains(kAXPickAction as String)
                || actions.contains(kAXConfirmAction as String)
            let isSelectableIcon = isInsideDesktop || (role == "AXLayoutItem" && isAttributeSettable(elem, kAXSelectedAttribute))
            if hasIconAction || (isSelectableIcon && hasAccessibilityLabel(elem)) {
                let minDim = min(rect.width, rect.height)
                return HitTarget(
                    id: "desktopicon-\(Int(rect.minX))-\(Int(rect.minY))-\(Int(rect.width))x\(Int(rect.height))",
                    rect: rect,
                    regionRect: rect,
                    cornerRadius: isInsideDesktop ? minDim * 0.2237 : min(minDim * 0.22, 14.0),
                    kind: (isInsideDesktop || max(rect.width, rect.height) <= 116.0) ? .lift : .highlight,
                    slipX: ApplePointerConstants.Effect.liftSlipX,
                    slipY: ApplePointerConstants.Effect.liftSlipY,
                    maxSlipPoints: 4.5,
                    overrideSlipPoints: CGPoint(x: 3.5, y: 3.5),
                    scaleUpPoints: isInsideDesktop ? 5.0 : 3.0,
                    horizontalPadding: 2.0,
                    verticalPadding: 2.0,
                    overlayEffectStyle: .prominent
                )
            }
        }

        // 6b. macOS Desktop Widgets & Notification Center banners/cards (com.apple.notificationcenterui)
        if isInsideNotificationCenter {
            // Skip thin decorative accent bars inside widgets (e.g. Calendar event stripes with no actions)
            if role == "AXButton" && min(rect.width, rect.height) < 12.0 && actionNames(elem).isEmpty {
                return nil
            }
            let axID = stringAttribute(elem, kAXIdentifierAttribute) ?? ""
            if role == "AXGroup"
                && axID.hasPrefix("widget-")
                && rect.width >= 120.0 && rect.width <= 440.0
                && rect.height >= 120.0 && rect.height <= 440.0 {
                let minDim = min(rect.width, rect.height)
                return HitTarget(
                    id: "nc-widget-\(Int(rect.minX))-\(Int(rect.minY))-\(Int(rect.width))x\(Int(rect.height))",
                    rect: rect,
                    regionRect: rect,
                    cornerRadius: min(minDim * 0.16, 26.0),
                    kind: .highlight,
                    slipX: 0.032,
                    slipY: 0.032,
                    maxSlipPoints: 5.0,
                    horizontalPadding: 0.0,
                    verticalPadding: 0.0,
                    overlayEffectStyle: .standard
                )
            }
            let isBannerSubrole = subrole.hasPrefix("AXNotificationCenter")
                || subrole == "AXNotificationListItems"
            let hasBannerID = axID.localizedCaseInsensitiveContains("banner")
                || axID.localizedCaseInsensitiveContains("notification")
                || axID.localizedCaseInsensitiveContains("alert")
            let isNotificationCardSize = rect.width >= 200.0 && rect.width <= 480.0
                && rect.height >= 40.0 && rect.height <= 340.0
            let isNotificationCard = isNotificationCardSize
                && !axID.hasPrefix("widget-")
                && (
                    isBannerSubrole
                    || hasBannerID
                    || role == "AXButton"
                    || ((role == "AXGroup" || role == "AXScrollArea") && subrole != "AXHostingView" && (!actionNames(elem).isEmpty || hasAccessibilityLabel(elem) || rect.height <= 260.0))
                    || (role == "AXWindow" && rect.height <= 260.0)
                )
            if isNotificationCard {
                let minDim = min(rect.width, rect.height)
                return HitTarget(
                    id: "nc-banner-\(Int(rect.minX))-\(Int(rect.minY))-\(Int(rect.width))x\(Int(rect.height))",
                    rect: rect,
                    regionRect: rect,
                    cornerRadius: min(minDim * 0.24, 18.0),
                    kind: .highlight,
                    slipX: 0.032,
                    slipY: 0.032,
                    maxSlipPoints: 5.0,
                    horizontalPadding: 0.0,
                    verticalPadding: 0.0,
                    overlayEffectStyle: .standard
                )
            }
        }

        // 7. Links
        if role == "AXLink" {
            guard ElementGeometryResolver.isControlSizeEligible(
                size: rect.size,
                role: role,
                subrole: subrole,
                isExplicitControl: true,
                isInsideToolbar: isInsideToolbar,
                isSidebarRow: false
            ) else {
                return nil
            }
            let hPad: CGFloat = rect.height <= 24.0 ? 5.0 : 0.0
            let vPad: CGFloat = rect.height <= 24.0 ? 2.5 : 0.0
            let tightMaxSlip = min(6.0, max(2.5, min(rect.width, rect.height) * 0.22))
            let linkDomRadius = Self.resolvedDomCornerRadius(for: elem, visualRect: rect, parent: directParent)
            let linkCornerRadius = ElementGeometryResolver.resolveCornerRadius(
                visualRect: rect,
                role: role,
                subrole: subrole,
                isInsideToolbar: isInsideToolbar,
                isSidebarRow: false,
                isCircularCloseOrDelete: false,
                isNotchButton: false,
                domRadius: linkDomRadius
            )
            return HitTarget(
                id: "AXLink-\(Int(rect.minX))-\(Int(rect.minY))-\(Int(rect.width))x\(Int(rect.height))",
                rect: rect,
                regionRect: rect,
                cornerRadius: linkCornerRadius,
                kind: .highlight,
                slipX: ApplePointerConstants.Effect.highlightSlipX,
                slipY: ApplePointerConstants.Effect.highlightSlipY,
                maxSlipPoints: tightMaxSlip,
                horizontalPadding: hPad,
                verticalPadding: vPad,
                overlayEffectStyle: .standard
            )
        }

        // 7b. Sliders -> snap onto the knob/thumb with Apple UIPointerAccessory directional arrows
        if role == "AXSlider" {
            let orientation = stringAttribute(elem, kAXOrientationAttribute) ?? ""
            let isVertical = orientation == "AXVerticalOrientation" || rect.height > rect.width * 1.4
            var thumbRect: CGRect?
            for child in visibleOrAllChildren(elem) {
                let childRole = stringAttribute(child, kAXRoleAttribute) ?? ""
                if childRole == "AXValueIndicator", let f = frameAttribute(child), f.width >= 6.0, f.height >= 6.0 {
                    thumbRect = f
                    break
                }
            }
            let knobRect: CGRect
            if let thumbRect {
                knobRect = thumbRect
            } else {
                let val = doubleAttribute(elem, kAXValueAttribute)
                let minVal = doubleAttribute(elem, kAXMinValueAttribute) ?? 0.0
                let maxVal = doubleAttribute(elem, kAXMaxValueAttribute) ?? 1.0
                let frac: CGFloat
                if let val, maxVal > minVal {
                    frac = CGFloat(max(0.0, min(1.0, (val - minVal) / (maxVal - minVal))))
                } else {
                    frac = isVertical
                        ? max(0.0, min(1.0, (point.y - rect.minY) / max(rect.height, 1.0)))
                        : max(0.0, min(1.0, (point.x - rect.minX) / max(rect.width, 1.0)))
                }
                let knobSide = max(16.0, min(26.0, min(rect.width, rect.height) + 2.0))
                if isVertical {
                    let cy = rect.maxY - knobSide * 0.5 - frac * max(0.0, rect.height - knobSide)
                    knobRect = CGRect(x: rect.midX - knobSide * 0.5, y: cy - knobSide * 0.5, width: knobSide, height: knobSide)
                } else {
                    let cx = rect.minX + knobSide * 0.5 + frac * max(0.0, rect.width - knobSide)
                    knobRect = CGRect(x: cx - knobSide * 0.5, y: rect.midY - knobSide * 0.5, width: knobSide, height: knobSide)
                }
            }
            let knobRegion = knobRect.insetBy(dx: -8.0, dy: -8.0)
            if knobRegion.contains(point) {
                return HitTarget(
                    id: "slider-\(Int(rect.minX))-\(Int(rect.minY))-\(Int(knobRect.midX))",
                    rect: knobRect,
                    regionRect: knobRegion,
                    cornerRadius: min(knobRect.width, knobRect.height) * 0.5,
                    kind: .highlight,
                    slipX: isVertical ? 0.06 : 0.14,
                    slipY: isVertical ? 0.14 : 0.06,
                    maxSlipPoints: 4.0,
                    horizontalPadding: 2.0,
                    verticalPadding: 2.0,
                    overlayEffectStyle: .standard,
                    accessoryKind: isVertical ? .verticalArrows : .horizontalArrows
                )
            }
            return nil
        }

        // 7c. Scrollbars -> Apple _UIPointerScrollIndicatorEffect thin capsule locked to scrollbar minor axis
        if role == "AXScrollBar" {
            let orientation = stringAttribute(elem, kAXOrientationAttribute) ?? ""
            let isVertical = orientation == "AXVerticalOrientation" || rect.height >= rect.width
            var thumbRect: CGRect?
            for child in visibleOrAllChildren(elem) {
                let childRole = stringAttribute(child, kAXRoleAttribute) ?? ""
                if childRole == "AXValueIndicator", let f = frameAttribute(child), f.width >= 4.0, f.height >= 4.0 {
                    thumbRect = f
                    break
                }
            }
            let capsule: CGRect
            if let thumbRect, thumbRect.insetBy(dx: -6.0, dy: -6.0).contains(point) {
                capsule = thumbRect
            } else if isVertical {
                let w = max(8.0, min(14.0, rect.width - 2.0))
                let h = min(64.0, max(28.0, rect.height * 0.18))
                let cy = max(rect.minY + h * 0.5, min(rect.maxY - h * 0.5, point.y))
                capsule = CGRect(x: rect.midX - w * 0.5, y: cy - h * 0.5, width: w, height: h)
            } else {
                let h = max(8.0, min(14.0, rect.height - 2.0))
                let w = min(64.0, max(28.0, rect.width * 0.18))
                let cx = max(rect.minX + w * 0.5, min(rect.maxX - w * 0.5, point.x))
                capsule = CGRect(x: cx - w * 0.5, y: rect.midY - h * 0.5, width: w, height: h)
            }
            return HitTarget(
                id: "scrollbar-\(Int(rect.minX))-\(Int(rect.minY))-\(isVertical ? "v" : "h")",
                rect: capsule,
                regionRect: rect,
                cornerRadius: min(capsule.width, capsule.height) * 0.5,
                kind: .scrollThumb,
                slipX: isVertical ? 0.08 : 1.0,
                slipY: isVertical ? 1.0 : 0.08,
                maxSlipPoints: 2.5,
                overlayEffectStyle: .standard
            )
        }

        // 8. Standard semantic controls (or custom clickable toolbar / segmented icon buttons)
        let isSemantic = semanticInteractiveRoles.contains(role) || semanticInteractiveSubroles.contains(subrole)
        var isExplicitControl = isSemantic
        if !isExplicitControl && allowExplicitPressFallback {
            // Never turn raw text nodes (AXStaticText/AXHeading/AXListMarker) into button highlight blocks
            // even when Electron/Chromium propagates AXPress onto selectable or annotatable text.
            if pureTextRoles.contains(role) {
                return nil
            }
            let actions = actionNames(elem)
            let hasPrimaryInteractiveAction = actions.contains(kAXPressAction as String)
                || actions.contains(kAXConfirmAction as String)
                || actions.contains(kAXPickAction as String)
                || actions.contains("AXOpen")
                || actions.contains(kAXIncrementAction as String)
                || actions.contains(kAXDecrementAction as String)
            let isSelectableNativeRow = (role == "AXRow" || role == "AXOutlineRow" || role == "AXCell" || subrole == "AXOutlineRow" || subrole == "AXTableRow")
                && rect.width >= 32.0 && rect.width <= 460.0
                && rect.height >= 16.0 && rect.height <= 72.0
                && isAttributeSettable(elem, kAXSelectedAttribute)
            if hasPrimaryInteractiveAction || isSelectableNativeRow {
                let isClickableRowOrButton =
                    isSelectableNativeRow
                    || (role == "AXRow" || role == "AXOutlineRow" || role == "AXCell" || subrole == "AXApplicationGroup" || subrole == "AXOutlineRow" || subrole == "AXTableRow")
                    || (rect.width <= 360.0 && rect.height >= 18.0 && rect.height <= 280.0 && (hasInteractiveStylingHint(elem) || hasAccessibilityLabel(elem)))
                if containsTextInput(elem) {
                    return nil
                }
                if !isInsideToolbar && !isInsideNotificationCenter && !isClickableRowOrButton && containsPureTextOnly(elem) {
                    return nil
                }
                isExplicitControl = true
            } else if isInsideToolbar
                        && min(rect.width, rect.height) >= 14.0
                        && max(rect.width, rect.height) <= 56.0
                        && hasAccessibilityLabel(elem) {
                // Custom AppKit/SwiftUI segmented toolbar icon views (e.g. CleanShot X tool palette)
                isExplicitControl = true
            }
        }
        guard isExplicitControl else {
            return nil
        }

        let isApplicationGroupRow = ((role == "AXGroup" && subrole == "AXApplicationGroup") || role == "AXRow" || role == "AXOutlineRow" || subrole == "AXOutlineRow" || subrole == "AXTableRow")
            && rect.width <= 460.0 && rect.height >= 16.0 && rect.height <= 72.0
        guard ElementGeometryResolver.isControlSizeEligible(
            size: rect.size,
            role: role,
            subrole: subrole,
            isExplicitControl: isSemantic,
            isInsideToolbar: isInsideToolbar,
            isSidebarRow: isApplicationGroupRow
        ) else {
            return nil
        }

        // macOS 26/27 Liquid Glass NSToolbarItem buttons often report full toolbar height (~52pt)
        // while the visible glass pill/circle is ~36pt centered vertically.
        var visualRect = rect
        var effectiveRegionRect = rect
        var isSidebarRowShape = isApplicationGroupRow
        if !isInsideToolbar,
           (role == "AXButton" || role == "AXLink"),
           let shapedText = shapedSidebarRowTextRect(for: elem, childRect: rect, parent: directParent) {
            visualRect = shapedText
            effectiveRegionRect = shapedText
            isSidebarRowShape = true
        } else {
            visualRect = ElementGeometryResolver.normalizeToolbarRect(rect, isInsideToolbar: isInsideToolbar)
        }

        let maxDim = max(visualRect.width, visualRect.height)
        let minDim = min(visualRect.width, visualRect.height)
        let axID = stringAttribute(elem, kAXIdentifierAttribute) ?? ""
        let isNotchButton = (axID == "notch.activation")
        let padding = ElementGeometryResolver.resolvePadding(
            visualRect: visualRect,
            role: role,
            isInsideToolbar: isInsideToolbar,
            isSidebarRow: isSidebarRowShape,
            isNotchButton: isNotchButton
        )

        let isCompactSquareControl = minDim >= 12.0 && maxDim <= 34.0 && abs(visualRect.width - visualRect.height) <= 3.5
        let isCircularCloseOrDeleteButton: Bool = {
            guard isCompactSquareControl && (role == "AXButton" || subrole == "AXCloseButton") else {
                return false
            }
            if isInsideNotificationCenter || subrole == "AXCloseButton" {
                return true
            }
            let label = primaryAccessibilityLabel(elem)?.lowercased() ?? ""
            let lowerID = axID.lowercased()
            let keywords = ["close", "dismiss", "delete", "remove", "clear", "закры", "удал", "очист"]
            return keywords.contains { label.contains($0) || lowerID.contains($0) }
        }()

        let domRadius = Self.resolvedDomCornerRadius(for: elem, visualRect: visualRect, parent: directParent)
        let cornerRadius = ElementGeometryResolver.resolveCornerRadius(
            visualRect: visualRect,
            role: role,
            subrole: subrole,
            isInsideToolbar: isInsideToolbar,
            isSidebarRow: isSidebarRowShape,
            isCircularCloseOrDelete: isCircularCloseOrDeleteButton,
            isNotchButton: isNotchButton,
            domRadius: domRadius
        )
        let baseSlipCap: CGFloat = isSidebarRowShape ? 3.5 : (maxDim > 125.0 ? 5.0 : 8.0)
        let tightMaxSlip = min(baseSlipCap, max(2.5, minDim * 0.20))

        return HitTarget(
            id: "\(role)-\(Int(visualRect.minX))-\(Int(visualRect.minY))-\(Int(visualRect.width))x\(Int(visualRect.height))",
            rect: visualRect,
            regionRect: effectiveRegionRect,
            cornerRadius: cornerRadius,
            kind: .highlight,
            slipX: ApplePointerConstants.Effect.highlightSlipX,
            slipY: ApplePointerConstants.Effect.highlightSlipY,
            maxSlipPoints: tightMaxSlip,
            horizontalPadding: padding.horizontal,
            verticalPadding: padding.vertical,
            overlayEffectStyle: .standard,
            accessoryKind: role == "AXIncrementor" ? .verticalArrows : .none
        )
    }

    /// Electron / web sidebar chat rows (e.g. Codex chat list) expose two distinct entities:
    /// 1) the outer chat row container (AXGroup/AXApplicationGroup, ~211x30), and
    /// 2) the inner title text button (AXButton, ~143-168x20) alongside trailing action icons (Pin / Archive).
    /// Keep BOTH entities distinct: when hovering the outer row chrome/margin, the full row highlights;
    /// when hovering the chat title text button, shape a crisp padded pill around the text area itself
    /// (breathing room on left/top/bottom, trimmed cleanly before trailing Pin/Archive icons).
    private static func shapedSidebarRowTextRect(
        for elem: AXUIElement,
        childRect: CGRect,
        parent: AXUIElement?
    ) -> CGRect? {
        guard let parent = parent ?? parentAttribute(elem) else { return nil }
        guard childRect.width >= 48.0, childRect.height <= 28.0 else { return nil }

        let parentRole = stringAttribute(parent, kAXRoleAttribute) ?? ""
        let parentSubrole = stringAttribute(parent, kAXSubroleAttribute) ?? ""
        guard parentRole == "AXGroup" || parentRole == "AXRow" else { return nil }
        guard let parentRect = frameAttribute(parent) else { return nil }
        guard parentRect.width <= 340.0, parentRect.height >= 24.0, parentRect.height <= 46.0 else {
            return nil
        }
        guard parentRect.insetBy(dx: -2.0, dy: -2.0).contains(childRect) else { return nil }
        guard (parentRect.width - childRect.width) >= 14.0 || (parentRect.height - childRect.height) >= 4.0 else {
            return nil
        }

        let isApplicationRow = parentSubrole == "AXApplicationGroup" || parentRole == "AXRow"
        let parentHasPress = actionNames(parent).contains(kAXPressAction as String)
        guard isApplicationRow || parentHasPress else { return nil }

        let childLabel = primaryAccessibilityLabel(elem)
        let parentLabel = primaryAccessibilityLabel(parent)
        let matchesRowTitle: Bool
        if let c = childLabel, let p = parentLabel, !c.isEmpty, c == p {
            matchesRowTitle = true
        } else if isApplicationRow && parentHasPress && childRect.width >= 70.0 && childRect.height <= 24.0 {
            matchesRowTitle = true
        } else {
            matchesRowTitle = false
        }
        guard matchesRowTitle else { return nil }

        // Find the leftmost trailing sibling action/status element (e.g. Pin / Archive group)
        // so the text field pill stops cleanly before those icons instead of overlapping them.
        var trailingLimitX = parentRect.maxX - 3.0
        for sibling in visibleOrAllChildren(parent) {
            guard let sibRect = frameAttribute(sibling), sibRect.width >= 12.0, sibRect.height >= 12.0 else { continue }
            // Skip the text button itself
            if abs(sibRect.minX - childRect.minX) < 2.0 && abs(sibRect.width - childRect.width) < 2.0 {
                continue
            }
            if sibRect.minX > childRect.minX + 36.0 && sibRect.minX < trailingLimitX {
                trailingLimitX = sibRect.minX - 4.0
            }
        }

        // Align left edge with the parent row so the row's leading icon and title highlight as one
        // coherent shape (matching macOS sidebar rows) while stopping cleanly before trailing Pin/Archive icons.
        let minX = parentRect.minX + 1.0
        let desiredMaxX = min(parentRect.maxX - 3.0, childRect.maxX + 6.0)
        let maxX = max(minX + 44.0, min(desiredMaxX, trailingLimitX))

        let minY = parentRect.minY + 0.5
        let height = max(childRect.height, parentRect.height - 1.0)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: height)
    }

    private static func primaryAccessibilityLabel(_ elem: AXUIElement) -> String? {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if let s = stringAttribute(elem, attr)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    private static func stringAttribute(_ elem: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func stringArrayAttribute(_ elem: AXUIElement, _ attr: String) -> [String] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &value) == .success else {
            return []
        }
        return (value as? [String]) ?? []
    }

    /// Resolves CSS/Tailwind border-radius from the element itself, a same-sized visual child wrapper,
    /// or a same-sized / token-bearing parent (e.g. [--radius-token-row:10px]).
    private static func resolvedDomCornerRadius(
        for elem: AXUIElement,
        visualRect: CGRect,
        parent: AXUIElement?
    ) -> CGFloat? {
        let minDim = min(visualRect.width, visualRect.height)
        let ownClasses = stringArrayAttribute(elem, "AXDOMClassList")
        let parentElem = parent ?? parentAttribute(elem)
        let parentClasses = parentElem.map { stringArrayAttribute($0, "AXDOMClassList") } ?? []

        if let direct = ElementGeometryResolver.domCornerRadius(
            classes: ownClasses,
            minDim: minDim,
            ancestorTokenClasses: []
        ) {
            return direct
        }

        // Check a single/matching visual child wrapper (e.g. <button><div class="rounded-xl">...</div></button>)
        for child in visibleOrAllChildren(elem).prefix(3) {
            guard let cf = frameAttribute(child),
                  abs(cf.width - visualRect.width) <= 4.0,
                  abs(cf.height - visualRect.height) <= 4.0 else { continue }
            let childClasses = stringArrayAttribute(child, "AXDOMClassList")
            if let childRadius = ElementGeometryResolver.domCornerRadius(classes: childClasses, minDim: minDim) {
                return childRadius
            }
        }

        // Check same-sized parent classes, or parent CSS custom radius token (e.g. [--radius-token-row:10px])
        if let parentElem {
            if let pf = frameAttribute(parentElem),
               abs(pf.width - visualRect.width) <= 6.0,
               abs(pf.height - visualRect.height) <= 6.0,
               let parentRadius = ElementGeometryResolver.domCornerRadius(classes: parentClasses, minDim: minDim) {
                return parentRadius
            }
            if let tokenRadius = ElementGeometryResolver.domCornerRadius(classes: [], minDim: minDim, ancestorTokenClasses: parentClasses) {
                return tokenRadius
            }
        }
        return nil
    }

    private static func hasInteractiveStylingHint(_ elem: AXUIElement) -> Bool {
        let classes = stringArrayAttribute(elem, "AXDOMClassList")
        guard !classes.isEmpty else { return false }
        return classes.contains { cls in
            cls == "cursor-pointer"
                || cls == "cursor-interaction"
                || cls.hasPrefix("rounded")
                || cls.localizedCaseInsensitiveContains("button")
                || cls.localizedCaseInsensitiveContains("btn")
                || cls.localizedCaseInsensitiveContains("tab")
                || cls.localizedCaseInsensitiveContains("item")
        }
    }

    /// Detects Chromium/Electron CSS overflow scrollbars (which do not expose an AXScrollBar node)
    /// when the pointer hovers the rightmost or bottom 14pt scrollbar strip of a scrollable container.
    private static func makeWebScrollbarTargetIfEdge(
        _ elem: AXUIElement,
        role: String,
        frame: CGRect,
        at point: CGPoint
    ) -> HitTarget? {
        guard role == "AXGroup" || role == "AXScrollArea" || role == "AXWebArea" else { return nil }
        guard frame.width >= 80.0 && frame.height >= 80.0 else { return nil }

        let nearRightEdge = (point.x >= frame.maxX - 14.0 && point.x <= frame.maxX + 2.0)
            && (point.y >= frame.minY + 4.0 && point.y <= frame.maxY - 4.0)
        let nearBottomEdge = (point.y >= frame.maxY - 14.0 && point.y <= frame.maxY + 2.0)
            && (point.x >= frame.minX + 4.0 && point.x <= frame.maxX - 4.0)
        guard nearRightEdge || nearBottomEdge else { return nil }

        let classes = stringArrayAttribute(elem, "AXDOMClassList")
        let hasVerticalScrollClass = classes.contains { cls in
            cls == "overflow-y-auto"
                || cls == "overflow-y-scroll"
                || cls == "overflow-auto"
                || cls == "overflow-scroll"
                || cls.localizedCaseInsensitiveContains("scrollbar")
                || cls.localizedCaseInsensitiveContains("scroll-area")
                || cls.localizedCaseInsensitiveContains("scrollable")
        }
        let hasHorizontalScrollClass = classes.contains { cls in
            cls == "overflow-x-auto"
                || cls == "overflow-x-scroll"
                || cls == "overflow-auto"
                || cls == "overflow-scroll"
        }

        if nearRightEdge && (hasVerticalScrollClass || (role == "AXScrollArea" && frame.height >= 160.0)) {
            let w: CGFloat = 9.0
            let h: CGFloat = min(68.0, max(32.0, frame.height * 0.14))
            let cy = max(frame.minY + h * 0.5, min(frame.maxY - h * 0.5, point.y))
            let capsule = CGRect(x: frame.maxX - w - 1.5, y: cy - h * 0.5, width: w, height: h)
            let trackRegion = CGRect(x: frame.maxX - 14.0, y: frame.minY, width: 16.0, height: frame.height)
            return HitTarget(
                id: "web-scrollbar-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))x\(Int(frame.height))-v",
                rect: capsule,
                regionRect: trackRegion,
                cornerRadius: w * 0.5,
                kind: .scrollThumb,
                slipX: 0.08,
                slipY: 1.0,
                maxSlipPoints: 2.5,
                overlayEffectStyle: .standard
            )
        }

        if nearBottomEdge && hasHorizontalScrollClass {
            let h: CGFloat = 9.0
            let w: CGFloat = min(68.0, max(32.0, frame.width * 0.14))
            let cx = max(frame.minX + w * 0.5, min(frame.maxX - w * 0.5, point.x))
            let capsule = CGRect(x: cx - w * 0.5, y: frame.maxY - h - 1.5, width: w, height: h)
            let trackRegion = CGRect(x: frame.minX, y: frame.maxY - 14.0, width: frame.width, height: 16.0)
            return HitTarget(
                id: "web-scrollbar-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))x\(Int(frame.height))-h",
                rect: capsule,
                regionRect: trackRegion,
                cornerRadius: h * 0.5,
                kind: .scrollThumb,
                slipX: 1.0,
                slipY: 0.08,
                maxSlipPoints: 2.5,
                overlayEffectStyle: .standard
            )
        }

        return nil
    }

    private static func boolAttribute(_ elem: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    private static func isAttributeSettable(_ elem: AXUIElement, _ attr: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(elem, attr as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private static func doubleAttribute(_ elem: AXUIElement, _ attr: String) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.doubleValue
    }

    private static func parentAttribute(_ elem: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &value) == .success else {
            return nil
        }
        guard let cf = value, CFGetTypeID(cf) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(cf, to: AXUIElement.self)
    }

    private static func visibleOrAllChildren(_ elem: AXUIElement) -> [AXUIElement] {
        var visRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXVisibleChildrenAttribute as CFString, &visRef) == .success,
           let vis = visRef as? [AXUIElement], !vis.isEmpty {
            return vis
        }
        var chRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &chRef) == .success,
           let ch = chRef as? [AXUIElement] {
            return ch
        }
        return []
    }

    private static func frameAttribute(_ elem: AXUIElement) -> CGRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(elem, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let posAX = posVal, let sizeAX = sizeVal,
              CFGetTypeID(posAX) == AXValueGetTypeID(),
              CFGetTypeID(sizeAX) == AXValueGetTypeID() else {
            return nil
        }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(posAX, to: AXValue.self), .cgPoint, &pt),
              AXValueGetValue(unsafeDowncast(sizeAX, to: AXValue.self), .cgSize, &sz) else {
            return nil
        }
        return CGRect(origin: pt, size: sz)
    }

    private static func actionNames(_ elem: AXUIElement) -> [String] {
        var namesRef: CFArray?
        guard AXUIElementCopyActionNames(elem, &namesRef) == .success,
              let names = namesRef as? [String] else {
            return []
        }
        return names
    }

    private static func hasAccessibilityLabel(_ elem: AXUIElement) -> Bool {
        for attr in [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute] {
            if let s = stringAttribute(elem, attr), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        return false
    }

    private static func containsTextInput(_ elem: AXUIElement) -> Bool {
        let children = visibleOrAllChildren(elem)
        for child in children.prefix(8) {
            let r = stringAttribute(child, kAXRoleAttribute) ?? ""
            let sr = stringAttribute(child, kAXSubroleAttribute) ?? ""
            if textInputRoles.contains(r) || sr == "AXTextArea" || boolAttribute(child, "AXEditable") == true {
                return true
            }
        }
        return false
    }

    private static func containsPureTextOnly(_ elem: AXUIElement) -> Bool {
        let children = visibleOrAllChildren(elem)
        guard !children.isEmpty else { return false }
        var sawPureText = false
        var sawOtherRole = false
        for child in children.prefix(8) {
            let r = stringAttribute(child, kAXRoleAttribute) ?? ""
            if pureTextRoles.contains(r) {
                sawPureText = true
            } else if !r.isEmpty {
                sawOtherRole = true
            }
        }
        return sawPureText && !sawOtherRole
    }

    private static func makeConstrainedTextBeamTarget(
        elem: AXUIElement,
        role: String,
        at point: CGPoint,
        fallbackRect: CGRect?
    ) -> HitTarget? {
        let queried = queryTextLineRect(elem, at: point)
        let lineRect: CGRect
        if let queried {
            lineRect = queried
        } else if role == "AXStaticText",
                  let f = fallbackRect,
                  f.width >= 6.0,
                  f.height >= 10.0,
                  f.height <= 56.0,
                  f.insetBy(dx: -4.0, dy: -3.0).contains(point) {
            // Single-line AXStaticText node (common in Chromium/Electron/SwiftUI) gives exact line bounds directly.
            lineRect = f
        } else {
            return nil
        }
        let verticalTolerance = max(lineRect.height * 0.72, 11.0)
        let isOnTextLine = abs(point.y - lineRect.midY) <= verticalTolerance
        let clampedH = min(46.0, max(18.0, lineRect.height + 4.0))

        if isOnTextLine {
            let spanX = fallbackRect?.minX ?? (point.x - 160.0)
            let spanW = max(fallbackRect?.width ?? 320.0, 48.0)
            let lineRegion = CGRect(
                x: spanX,
                y: lineRect.minY - 1.5,
                width: spanW,
                height: lineRect.height + 3.0
            )
            return HitTarget(
                id: "ibeam-\(role)-\(Int(round(lineRect.midY)))-\(Int(round(clampedH)))",
                rect: CGRect(
                    x: point.x - ApplePointerConstants.Geometry.beamWidth * 0.5,
                    y: lineRect.midY - clampedH * 0.5,
                    width: ApplePointerConstants.Geometry.beamWidth,
                    height: clampedH
                ),
                regionRect: lineRegion,
                cornerRadius: ApplePointerConstants.Geometry.beamWidth * 0.5,
                kind: .beam,
                slipX: ApplePointerConstants.Effect.beamSlipX,
                slipY: 0.14,
                maxSlipPoints: min(2.4, max(1.2, lineRect.height * 0.14)),
                overlayEffectStyle: .none
            )
        }

        return HitTarget(
            id: "ibeam-free-\(role)-\(Int(round(clampedH)))",
            rect: CGRect(
                x: point.x - ApplePointerConstants.Geometry.beamWidth * 0.5,
                y: point.y - clampedH * 0.5,
                width: ApplePointerConstants.Geometry.beamWidth,
                height: clampedH
            ),
            regionRect: fallbackRect ?? CGRect(x: point.x - 1.5, y: point.y - clampedH * 0.5, width: ApplePointerConstants.Geometry.beamWidth, height: clampedH),
            cornerRadius: ApplePointerConstants.Geometry.beamWidth * 0.5,
            kind: .beam,
            slipX: ApplePointerConstants.Effect.beamSlipX,
            slipY: ApplePointerConstants.Effect.beamSlipY,
            maxSlipPoints: .greatestFiniteMagnitude,
            overlayEffectStyle: .none
        )
    }

    private static func queryTextLineRect(_ elem: AXUIElement, at point: CGPoint) -> CGRect? {
        var pt = point
        guard let ptVal = AXValueCreate(.cgPoint, &pt) else { return nil }
        var rangeRef: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(elem, kAXRangeForPositionParameterizedAttribute as CFString, ptVal, &rangeRef) == .success,
           let rangeAX = rangeRef,
           CFGetTypeID(rangeAX) == AXValueGetTypeID() {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(elem, kAXBoundsForRangeParameterizedAttribute as CFString, rangeAX, &boundsRef) == .success,
               let boundsAX = boundsRef,
               CFGetTypeID(boundsAX) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(unsafeDowncast(boundsAX, to: AXValue.self), .cgRect, &rect),
                   rect.height >= 8.0 && rect.height <= 120.0,
                   rect.minY.isFinite && rect.height.isFinite {
                    return rect
                }
            }
        }
        // WebKit / Safari fallback via AXTextMarkerForPosition -> AXLineTextMarkerRangeForTextMarker
        var markerRef: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(elem, "AXTextMarkerForPosition" as CFString, ptVal, &markerRef) == .success,
           let marker = markerRef {
            var lineRangeRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(elem, "AXLineTextMarkerRangeForTextMarker" as CFString, marker, &lineRangeRef) == .success,
               let lineRange = lineRangeRef {
                var boundsRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(elem, "AXBoundsForTextMarkerRange" as CFString, lineRange, &boundsRef) == .success,
                   let boundsAX = boundsRef,
                   CFGetTypeID(boundsAX) == AXValueGetTypeID() {
                    var rect = CGRect.zero
                    if AXValueGetValue(unsafeDowncast(boundsAX, to: AXValue.self), .cgRect, &rect),
                       rect.height >= 8.0 && rect.height <= 120.0,
                       rect.minY.isFinite && rect.height.isFinite {
                        return rect
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Focused Text Caret Query (VS Code Smooth Caret Mode)

    private static let excludedSmoothCaretBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "dev.zed.Zed",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.cmuxterm.app",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm"
    ]

    private let caretQueue = DispatchQueue(label: "com.nikolenko.ApplePointer.caret", qos: .userInteractive)
    private var isCaretQueryInFlight = false

    func queryFocusedCaretAsync(frontmostPID: pid_t, bundleID: String?, completion: @escaping @Sendable (CGRect?) -> Void) {
        guard AXIsProcessTrusted(), frontmostPID != ownPID else {
            completion(nil)
            return
        }
        if let bundleID, Self.excludedSmoothCaretBundleIDs.contains(bundleID) {
            completion(nil)
            return
        }
        lock.lock()
        if isCaretQueryInFlight {
            lock.unlock()
            return
        }
        isCaretQueryInFlight = true
        lock.unlock()

        caretQueue.async { [weak self] in
            defer {
                self?.lock.lock()
                self?.isCaretQueryInFlight = false
                self?.lock.unlock()
            }
            self?.enableManualAXIfNeeded(for: frontmostPID, encounteringRole: nil)
            let rect = Self.queryFocusedCaretRectSync(pid: frontmostPID)
            completion(rect)
        }
    }

    private static func queryFocusedCaretRectSync(pid: pid_t) -> CGRect? {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.06)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedCF = focusedRef,
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else {
            return nil
        }
        let elem = unsafeDowncast(focusedCF, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(elem, 0.06)

        let role = stringAttribute(elem, kAXRoleAttribute) ?? ""
        guard textInputRoles.contains(role)
                || role == "AXWebArea"
                || role == "AXGroup"
                || role == "AXStaticText"
                || role == "AXGenericElement"
                || role == "AXScrollArea" else {
            return nil
        }
        let elemFrame = frameAttribute(elem)

        func isValidCaretRect(_ r: CGRect) -> Bool {
            guard r.height >= 10.0, r.height <= 64.0, r.width <= 8.0,
                  r.minX.isFinite, r.minY.isFinite, r.height.isFinite,
                  !(r.minX == 0 && r.maxY >= 1000 && r.height == 0) else {
                return false
            }
            if let f = elemFrame, f.width > 0, f.height > 0 {
                return f.insetBy(dx: -24.0, dy: -24.0).contains(CGPoint(x: r.midX, y: r.midY))
            }
            return true
        }

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rCF = rangeRef,
           CFGetTypeID(rCF) == AXValueGetTypeID() {
            let rangeAX = unsafeDowncast(rCF, to: AXValue.self)
            var cfRange = CFRange()
            if AXValueGetValue(rangeAX, .cfRange, &cfRange), cfRange.length == 0 {
                if let direct = boundsForCFRange(elem, range: cfRange), isValidCaretRect(direct) {
                    return CGRect(x: direct.minX, y: direct.minY, width: 2.4, height: direct.height)
                }
                if cfRange.location > 0,
                   let prevChar = boundsForCFRange(elem, range: CFRange(location: cfRange.location - 1, length: 1)),
                   prevChar.height >= 10.0, prevChar.height <= 64.0, prevChar.width >= 0.5, prevChar.width <= 48.0 {
                    let candidate = CGRect(x: prevChar.maxX, y: prevChar.minY, width: 2.4, height: prevChar.height)
                    if isValidCaretRect(candidate) {
                        return candidate
                    }
                }
                if let nextChar = boundsForCFRange(elem, range: CFRange(location: cfRange.location, length: 1)),
                   nextChar.height >= 10.0, nextChar.height <= 64.0, nextChar.width >= 0.5, nextChar.width <= 48.0 {
                    let candidate = CGRect(x: nextChar.minX, y: nextChar.minY, width: 2.4, height: nextChar.height)
                    if isValidCaretRect(candidate) {
                        return candidate
                    }
                }
            }
        }

        var markerRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, "AXSelectedTextMarkerRange" as CFString, &markerRangeRef) == .success,
           let mr = markerRangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(elem, "AXBoundsForTextMarkerRange" as CFString, mr, &boundsRef) == .success,
               let bCF = boundsRef,
               CFGetTypeID(bCF) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(unsafeDowncast(bCF, to: AXValue.self), .cgRect, &rect), isValidCaretRect(rect) {
                    return CGRect(x: rect.minX, y: rect.minY, width: 2.4, height: rect.height)
                }
            }
            // WebKit / Chromium marker fallback: step 1 character backward from the selected start marker
            // when the collapsed marker range reports zero or container-wide bounds.
            var startMarkerRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(elem, "AXStartTextMarkerForTextMarkerRange" as CFString, mr, &startMarkerRef) == .success,
               let startMarker = startMarkerRef {
                var prevMarkerRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(elem, "AXPreviousTextMarkerForTextMarker" as CFString, startMarker, &prevMarkerRef) == .success,
                   let prevMarker = prevMarkerRef {
                    let pair = [prevMarker, startMarker] as CFArray
                    var prevRangeRef: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(elem, "AXTextMarkerRangeForUnorderedTextMarkers" as CFString, pair, &prevRangeRef) == .success,
                       let prevRange = prevRangeRef {
                        var pbRef: CFTypeRef?
                        if AXUIElementCopyParameterizedAttributeValue(elem, "AXBoundsForTextMarkerRange" as CFString, prevRange, &pbRef) == .success,
                           let pbCF = pbRef,
                           CFGetTypeID(pbCF) == AXValueGetTypeID() {
                            var pRect = CGRect.zero
                            if AXValueGetValue(unsafeDowncast(pbCF, to: AXValue.self), .cgRect, &pRect),
                               pRect.height >= 10.0, pRect.height <= 64.0, pRect.width >= 0.5, pRect.width <= 48.0 {
                                let candidate = CGRect(x: pRect.maxX, y: pRect.minY, width: 2.4, height: pRect.height)
                                if isValidCaretRect(candidate) {
                                    return candidate
                                }
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func boundsForCFRange(_ elem: AXUIElement, range: CFRange) -> CGRect? {
        var mutable = range
        guard let rangeVal = AXValueCreate(.cfRange, &mutable) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(elem, kAXBoundsForRangeParameterizedAttribute as CFString, rangeVal, &boundsRef) == .success,
              let bCF = boundsRef,
              CFGetTypeID(bCF) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeDowncast(bCF, to: AXValue.self), .cgRect, &rect) else { return nil }
        return rect
    }
}
