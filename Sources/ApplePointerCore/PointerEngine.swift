import CoreGraphics
import Foundation

public final class PointerEngine: @unchecked Sendable {
    public var configuration: PointerConfiguration

    public private(set) var modelCursorPosition: CGPoint
    public private(set) var currentTarget: HitTarget?
    public private(set) var activeResizeKind: ResizeCursorKind = .none
    public private(set) var activeSpecialCursorKind: SpecialCursorKind = .none
    public private(set) var systemIBeamActive: Bool = false
    public private(set) var systemCrosshairActive: Bool = false
    public private(set) var isPressed: Bool = false
    public private(set) var isAutohidden: Bool = false
    public private(set) var isHiddenByTyping: Bool = false
    public private(set) var isDarkBackground: Bool = false
    public private(set) var isSystemDarkAppearance: Bool = false
    public private(set) var lastInteractionTimestamp: TimeInterval
    public private(set) var lastInputWasTrackpad: Bool = false
    public private(set) var smoothedVelocity: CGPoint = .zero
    public private(set) var accessibilityZoomFactor: CGFloat = 1.0
    public private(set) var isFullscreenVideoActive: Bool = false

    private var lastMouseMoveTimestamp: TimeInterval
    private var lastScrollTimestamp: TimeInterval = -.infinity
    private var lastTargetID: String?
    private var lastVisibleResizeKind: ResizeCursorKind = .none
    private var lastVisibleSpecialCursorKind: SpecialCursorKind = .none
    private var lastVisibleAccessoryKind: PointerAccessoryKind = .none
    private var typingHideAnchorPosition: CGPoint?
    private var typingHideTimestamp: TimeInterval = -.infinity
    private var consecutiveFastMoves: Int = 0
    private var shakeDetector = ShakeToFindDetector()
    private var lastSteppedState: PointerRenderState?
    private var stableFrameCount: Int = 0

    // Analytical 1D springs matching PUIDPointerRenderingRootViewController & PUIDPointerShapeView
    private var posX = Spring1D(value: 0)
    private var posY = Spring1D(value: 0)
    private var width = Spring1D(value: ApplePointerConstants.Geometry.systemPointerSize)
    private var height = Spring1D(value: ApplePointerConstants.Geometry.systemPointerSize)
    private var cornerRadius = Spring1D(value: ApplePointerConstants.Geometry.systemPointerSize * 0.5)
    private var rampingX = Spring1D(value: 0)
    private var rampingY = Spring1D(value: 0)
    private var intensity = Spring1D(value: ApplePointerConstants.Material.materialAlphaDot)
    private var pressedScale = Spring1D(value: 1.0)
    private var pressedBlend = Spring1D(value: 0.0)
    private var autohideScale = Spring1D(value: 1.0)
    private var autohideOpacity = Spring1D(value: 1.0)
    private var blurRadius = Spring1D(value: 0.0)
    private var specularOpacity = Spring1D(value: 0.0)
    private var lumaMix = Spring1D(value: 0.0)
    private var shakeScale = Spring1D(value: 1.0)
    private var recenterShiftX = Spring1D(value: 0.0)
    private var recenterShiftY = Spring1D(value: 0.0)
    private var arrowBlend = Spring1D(value: 1.0)
    private var resizeBlend = Spring1D(value: 0.0)
    private var crosshairBlend = Spring1D(value: 0.0)
    private var specialCursorBlend = Spring1D(value: 0.0)
    private var accessoryBlend = Spring1D(value: 0.0)
    private var elasticScaleX = Spring1D(value: 1.0)
    private var elasticScaleY = Spring1D(value: 1.0)
    private var liftShadowAlpha = Spring1D(value: 0.0)
    private var rimDirX = Spring1D(value: -0.7)
    private var rimDirY = Spring1D(value: 0.7)
    private var perspectiveTiltYSpring = Spring1D(value: 0.0)
    private var innerPointerBlend = Spring1D(value: 0.0)
    private var contourBlend = Spring1D(value: 0.0)
    private var contourRadiiSprings: [Spring1D] = Array(repeating: Spring1D(value: ApplePointerConstants.Geometry.systemPointerSize * 0.5), count: OrganicContour.sampleCount)

    public init(
        initialPosition: CGPoint = .zero,
        timestamp: TimeInterval = 0,
        configuration: PointerConfiguration = PointerConfiguration()
    ) {
        self.configuration = configuration
        self.modelCursorPosition = initialPosition
        self.lastInteractionTimestamp = timestamp
        self.lastMouseMoveTimestamp = timestamp
        self.posX.reset(to: Double(initialPosition.x))
        self.posY.reset(to: Double(initialPosition.y))
        let dotSize = ApplePointerConstants.Geometry.systemPointerSize * configuration.activeSizeMultiplier
        self.width.reset(to: Double(dotSize))
        self.height.reset(to: Double(dotSize))
        self.cornerRadius.reset(to: Double(dotSize * 0.5))
        self.arrowBlend.reset(to: configuration.pointerShapeStyle == .appleMouse ? 1.0 : 0.0)
        self.resizeBlend.reset(to: 0.0)
        self.crosshairBlend.reset(to: 0.0)
        self.specialCursorBlend.reset(to: 0.0)
        self.accessoryBlend.reset(to: 0.0)
        for i in 0..<contourRadiiSprings.count {
            self.contourRadiiSprings[i].reset(to: Double(dotSize * 0.5))
        }
    }

    public func updatePointerPosition(_ point: CGPoint, timestamp: TimeInterval, isTrackpad: Bool? = nil) {
        let prevPoint = modelCursorPosition
        let dist = hypot(point.x - modelCursorPosition.x, point.y - modelCursorPosition.y)
        let moved: Bool
        if isHiddenByTyping {
            // Rock-solid MacBook trackpad palm rejection while typing:
            // require >= 24pt travel within 0.45s of typing, or >= 12pt deliberate movement afterward.
            let anchor = typingHideAnchorPosition ?? prevPoint
            let recentlyTyped = (timestamp - typingHideTimestamp) < 0.45
            let threshold: CGFloat = recentlyTyped ? 24.0 : 12.0
            moved = hypot(point.x - anchor.x, point.y - anchor.y) >= threshold
        } else {
            moved = dist > 0.25
        }
        modelCursorPosition = point

        let moveDt = timestamp - lastMouseMoveTimestamp
        if dist > 0.25 && moveDt > 0.0005 && moveDt < 0.12 {
            let instVx = (point.x - prevPoint.x) / CGFloat(moveDt)
            let instVy = (point.y - prevPoint.y) / CGFloat(moveDt)
            let w = ApplePointerConstants.Behavior.pointerVelocitySmoothingWeight
            smoothedVelocity = CGPoint(
                x: smoothedVelocity.x * (1.0 - w) + instVx * w,
                y: smoothedVelocity.y * (1.0 - w) + instVy * w
            )
            let speed = hypot(smoothedVelocity.x, smoothedVelocity.y)
            if speed >= ApplePointerConstants.Behavior.minimumVelocityThresholdForDeceleration {
                consecutiveFastMoves = min(consecutiveFastMoves + 1, 10)
            } else {
                consecutiveFastMoves = 0
            }
        } else if moveDt >= 0.12 {
            smoothedVelocity = .zero
            consecutiveFastMoves = 0
        }

        if moved {
            lastInteractionTimestamp = timestamp
        }
        if let isTrackpad {
            lastInputWasTrackpad = isTrackpad
        }

        if isPressed,
           let target = currentTarget,
           target.id.hasPrefix("burette-3d-"),
           dist > 1.5 {
            currentTarget = nil
            lastTargetID = nil
            recenterShiftX.reset(to: 0.0)
            recenterShiftY.reset(to: 0.0)
        }

        if let target = currentTarget,
           !target.regionRect.insetBy(
               dx: target.kind == .beam ? -8.0 : -ApplePointerConstants.Behavior.regionExitHysteresis,
               dy: target.kind == .beam ? -3.0 : -ApplePointerConstants.Behavior.regionExitHysteresis
           ).contains(point) {
            if target.kind != .beam || target.slipY < 1.0 {
                currentTarget = nil
                lastTargetID = nil
                recenterShiftX.reset(to: 0.0)
                recenterShiftY.reset(to: 0.0)
            }
        }

        if moved {
            lastMouseMoveTimestamp = timestamp
            stableFrameCount = 0
            if configuration.shakeToFindEnabled {
                shakeDetector.recordMove(point: point, timestamp: timestamp)
            }
            if isAutohidden || isHiddenByTyping {
                wakeFromAutohide()
            }
        }
    }

    public func setPressed(_ pressed: Bool, timestamp: TimeInterval) {
        isPressed = pressed
        lastInteractionTimestamp = timestamp
        stableFrameCount = 0
        if isAutohidden || isHiddenByTyping {
            wakeFromAutohide()
        }
    }

    public func registerScrollOrActivity(timestamp: TimeInterval, isTrackpad: Bool? = nil) {
        lastInteractionTimestamp = timestamp
        lastScrollTimestamp = timestamp
        stableFrameCount = 0
        if let isTrackpad {
            lastInputWasTrackpad = isTrackpad
        }
        if currentTarget?.kind != .beam {
            currentTarget = nil
            lastTargetID = nil
            recenterShiftX.reset(to: 0.0)
            recenterShiftY.reset(to: 0.0)
        }
        if isAutohidden && !isHiddenByTyping {
            wakeFromAutohide()
        }
    }

    public func hideForTyping(at timestamp: TimeInterval = 0) {
        guard configuration.hideWhileTyping, !isPressed else { return }
        if !isHiddenByTyping {
            typingHideAnchorPosition = modelCursorPosition
        }
        typingHideTimestamp = timestamp
        isHiddenByTyping = true
        isAutohidden = true
        stableFrameCount = 0
    }

    public func updateResizeCursor(_ kind: ResizeCursorKind) {
        if activeResizeKind != kind {
            stableFrameCount = 0
        }
        activeResizeKind = kind
        if kind != .none {
            lastVisibleResizeKind = kind
            if currentTarget != nil {
                currentTarget = nil
                lastTargetID = nil
                recenterShiftX.reset(to: 0.0)
                recenterShiftY.reset(to: 0.0)
            }
        }
    }

    public func updateSystemIBeam(_ active: Bool) {
        if systemIBeamActive != active {
            stableFrameCount = 0
        }
        systemIBeamActive = active
        if active, let existing = currentTarget, existing.kind != .beam {
            currentTarget = nil
            lastTargetID = nil
            recenterShiftX.reset(to: 0.0)
            recenterShiftY.reset(to: 0.0)
        }
    }

    public func updateSystemCrosshair(_ active: Bool) {
        if systemCrosshairActive != active {
            stableFrameCount = 0
        }
        systemCrosshairActive = active
        if active, currentTarget != nil {
            currentTarget = nil
            lastTargetID = nil
            recenterShiftX.reset(to: 0.0)
            recenterShiftY.reset(to: 0.0)
        }
    }

    public func updateSpecialCursor(_ kind: SpecialCursorKind) {
        if activeSpecialCursorKind != kind {
            stableFrameCount = 0
        }
        activeSpecialCursorKind = kind
        if kind != .none {
            lastVisibleSpecialCursorKind = kind
            if currentTarget != nil {
                currentTarget = nil
                lastTargetID = nil
                recenterShiftX.reset(to: 0.0)
                recenterShiftY.reset(to: 0.0)
            }
        }
    }

    public func updateHitTarget(_ target: HitTarget?, at timestamp: TimeInterval? = nil) {
        if activeResizeKind != .none || systemCrosshairActive || activeSpecialCursorKind != .none {
            currentTarget = nil
            lastTargetID = nil
            recenterShiftX.reset(to: 0.0)
            recenterShiftY.reset(to: 0.0)
            return
        }

        if systemIBeamActive, let target, target.kind != .beam {
            return
        }

        if !configuration.magnetismEnabled {
            if target?.kind == .beam {
                currentTarget = target
                lastTargetID = target?.id
            } else {
                currentTarget = nil
                lastTargetID = nil
            }
            recenterShiftX.reset(to: 0.0)
            recenterShiftY.reset(to: 0.0)
            return
        }

        if let target {
            if target.kind != .beam && isPressed && currentTarget?.id != target.id {
                return
            }
            if target.kind != .beam,
               let ts = timestamp,
               (ts - lastScrollTimestamp) < ApplePointerConstants.Behavior.scrollSnapCooldown {
                return
            }
            // Exact Apple fast-flight velocity projection: when flying past intermediate buttons
            // above minimumVelocityThresholdForDeceleration (1000 pt/s), skip snapping if the
            // projected cursor trajectory already exits this target's region.
            if configuration.inertiaEnabled && target.kind != .beam && currentTarget?.id != target.id && consecutiveFastMoves >= 2 {
                let speed = hypot(smoothedVelocity.x, smoothedVelocity.y)
                if speed >= ApplePointerConstants.Behavior.minimumVelocityThresholdForDeceleration {
                    let lookahead: CGFloat = 0.085 * ApplePointerConstants.Behavior.pointerPositionProjectionScaleFactor
                    let projected = CGPoint(
                        x: modelCursorPosition.x + smoothedVelocity.x * lookahead,
                        y: modelCursorPosition.y + smoothedVelocity.y * lookahead
                    )
                    if !target.regionRect.insetBy(dx: -10.0, dy: -10.0).contains(projected) {
                        return
                    }
                }
            }
            if target.kind != .beam,
               !target.regionRect.insetBy(
                   dx: -ApplePointerConstants.Behavior.regionExitHysteresis,
                   dy: -ApplePointerConstants.Behavior.regionExitHysteresis
               ).contains(modelCursorPosition) {
                if let existing = currentTarget,
                   existing.kind != .beam,
                   !existing.regionRect.insetBy(
                       dx: -ApplePointerConstants.Behavior.regionExitHysteresis,
                       dy: -ApplePointerConstants.Behavior.regionExitHysteresis
                   ).contains(modelCursorPosition) {
                    currentTarget = nil
                    lastTargetID = nil
                    recenterShiftX.reset(to: 0.0)
                    recenterShiftY.reset(to: 0.0)
                }
                return
            }
        }

        if target?.id != lastTargetID {
            lastTargetID = target?.id
            recenterShiftX.reset(to: 0.0)
            recenterShiftY.reset(to: 0.0)
            stableFrameCount = 0
        }
        currentTarget = target
    }

    public func updateBackgroundLuma(_ luma: Double) {
        let prev = isDarkBackground
        if luma < ApplePointerConstants.Material.lumaLowerThreshold {
            isDarkBackground = true
        } else if luma > ApplePointerConstants.Material.lumaUpperThreshold {
            isDarkBackground = false
        }
        if isDarkBackground != prev {
            stableFrameCount = 0
        }
    }

    public func updateSystemDarkAppearance(_ isDark: Bool) {
        if isSystemDarkAppearance != isDark {
            isSystemDarkAppearance = isDark
            stableFrameCount = 0
        }
    }

    public func updateAccessibilityZoomFactor(_ factor: CGFloat) {
        let clamped = max(1.0, min(3.0, factor))
        if abs(clamped - accessibilityZoomFactor) > 0.005 {
            accessibilityZoomFactor = clamped
            stableFrameCount = 0
        }
    }

    public func updateFullscreenVideoActive(_ active: Bool) {
        isFullscreenVideoActive = active
    }

    public func markNeedsAnimation() {
        stableFrameCount = 0
    }

    public func isIdleSettled(at timestamp: TimeInterval) -> Bool {
        guard !isPressed,
              shakeDetector.targetMultiplier <= 1.001,
              (timestamp - lastMouseMoveTimestamp) >= 0.25,
              (timestamp - lastInteractionTimestamp) >= 0.25 else {
            return false
        }
        return stableFrameCount >= 8
    }

    public func nextAutohideDelay(at timestamp: TimeInterval) -> TimeInterval? {
        guard !isAutohidden, !isHiddenByTyping, configuration.autohideEnabled, !isPressed else {
            return nil
        }
        var timeout = lastInputWasTrackpad
            ? min(configuration.autohideDuration, ApplePointerConstants.Behavior.autohideDurationTrackpad)
            : configuration.autohideDuration
        if isFullscreenVideoActive {
            timeout = min(timeout, 2.0)
        }
        guard timeout > 0 else { return nil }
        let remaining = timeout - (timestamp - lastInteractionTimestamp)
        return max(0.05, remaining)
    }

    public func wakeFromAutohide() {
        let wasTypingHide = isHiddenByTyping
        isHiddenByTyping = false
        typingHideAnchorPosition = nil
        stableFrameCount = 0
        guard isAutohidden else { return }
        isAutohidden = false
        if !wasTypingHide {
            // Apple PUIDPointerSettings hiddenToVisible behavior for idle autohide wake:
            // instant seed at 1.75x + 10pt blur, then spring back to 1.0x and 0pt blur.
            autohideScale.reset(to: Double(ApplePointerConstants.Springs.hiddenToVisiblePointerScale))
            blurRadius.reset(to: Double(ApplePointerConstants.Springs.hiddenToVisiblePointerBlurRadius))
        }
    }

    public func step(dt: TimeInterval, timestamp: TimeInterval) -> PointerRenderState {
        // 1. Check autohide timeout (typing hide stays active even if idle autohide is off)
        if !isHiddenByTyping {
            if configuration.autohideEnabled && !isPressed {
                var timeout = lastInputWasTrackpad
                    ? min(configuration.autohideDuration, ApplePointerConstants.Behavior.autohideDurationTrackpad)
                    : configuration.autohideDuration
                if isFullscreenVideoActive {
                    timeout = min(timeout, 2.0)
                }
                if timeout > 0 && (timestamp - lastInteractionTimestamp) >= timeout {
                    isAutohidden = true
                }
            } else if !configuration.autohideEnabled && isAutohidden {
                wakeFromAutohide()
            }
        } else if !configuration.hideWhileTyping {
            wakeFromAutohide()
        }

        // 2. Shake to find decay
        if configuration.shakeToFindEnabled {
            shakeDetector.update(at: timestamp)
        } else {
            shakeDetector.reset()
        }
        let shakeTarget = Double(shakeDetector.targetMultiplier)
        let shakeSpring = shakeTarget > shakeScale.value
            ? ApplePointerConstants.Springs.shakeToFindExpansion
            : ApplePointerConstants.Springs.shakeToFindContraction
        shakeScale.step(to: shakeTarget, dt: dt, parameters: shakeSpring)

        // 3. Determine active target shape, slip, and intensity
        if (timestamp - lastMouseMoveTimestamp) > 0.06 {
            let decay = CGFloat(exp(-dt * 24.0))
            smoothedVelocity = CGPoint(x: smoothedVelocity.x * decay, y: smoothedVelocity.y * decay)
            consecutiveFastMoves = 0
        }
        let zoomBoost: CGFloat = configuration.scaleWithZoomEnabled
            ? min(2.0, 1.0 + (accessibilityZoomFactor - 1.0) * 0.45)
            : 1.0
        let activeSizeMultiplier = configuration.activeSizeMultiplier * zoomBoost
        let dotSize = ApplePointerConstants.Geometry.systemPointerSize * activeSizeMultiplier
        let isResizing = activeResizeKind != .none
        let isCrosshair = !isResizing && systemCrosshairActive
        let isSpecialCursor = !isResizing && !isCrosshair && activeSpecialCursorKind != .none
        let activeTarget = (isResizing || isCrosshair || isSpecialCursor) ? nil : currentTarget
        let isCameraNotchTarget = activeTarget?.id.hasPrefix("camera-notch-") ?? false
        let isMenuBarTarget = activeTarget?.id.hasPrefix("menubar-") ?? false
        let effectiveDarkBackground = isDarkBackground
            || isCameraNotchTarget
            || (isMenuBarTarget && isSystemDarkAppearance)

        let targetRect: CGRect
        let targetCornerRadius: CGFloat
        let mappedSlip: CGPoint
        let maxSlip: CGFloat
        let isSnapped: Bool
        let isBeam: Bool
        var targetIntensity: CGFloat
        let overlayStyle: OverlayEffectStyle
        var activeAccessory: PointerAccessoryKind = .none
        var dotVividnessBoost: CGFloat = 0.0

        let smallItemBaseIntensity = effectiveDarkBackground
            ? ApplePointerConstants.Material.materialAlphaSmallItemLight
            : (configuration.highContrast
                ? ApplePointerConstants.Material.materialAlphaSmallItemDarkHighContrast
                : ApplePointerConstants.Material.materialAlphaSmallItemDark)

        if !isResizing && !isCrosshair && !isSpecialCursor && (systemIBeamActive || activeTarget?.kind == .beam) {
            isSnapped = true
            isBeam = true
            let defaultBeamH = ApplePointerConstants.Geometry.beamMinLength * max(0.85, min(1.35, activeSizeMultiplier))
            let measuredH: CGFloat
            let beamCenterY: CGFloat
            if let beamTarget = activeTarget, beamTarget.kind == .beam {
                measuredH = min(
                    ApplePointerConstants.Geometry.beamMaxSnapLength,
                    max(20.0, beamTarget.rect.height)
                )
                if configuration.magnetismEnabled && beamTarget.slipY < 1.0 {
                    // Exact Apple UIAxisVertical constrained beam: X tracks 1:1 freely,
                    // while Y magnetically aligns to the text line's vertical center.
                    beamCenterY = beamTarget.rect.midY
                    mappedSlip = CGPoint(x: 1.0, y: max(0.0, min(1.0, beamTarget.slipY)))
                    maxSlip = beamTarget.maxSlipPoints
                } else {
                    beamCenterY = modelCursorPosition.y
                    mappedSlip = CGPoint(x: 1.0, y: 1.0)
                    maxSlip = .greatestFiniteMagnitude
                }
            } else {
                measuredH = defaultBeamH
                beamCenterY = modelCursorPosition.y
                mappedSlip = CGPoint(x: 1.0, y: 1.0)
                maxSlip = .greatestFiniteMagnitude
            }
            let w = ApplePointerConstants.Geometry.beamWidth
            targetRect = CGRect(x: modelCursorPosition.x - w * 0.5, y: beamCenterY - measuredH * 0.5, width: w, height: measuredH)
            targetCornerRadius = w * 0.5
            targetIntensity = ApplePointerConstants.Material.materialAlphaIBeam
            overlayStyle = .none
        } else if let target = activeTarget {
            switch target.kind {
            case .beam:
                isSnapped = true
                isBeam = true
                mappedSlip = CGPoint(x: 1.0, y: 1.0)
                maxSlip = target.maxSlipPoints
                let h = min(
                    ApplePointerConstants.Geometry.beamMaxSnapLength,
                    max(ApplePointerConstants.Geometry.beamMinLength, target.rect.height)
                )
                let w = ApplePointerConstants.Geometry.beamWidth
                targetRect = CGRect(x: modelCursorPosition.x - w * 0.5, y: modelCursorPosition.y - h * 0.5, width: w, height: h)
                targetCornerRadius = w * 0.5
                targetIntensity = ApplePointerConstants.Material.materialAlphaIBeam
                overlayStyle = .none

            case .highlight:
                isSnapped = true
                isBeam = false
                maxSlip = target.maxSlipPoints
                overlayStyle = target.overlayEffectStyle
                activeAccessory = target.accessoryKind
                let padded = target.rect.insetBy(dx: -target.horizontalPadding, dy: -target.verticalPadding)
                targetRect = padded
                let baseMinDim = min(target.rect.width, target.rect.height)
                let paddedMinDim = min(padded.width, padded.height)
                if target.cornerRadius >= baseMinDim * 0.48 {
                    // Keep circular & pill targets perfectly round after padding (traffic lights, sliders, icon buttons)
                    targetCornerRadius = paddedMinDim * 0.5
                } else {
                    let extraPad = min(target.horizontalPadding, target.verticalPadding)
                    targetCornerRadius = min(target.cornerRadius + extraPad, paddedMinDim * 0.5)
                }
                mappedSlip = Self.mappedPointerSlip(
                    shapeSize: padded.size,
                    regionSize: target.regionRect.size,
                    slipFactorX: target.slipX,
                    slipFactorY: target.slipY,
                    maxSlipPoints: target.maxSlipPoints,
                    overrideSlipPoints: target.overrideSlipPoints
                )
                let flexBase = Self.flexibleRectIntensity(
                    for: padded.size,
                    isDarkBackground: effectiveDarkBackground,
                    visualIntensity: smallItemBaseIntensity
                )
                // Keep Liquid Glass object highlights crisp & clearly legible (never dimmer than the free dot)
                if target.suppressOutline {
                    // Seamless borderless embedding for 3D molecular pieces (clean optical veil, never muddy)
                    targetIntensity = min(0.76, flexBase + (configuration.highContrast ? 0.22 : 0.10))
                } else {
                    targetIntensity = min(0.88, flexBase + (configuration.highContrast ? 0.28 : 0.18))
                }

            case .menuItem:
                isSnapped = true
                isBeam = false
                maxSlip = 0.0
                overlayStyle = target.overlayEffectStyle
                targetRect = target.rect
                targetCornerRadius = min(target.cornerRadius, min(target.rect.width, target.rect.height) * 0.5)
                mappedSlip = .zero
                // Native macOS menus already draw their own selection pill; keep our overlay
                // subtle so the pointer morphs cleanly into the row without washing out text.
                targetIntensity = configuration.highContrast ? 0.28 : (effectiveDarkBackground ? 0.20 : 0.18)

            case .lift:
                isSnapped = true
                isBeam = false
                maxSlip = target.maxSlipPoints
                overlayStyle = target.overlayEffectStyle
                let base = target.rect.insetBy(dx: -target.horizontalPadding, dy: -target.verticalPadding)
                let scale = Self.contentScale(for: base.size, scaleUpPoints: target.scaleUpPoints)
                let scaledW = base.width * scale
                let scaledH = base.height * scale
                targetRect = CGRect(
                    x: base.midX - scaledW * 0.5,
                    y: base.midY - scaledH * 0.5,
                    width: scaledW,
                    height: scaledH
                )
                targetCornerRadius = min(target.cornerRadius * scale, min(scaledW, scaledH) * 0.5)
                mappedSlip = Self.mappedPointerSlip(
                    shapeSize: targetRect.size,
                    regionSize: target.regionRect.size,
                    slipFactorX: target.slipX,
                    slipFactorY: target.slipY,
                    maxSlipPoints: target.maxSlipPoints,
                    overrideSlipPoints: target.overrideSlipPoints
                )
                let liftFlex = Self.flexibleRectIntensity(
                    for: targetRect.size,
                    isDarkBackground: effectiveDarkBackground,
                    visualIntensity: smallItemBaseIntensity
                )
                targetIntensity = min(0.82, liftFlex + (configuration.highContrast ? 0.22 : 0.10))

            case .hover:
                isSnapped = true
                isBeam = false
                maxSlip = target.maxSlipPoints
                overlayStyle = target.overlayEffectStyle
                let base = target.rect.insetBy(dx: -target.horizontalPadding, dy: -target.verticalPadding)
                let scale = Self.contentScale(for: base.size, scaleUpPoints: target.scaleUpPoints)
                let scaledW = base.width * scale
                let scaledH = base.height * scale
                targetRect = CGRect(
                    x: base.midX - scaledW * 0.5,
                    y: base.midY - scaledH * 0.5,
                    width: scaledW,
                    height: scaledH
                )
                targetCornerRadius = min(target.cornerRadius * scale, min(scaledW, scaledH) * 0.5)
                mappedSlip = CGPoint(x: 1.0, y: 1.0)
                let hoverFlex = Self.flexibleRectIntensity(
                    for: targetRect.size,
                    isDarkBackground: effectiveDarkBackground,
                    visualIntensity: smallItemBaseIntensity
                )
                targetIntensity = min(0.86, hoverFlex + (configuration.highContrast ? 0.26 : 0.18))

            case .scrollThumb:
                isSnapped = true
                isBeam = false
                maxSlip = target.maxSlipPoints
                overlayStyle = target.overlayEffectStyle
                targetRect = target.rect
                targetCornerRadius = min(target.rect.width, target.rect.height) * 0.5
                mappedSlip = CGPoint(x: max(0.0, min(1.0, target.slipX)), y: max(0.0, min(1.0, target.slipY)))
                targetIntensity = configuration.highContrast ? 0.65 : (effectiveDarkBackground ? 0.48 : 0.42)
            }
        } else {
            isSnapped = false
            isBeam = false
            mappedSlip = CGPoint(x: 1.0, y: 1.0)
            maxSlip = .greatestFiniteMagnitude
            overlayStyle = .none
            targetRect = CGRect(
                x: modelCursorPosition.x - dotSize * 0.5,
                y: modelCursorPosition.y - dotSize * 0.5,
                width: dotSize,
                height: dotSize
            )
            targetCornerRadius = dotSize * 0.5
            if configuration.pointerShapeStyle == .ipadDot {
                // Automatically strengthen small dots (< 19pt) so they remain crisp and legible,
                // matching Apple's PSPointerSettings.materialAlphaDot (0.85) in Classic mode and
                // balanced Plasma density in Liquid Glass mode without fake non-backdrop tints.
                let smallBoost = max(0.0, min(1.0, (1.0 - configuration.activeSizeMultiplier) / 0.50))
                let baseDotAlpha: CGFloat = configuration.highContrast
                    ? 0.95
                    : (configuration.dotLiquidGlassEnabled ? 0.74 : ApplePointerConstants.Material.materialAlphaDot)
                let effectiveDotScale = configuration.dotIntensity + smallBoost * 0.14
                targetIntensity = max(0.35, min(0.98, baseDotAlpha * effectiveDotScale))
                dotVividnessBoost = max(0.0, min(1.0, (configuration.dotIntensity - 1.0) / 0.50))
            } else {
                targetIntensity = configuration.highContrast ? 1.0 : ApplePointerConstants.Material.materialAlphaDot
            }
        }

        // Apple contentOverlayIntensityPressed feedback: pressing a snapped control deepens highlight density
        pressedBlend.step(to: isPressed ? 1.0 : 0.0, dt: dt, parameters: ApplePointerConstants.Springs.pressedScale)
        let clampedPressedBlend = max(0.0, min(1.0, CGFloat(pressedBlend.value)))
        if !isBeam && clampedPressedBlend > 0.001 {
            if isSnapped {
                targetIntensity = min(0.98, targetIntensity + 0.20 * clampedPressedBlend)
            } else if configuration.pointerShapeStyle == .ipadDot {
                targetIntensity = min(0.96, targetIntensity + 0.18 * clampedPressedBlend)
                dotVividnessBoost = min(1.0, dotVividnessBoost + 0.36 * clampedPressedBlend)
            }
        }

        // 4. Ramping & exact Apple slip equation + jump-free mouseRecentering
        let rawDeltaX = modelCursorPosition.x - targetRect.midX
        let rawDeltaY = modelCursorPosition.y - targetRect.midY

        let desiredPosX: Double
        let desiredPosY: Double
        if isSnapped && (mappedSlip.x < 1.0 || mappedSlip.y < 1.0) {
            let idleAfterMove = (timestamp - lastMouseMoveTimestamp) >= ApplePointerConstants.Springs.delayBeforeRecenteringAfterMouseMovement
            if mappedSlip.x < 1.0 {
                if idleAfterMove && !isPressed {
                    recenterShiftX.step(to: Double(rawDeltaX), dt: dt, parameters: ApplePointerConstants.Springs.mouseRecentering)
                }
                let effectiveDeltaX = rawDeltaX - CGFloat(recenterShiftX.value)
                let clampedOffsetX = max(-maxSlip, min(maxSlip, effectiveDeltaX * mappedSlip.x))
                desiredPosX = Double(targetRect.midX + clampedOffsetX)
            } else {
                recenterShiftX.reset(to: 0.0)
                desiredPosX = Double(modelCursorPosition.x)
            }

            if mappedSlip.y < 1.0 {
                if idleAfterMove && !isPressed {
                    recenterShiftY.step(to: Double(rawDeltaY), dt: dt, parameters: ApplePointerConstants.Springs.mouseRecentering)
                }
                let effectiveDeltaY = rawDeltaY - CGFloat(recenterShiftY.value)
                let clampedOffsetY = max(-maxSlip, min(maxSlip, effectiveDeltaY * mappedSlip.y))
                desiredPosY = Double(targetRect.midY + clampedOffsetY)
            } else {
                recenterShiftY.reset(to: 0.0)
                desiredPosY = Double(modelCursorPosition.y)
            }
        } else {
            recenterShiftX.reset(to: 0.0)
            recenterShiftY.reset(to: 0.0)
            desiredPosX = Double(modelCursorPosition.x)
            desiredPosY = Double(modelCursorPosition.y)
        }

        if mappedSlip.x < 1.0 {
            rampingX.reset(to: 1.0)
        } else {
            rampingX.step(to: 0.0, dt: dt, parameters: ApplePointerConstants.Springs.rampingExit)
        }
        if mappedSlip.y < 1.0 {
            rampingY.reset(to: 1.0)
        } else {
            rampingY.step(to: 0.0, dt: dt, parameters: ApplePointerConstants.Springs.rampingExit)
        }

        let posSpringX = SpringParameters.lerp(
            ApplePointerConstants.Springs.systemPosition,
            ApplePointerConstants.Springs.focusedPointerPosition,
            t: rampingX.value
        )
        let posSpringY = SpringParameters.lerp(
            ApplePointerConstants.Springs.systemPosition,
            ApplePointerConstants.Springs.focusedPointerPosition,
            t: rampingY.value
        )

        posX.step(to: desiredPosX, dt: dt, parameters: posSpringX)
        posY.step(to: desiredPosY, dt: dt, parameters: posSpringY)

        // 5. Shape morphing & adaptive arrow / resize / crosshair glyph blend springs
        width.step(to: Double(targetRect.width), dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        height.step(to: Double(targetRect.height), dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        cornerRadius.step(to: Double(targetCornerRadius), dt: dt, parameters: ApplePointerConstants.Springs.standardShape)

        let targetArrowBlend: Double = (configuration.pointerShapeStyle == .appleMouse && !isSnapped && !isResizing && !isCrosshair && !isSpecialCursor) ? 1.0 : 0.0
        let targetResizeBlend: Double = isResizing ? 1.0 : 0.0
        let targetCrosshairBlend: Double = isCrosshair ? 1.0 : 0.0
        let targetSpecialBlend: Double = isSpecialCursor ? 1.0 : 0.0
        let targetAccessoryBlend: Double = (isSnapped && !isBeam && activeAccessory != .none) ? 1.0 : 0.0
        if activeAccessory != .none {
            lastVisibleAccessoryKind = activeAccessory
        }
        arrowBlend.step(to: targetArrowBlend, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        resizeBlend.step(to: targetResizeBlend, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        crosshairBlend.step(to: targetCrosshairBlend, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        specialCursorBlend.step(to: targetSpecialBlend, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        accessoryBlend.step(to: targetAccessoryBlend, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)

        let clampedArrowBlend = max(0.0, min(1.0, CGFloat(arrowBlend.value)))
        let clampedResizeBlend = max(0.0, min(1.0, CGFloat(resizeBlend.value)))
        let clampedCrosshairBlend = max(0.0, min(1.0, CGFloat(crosshairBlend.value)))
        let clampedSpecialBlend = max(0.0, min(1.0, CGFloat(specialCursorBlend.value)))
        let clampedAccessoryBlend = max(0.0, min(1.0, CGFloat(accessoryBlend.value)))
        let effectiveResizeKind: ResizeCursorKind = isResizing
            ? activeResizeKind
            : (clampedResizeBlend > 0.02 ? lastVisibleResizeKind : .none)
        let effectiveSpecialKind: SpecialCursorKind = isSpecialCursor
            ? activeSpecialCursorKind
            : (clampedSpecialBlend > 0.02 ? lastVisibleSpecialCursorKind : .none)
        let effectiveAccessoryKind: PointerAccessoryKind = activeAccessory != .none
            ? activeAccessory
            : (clampedAccessoryBlend > 0.02 ? lastVisibleAccessoryKind : .none)

        // Apple iPadOS 26/27 Liquid Glass rubberband elasticity (plasmaRubberbandFactor):
        // subtle stretch along pull direction while tugging on a snapped control, or along motion vector in free Dot mode.
        let isLiquidGlass = configuration.materialPreset == .liquidGlass
        let isDotLiquidGlass = configuration.dotLiquidGlassEnabled
        let rubberStrength: Double = isLiquidGlass ? 1.0 : 0.0
        var targetElasticX = 1.0
        var targetElasticY = 1.0
        if isLiquidGlass && isSnapped && !isBeam && (mappedSlip.x < 1.0 || mappedSlip.y < 1.0) {
            let halfW = max(Double(targetRect.width) * 0.5, 12.0)
            let halfH = max(Double(targetRect.height) * 0.5, 12.0)
            let pullX = min(1.0, abs(Double(rawDeltaX)) / halfW) * (mappedSlip.x < 1.0 ? 1.0 : 0.0)
            let pullY = min(1.0, abs(Double(rawDeltaY)) / halfH) * (mappedSlip.y < 1.0 ? 1.0 : 0.0)
            let sx = pullX * 0.048 * rubberStrength
            let sy = pullY * 0.048 * rubberStrength
            targetElasticX = 1.0 + sx - sy * 0.45
            targetElasticY = 1.0 + sy - sx * 0.45
        } else if isDotLiquidGlass && !isSnapped && !isResizing && !isCrosshair && !isSpecialCursor && configuration.pointerShapeStyle == .ipadDot {
            let speed = Double(hypot(smoothedVelocity.x, smoothedVelocity.y))
            if speed > 380.0 {
                let factor = min(1.0, (speed - 380.0) / 1600.0) * 0.055
                let nx = abs(Double(smoothedVelocity.x)) / speed
                let ny = abs(Double(smoothedVelocity.y)) / speed
                targetElasticX = 1.0 + factor * (nx - ny * 0.5)
                targetElasticY = 1.0 + factor * (ny - nx * 0.5)
            }
        }
        elasticScaleX.step(to: targetElasticX, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        elasticScaleY.step(to: targetElasticY, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)

        // 6. Material intensity & luma mix
        // Use vibrant content-overlay Liquid Glass on snapped controls/icons so underlying icons & text
        // stay crystal-clear and luminous (never muddy gray), and Plasma glass on free Dot / I-beam / glyphs.
        intensity.step(to: Double(targetIntensity), dt: dt, parameters: ApplePointerConstants.Springs.visibleIntensity)
        let lumaSpring = (isCameraNotchTarget || (isMenuBarTarget && isSystemDarkAppearance))
            ? ApplePointerConstants.Springs.standardShape
            : ApplePointerConstants.Springs.materialTransition
        lumaMix.step(to: effectiveDarkBackground ? 1.0 : 0.0, dt: dt, parameters: lumaSpring)

        let blendedMatrix: PointerColorMatrix
        if isSnapped && !isBeam {
            let baseSnapped = PointerColorMatrix.lerp(
                .contentOverlayLightBackground,
                .contentOverlayDarkBackground,
                t: Float(lumaMix.value)
            )
            blendedMatrix = baseSnapped.applyingPressedContrast(
                isDarkBackground: effectiveDarkBackground,
                isSnapped: true,
                amount: Float(clampedPressedBlend)
            )
        } else {
            let isFreeDot = !isBeam && !isResizing && !isCrosshair && !isSpecialCursor && configuration.pointerShapeStyle == .ipadDot
            let freePreset: MaterialPreset = isFreeDot
                ? (isDotLiquidGlass ? .liquidGlass : .classicIPadOS)
                : configuration.materialPreset
            let lightMatrix = PointerColorMatrix.resolve(
                preset: freePreset,
                isDarkBackground: false,
                highContrast: configuration.highContrast
            )
            let darkMatrix = PointerColorMatrix.resolve(
                preset: freePreset,
                isDarkBackground: true,
                highContrast: configuration.highContrast
            )
            var baseFree = PointerColorMatrix.lerp(lightMatrix, darkMatrix, t: Float(lumaMix.value))
            if !isBeam && clampedPressedBlend > 0.001 {
                if !configuration.highContrast {
                    let lightHC = PointerColorMatrix.resolve(
                        preset: freePreset,
                        isDarkBackground: false,
                        highContrast: true
                    )
                    let darkHC = PointerColorMatrix.resolve(
                        preset: freePreset,
                        isDarkBackground: true,
                        highContrast: true
                    )
                    let hcMatrix = PointerColorMatrix.lerp(lightHC, darkHC, t: Float(lumaMix.value))
                    baseFree = PointerColorMatrix.lerp(baseFree, hcMatrix, t: Float(clampedPressedBlend * 0.65))
                }
                baseFree = baseFree.applyingPressedContrast(
                    isDarkBackground: effectiveDarkBackground,
                    isSnapped: false,
                    amount: Float(clampedPressedBlend)
                )
            }
            blendedMatrix = baseFree
        }

        // 7. Pressed scale
        let targetPressedScale: Double
        if isPressed {
            targetPressedScale = isSnapped && !isBeam
                ? Double(ApplePointerConstants.Effect.underlayingPointerPressedScaleFactor)
                : Double(ApplePointerConstants.Effect.systemPointerPressedScale)
        } else {
            targetPressedScale = 1.0
        }
        pressedScale.step(to: targetPressedScale, dt: dt, parameters: ApplePointerConstants.Springs.pressedScale)

        // 8. Autohide & typing-hide scale, opacity, blur
        if isAutohidden {
            let hideSpring = isHiddenByTyping
                ? SpringParameters(dampingRatio: 1.0, response: 0.14)
                : ApplePointerConstants.Springs.visibleToHidden
            autohideScale.step(
                to: Double(ApplePointerConstants.Springs.visibleToHiddenPointerScale),
                dt: dt,
                parameters: hideSpring
            )
            autohideOpacity.step(to: 0.0, dt: dt, parameters: hideSpring)
            blurRadius.step(
                to: Double(isHiddenByTyping ? 0.5 : ApplePointerConstants.Springs.visibleToHiddenPointerBlurRadius),
                dt: dt,
                parameters: hideSpring
            )
        } else {
            autohideScale.step(to: 1.0, dt: dt, parameters: ApplePointerConstants.Springs.hiddenToVisibleScale)
            autohideOpacity.step(to: 1.0, dt: dt, parameters: ApplePointerConstants.Springs.hiddenToVisible)
            blurRadius.step(to: 0.0, dt: dt, parameters: ApplePointerConstants.Springs.hiddenToVisible)
        }

        // 9. Specular highlight
        let targetSpecularOpacity: Double
        let targetSpecularScale: CGFloat
        if configuration.specularEnabled && isSnapped && !isBeam && overlayStyle != .none {
            let longestSide = max(CGFloat(width.value), CGFloat(height.value))
            let baseMult: CGFloat
            let opacityMult: CGFloat
            switch overlayStyle {
            case .standard:
                baseMult = ApplePointerConstants.Specular.standardLongestSideBaseMultiplier
                opacityMult = ApplePointerConstants.Specular.standardOpacityMultiplier
            case .prominent:
                baseMult = ApplePointerConstants.Specular.prominentLongestSideBaseMultiplier
                opacityMult = ApplePointerConstants.Specular.prominentOpacityMultiplier
            case .none:
                baseMult = 0
                opacityMult = 0
            }
            let factor = max(0.0, min(1.0, longestSide * baseMult))
            targetSpecularOpacity = Double(opacityMult * factor)
            targetSpecularScale = 1.0 + factor
        } else {
            targetSpecularOpacity = 0.0
            targetSpecularScale = 1.0
        }
        specularOpacity.step(to: targetSpecularOpacity, dt: dt, parameters: ApplePointerConstants.Springs.specularOpacity)

        let centerPt = CGPoint(x: posX.value, y: posY.value)
        let specOffset = CGPoint(x: modelCursorPosition.x - centerPt.x, y: modelCursorPosition.y - centerPt.y)

        let targetTiltY: Double = (isSnapped && !isBeam) ? Double(activeTarget?.perspectiveTiltY ?? 0.0) : 0.0
        perspectiveTiltYSpring.step(to: targetTiltY, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)

        let suppressSnappedOutline = isSnapped && !isBeam && (activeTarget?.suppressOutline ?? false)
        let isLargeSnappedTarget = isSnapped && !isBeam
            && !suppressSnappedOutline
            && max(targetRect.width, targetRect.height) >= 110.0
            && min(targetRect.width, targetRect.height) >= 44.0
        innerPointerBlend.step(to: isLargeSnappedTarget ? 1.0 : 0.0, dt: dt, parameters: ApplePointerConstants.Springs.visibleIntensity)
        let clampedInnerPointerAlpha = max(0.0, min(1.0, CGFloat(innerPointerBlend.value)))

        // 10. Soft elevation shadow on lifted Dock icons & compact controls (no distorted backdrop zooming)
        var targetLiftShadow = 0.0
        if isLiquidGlass && isSnapped && !isBeam && !suppressSnappedOutline, let target = activeTarget {
            switch target.kind {
            case .lift:
                targetLiftShadow = isPressed ? 0.14 : 0.24
            case .hover:
                targetLiftShadow = isPressed ? 0.10 : 0.18
            case .highlight:
                let longest = max(targetRect.width, targetRect.height)
                let compactFactor = max(0.35, min(1.0, 140.0 / max(longest, 40.0)))
                targetLiftShadow = (isPressed ? 0.05 : 0.12) * Double(compactFactor)
            case .menuItem, .scrollThumb, .beam:
                break
            }
        }
        liftShadowAlpha.step(to: targetLiftShadow, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)

        // 11. Directional Liquid Glass rim specular (plasmaLensParallaxFactor):
        // tilts the rim highlight toward cursor offset on snapped buttons, or velocity on free Dot.
        var targetRimX = -0.707
        var targetRimY = 0.707
        if isSnapped && !isBeam {
            let dx = Double(specOffset.x)
            let dy = -Double(specOffset.y)
            let mag = hypot(dx, dy)
            if mag > 1.5 {
                let blend = min(1.0, mag / 18.0)
                let nx = dx / mag
                let ny = dy / mag
                targetRimX = (-0.707) * (1.0 - blend) + nx * blend
                targetRimY = (0.707) * (1.0 - blend) + ny * blend
            }
        } else if !isSnapped && !isResizing && !isCrosshair && !isSpecialCursor && configuration.pointerShapeStyle == .ipadDot {
            let vx = Double(smoothedVelocity.x)
            let vy = -Double(smoothedVelocity.y)
            let speed = hypot(vx, vy)
            if speed > 180.0 {
                let blend = min(0.75, (speed - 180.0) / 1400.0)
                targetRimX = (-0.707) * (1.0 - blend) + (vx / speed) * blend
                targetRimY = (0.707) * (1.0 - blend) + (vy / speed) * blend
            }
        }
        rimDirX.step(to: targetRimX, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        rimDirY.step(to: targetRimY, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        let rimNorm = max(0.001, hypot(rimDirX.value, rimDirY.value))
        let rimLightDirection = CGPoint(x: rimDirX.value / rimNorm, y: rimDirY.value / rimNorm)
        let rimSpecularAlpha: CGFloat
        if isBeam || isResizing || isCrosshair || isSpecialCursor || suppressSnappedOutline {
            rimSpecularAlpha = 0.0
        } else if isSnapped && isLiquidGlass && configuration.specularEnabled {
            // Prominent crystalline Liquid Glass rim on snapped controls & Dock icons
            let baseRim: CGFloat = effectiveDarkBackground ? 0.82 : 0.72
            rimSpecularAlpha = min(0.96, baseRim + 0.10 * clampedPressedBlend)
        } else if !isSnapped && configuration.pointerShapeStyle == .ipadDot && isDotLiquidGlass {
            // Keep the Liquid Glass rim active whenever Glass Dot is enabled (even if highlight specular is off)
            // so Glass Dot always looks unmistakably glassy and clearly visible on light & dark backgrounds.
            let baseRim: CGFloat = effectiveDarkBackground ? 0.46 : 0.44
            rimSpecularAlpha = min(0.74, baseRim + 0.18 * clampedPressedBlend)
        } else {
            rimSpecularAlpha = 0.0
        }

        // 12. Smooth 24-ray organic contour morphing for 3D molecular pieces
        let targetOrganicContour = (isSnapped && !isBeam) ? activeTarget?.organicContour : nil
        let wasOrganicActive = contourBlend.value > 0.004
        if targetOrganicContour != nil && !wasOrganicActive {
            let seedR = max(4.0, min(width.value, height.value) * 0.5)
            for i in 0..<contourRadiiSprings.count {
                contourRadiiSprings[i].reset(to: seedR)
            }
        }
        contourBlend.step(to: targetOrganicContour != nil ? 1.0 : 0.0, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
        let organicContourRadii: [CGFloat]?
        if let targetOrganicContour {
            for i in 0..<contourRadiiSprings.count {
                contourRadiiSprings[i].step(to: Double(targetOrganicContour.radii[i]), dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
            }
            organicContourRadii = contourRadiiSprings.map { max(3.5, CGFloat($0.value)) }
        } else if contourBlend.value > 0.004 {
            let fallbackR = max(4.0, Double(dotSize) * 0.5)
            for i in 0..<contourRadiiSprings.count {
                contourRadiiSprings[i].step(to: fallbackR, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
            }
            organicContourRadii = contourRadiiSprings.map { max(3.5, CGFloat($0.value)) }
        } else {
            organicContourRadii = nil
        }

        let totalScale = CGFloat(pressedScale.value * autohideScale.value * shakeScale.value)

        let state = PointerRenderState(
            center: centerPt,
            size: CGSize(width: max(1.0, width.value), height: max(1.0, height.value)),
            cornerRadius: max(0.0, CGFloat(cornerRadius.value)),
            totalScale: totalScale,
            intensity: max(0.0, min(1.0, CGFloat(intensity.value))),
            opacity: max(0.0, min(1.0, CGFloat(autohideOpacity.value))),
            blurRadius: max(0.0, CGFloat(blurRadius.value)),
            colorMatrix: blendedMatrix,
            isDarkBackground: effectiveDarkBackground,
            lumaMix: max(0.0, min(1.0, CGFloat(lumaMix.value))),
            pointerShapeStyle: configuration.pointerShapeStyle,
            materialPreset: configuration.materialPreset,
            isDotLiquidGlass: isDotLiquidGlass,
            pointerSizeMultiplier: activeSizeMultiplier,
            highContrast: configuration.highContrast,
            arrowBlend: clampedArrowBlend,
            resizeKind: effectiveResizeKind,
            resizeBlend: clampedResizeBlend,
            crosshairBlend: clampedCrosshairBlend,
            specialCursorKind: effectiveSpecialKind,
            specialCursorBlend: clampedSpecialBlend,
            accessoryKind: effectiveAccessoryKind,
            accessoryBlend: clampedAccessoryBlend,
            elasticScaleX: max(0.88, min(1.14, CGFloat(elasticScaleX.value))),
            elasticScaleY: max(0.88, min(1.14, CGFloat(elasticScaleY.value))),
            specularAlpha: max(0.0, CGFloat(specularOpacity.value)),
            specularScale: targetSpecularScale,
            specularOffset: specOffset,
            rimSpecularAlpha: rimSpecularAlpha,
            rimLightDirection: rimLightDirection,
            liftShadowAlpha: max(0.0, min(0.5, CGFloat(liftShadowAlpha.value))),
            isSnapped: isSnapped,
            isBeam: isBeam,
            isCrosshair: isCrosshair,
            showCenterDot: configuration.showCenterDot && !isSnapped && !isResizing && !isCrosshair && !isSpecialCursor && configuration.pointerShapeStyle == .ipadDot,
            dotVividnessBoost: dotVividnessBoost,
            perspectiveTiltY: CGFloat(perspectiveTiltYSpring.value),
            innerPointerOffset: specOffset,
            innerPointerAlpha: clampedInnerPointerAlpha,
            suppressSnappedOutline: suppressSnappedOutline,
            organicContourRadii: organicContourRadii
        )

        if let prev = lastSteppedState,
           !isPressed,
           shakeDetector.targetMultiplier <= 1.001,
           (timestamp - lastMouseMoveTimestamp) >= 0.22,
           Self.statesEffectivelyEqual(prev, state) {
            stableFrameCount = min(stableFrameCount + 1, 16)
        } else {
            stableFrameCount = 0
        }
        lastSteppedState = state
        return state
    }

    private static func statesEffectivelyEqual(_ a: PointerRenderState, _ b: PointerRenderState) -> Bool {
        abs(a.center.x - b.center.x) < 0.04
            && abs(a.center.y - b.center.y) < 0.04
            && abs(a.size.width - b.size.width) < 0.04
            && abs(a.size.height - b.size.height) < 0.04
            && abs(a.cornerRadius - b.cornerRadius) < 0.04
            && abs(a.totalScale - b.totalScale) < 0.0015
            && abs(a.intensity - b.intensity) < 0.002
            && abs(a.opacity - b.opacity) < 0.002
            && abs(a.blurRadius - b.blurRadius) < 0.01
            && abs(a.lumaMix - b.lumaMix) < 0.002
            && abs(a.arrowBlend - b.arrowBlend) < 0.002
            && abs(a.resizeBlend - b.resizeBlend) < 0.002
            && abs(a.crosshairBlend - b.crosshairBlend) < 0.002
            && abs(a.specialCursorBlend - b.specialCursorBlend) < 0.002
            && abs(a.accessoryBlend - b.accessoryBlend) < 0.002
            && abs(a.elasticScaleX - b.elasticScaleX) < 0.002
            && abs(a.elasticScaleY - b.elasticScaleY) < 0.002
            && abs(a.specularAlpha - b.specularAlpha) < 0.002
            && abs(a.rimSpecularAlpha - b.rimSpecularAlpha) < 0.002
            && abs(a.rimLightDirection.x - b.rimLightDirection.x) < 0.005
            && abs(a.rimLightDirection.y - b.rimLightDirection.y) < 0.005
            && abs(a.liftShadowAlpha - b.liftShadowAlpha) < 0.002
            && abs(a.dotVividnessBoost - b.dotVividnessBoost) < 0.002
            && abs(a.colorMatrix.m15 - b.colorMatrix.m15) < 0.001
            && abs(a.colorMatrix.m45 - b.colorMatrix.m45) < 0.001
            && abs(a.perspectiveTiltY - b.perspectiveTiltY) < 0.002
            && abs(a.innerPointerAlpha - b.innerPointerAlpha) < 0.002
            && (a.innerPointerAlpha < 0.01 || (abs(a.innerPointerOffset.x - b.innerPointerOffset.x) < 0.05 && abs(a.innerPointerOffset.y - b.innerPointerOffset.y) < 0.05))
            && a.isSnapped == b.isSnapped
            && a.isBeam == b.isBeam
            && a.isDarkBackground == b.isDarkBackground
            && a.materialPreset == b.materialPreset
            && a.isDotLiquidGlass == b.isDotLiquidGlass
            && a.pointerShapeStyle == b.pointerShapeStyle
            && a.resizeKind == b.resizeKind
            && a.specialCursorKind == b.specialCursorKind
            && a.accessoryKind == b.accessoryKind
            && a.showCenterDot == b.showCenterDot
            && a.suppressSnappedOutline == b.suppressSnappedOutline
            && Self.contoursEffectivelyEqual(a.organicContourRadii, b.organicContourRadii)
    }

    private static func contoursEffectivelyEqual(_ a: [CGFloat]?, _ b: [CGFloat]?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (.some(ra), .some(rb)) where ra.count == rb.count:
            for i in 0..<ra.count where abs(ra[i] - rb[i]) >= 0.05 {
                return false
            }
            return true
        default:
            return false
        }
    }

    /// Exact Apple `UIPointerStyle._pointerSlipFactor` + `_pointerSlipMappedToRegionSize:`.
    public static func mappedPointerSlip(
        shapeSize: CGSize,
        regionSize: CGSize,
        slipFactorX: CGFloat,
        slipFactorY: CGFloat,
        maxSlipPoints: CGFloat,
        overrideSlipPoints: CGPoint? = nil
    ) -> CGPoint {
        let ptsX: CGFloat
        let ptsY: CGFloat
        if let ov = overrideSlipPoints {
            ptsX = max(0.0, ov.x)
            ptsY = max(0.0, ov.y)
        } else {
            ptsX = max(0.0, min(shapeSize.width * slipFactorX, maxSlipPoints))
            ptsY = max(0.0, min(shapeSize.height * slipFactorY, maxSlipPoints))
        }
        let mappedX = min(ptsX / max(regionSize.width * 0.5, 1.0), 1.0)
        let mappedY = min(ptsY / max(regionSize.height * 0.5, 1.0), 1.0)
        return CGPoint(x: mappedX, y: mappedY)
    }

    /// Exact Apple `UIPointerStyle.contentScale` calculation from `UIKitCore`.
    public static func contentScale(for size: CGSize, scaleUpPoints: CGFloat) -> CGFloat {
        let maxDim = max(size.width, size.height)
        guard maxDim > 0, scaleUpPoints > 0 else { return 1.0 }
        return (maxDim + scaleUpPoints) / maxDim
    }

    /// Exact Apple `flexibleRectIntensityReductionRange` calculation from `pointeruid` (0x1000203a0..0x1000204d4).
    public static func flexibleRectIntensity(
        for size: CGSize,
        isDarkBackground: Bool,
        visualIntensity: CGFloat? = nil
    ) -> CGFloat {
        let base = visualIntensity ?? (
            isDarkBackground
                ? ApplePointerConstants.Material.materialAlphaSmallItemLight
                : ApplePointerConstants.Material.materialAlphaSmallItemDark
        )
        let maxAllowed = min(1.0, base + ApplePointerConstants.Material.flexibleRectIntensityBaseBoost)

        let minFlex = isDarkBackground
            ? ApplePointerConstants.Material.minFlexibleRectLightLuminanceIntensity
            : ApplePointerConstants.Material.minFlexibleRectDarkLuminanceIntensity

        let longestSide = max(size.width, size.height)
        let minSize = ApplePointerConstants.Geometry.systemPointerSize * ApplePointerConstants.Effect.systemPointerPressedScale
        let t = (longestSide - minSize) / ApplePointerConstants.Material.flexibleRectIntensityReductionRange
        let lerped = (1.0 - t) * 1.0 + t * minFlex
        return max(minFlex, min(lerped, maxAllowed))
    }
}

/// Apple iPadOS-inspired smooth animated typing caret (crisp typing glide + taut spring jumps between text chunks).
public final class SmoothCaretEngine: @unchecked Sendable {
    private static let caretSpring = SpringParameters(dampingRatio: 1.0, response: 0.082)
    private static let jumpSpring = SpringParameters(dampingRatio: 0.92, response: 0.125)
    private static let fadeInSpring = SpringParameters(dampingRatio: 1.0, response: 0.028)
    private static let fadeOutSpring = SpringParameters(dampingRatio: 1.0, response: 0.12)

    private var posX = Spring1D(value: 0)
    private var posY = Spring1D(value: 0)
    private var height = Spring1D(value: 18)
    private var presenceOpacity = Spring1D(value: 0)

    private var targetRect: CGRect?
    private var lastGlideStartTimestamp: TimeInterval = -.infinity
    private var lastValidCaretTimestamp: TimeInterval = -.infinity
    private var consecutiveNilCount: Int = 0
    private var hasSeeded = false
    private var glideActive = false
    private var isChunkJump = false

    public init() {}

    @discardableResult
    public func updateTargetCaret(
        _ rect: CGRect?,
        at timestamp: TimeInterval,
        source: CaretMoveSource = .typing
    ) -> Bool {
        guard let rect, rect.height >= 10.0, rect.height <= 64.0, rect.minX.isFinite, rect.minY.isFinite else {
            consecutiveNilCount += 1
            let expired = (timestamp - lastValidCaretTimestamp) > 0.65
            if source == .mouseClick || consecutiveNilCount >= 3 || expired {
                targetRect = nil
                hasSeeded = false
                glideActive = false
            }
            return glideActive
        }
        consecutiveNilCount = 0
        lastValidCaretTimestamp = timestamp

        if let prev = targetRect {
            let dx = abs(rect.minX - prev.minX)
            let dy = abs(rect.midY - prev.midY)
            let moved = dx > 0.5 || dy > 0.5
            guard moved else {
                targetRect = rect
                return glideActive
            }

            let sameLine = dy <= max(rect.height * 0.65, 14.0)
            let jumpDistance = hypot(dx, dy)
            let shouldGlide: Bool
            let chunkJump: Bool
            switch source {
            case .mouseClick:
                // Clicking another word, line, or paragraph within local reading context glides with
                // Apple's taut spring jump; giant cross-screen teleports (> 520pt) snap instantly.
                shouldGlide = jumpDistance <= 520.0
                chunkJump = !sameLine || dx > 48.0
            case .typing, .keyboardNavigation:
                shouldGlide = jumpDistance <= 520.0
                chunkJump = !sameLine || dx > 48.0
            }

            if shouldGlide {
                lastGlideStartTimestamp = timestamp
                glideActive = true
                isChunkJump = chunkJump
            } else {
                posX.reset(to: Double(rect.minX))
                posY.reset(to: Double(rect.midY))
                height.reset(to: Double(rect.height))
                glideActive = false
                isChunkJump = false
                presenceOpacity.reset(to: 0.0)
            }
        } else {
            posX.reset(to: Double(rect.minX))
            posY.reset(to: Double(rect.midY))
            height.reset(to: Double(rect.height))
            glideActive = false
            isChunkJump = false
            presenceOpacity.reset(to: 0.0)
            hasSeeded = true
        }
        targetRect = rect
        return glideActive
    }

    public func reset() {
        targetRect = nil
        lastValidCaretTimestamp = -.infinity
        consecutiveNilCount = 0
        hasSeeded = false
        glideActive = false
        isChunkJump = false
        presenceOpacity.reset(to: 0.0)
    }

    public func step(
        dt: TimeInterval,
        timestamp: TimeInterval,
        enabled: Bool,
        isDarkBackground: Bool = false
    ) -> SmoothCaretRenderState {
        guard enabled, hasSeeded, let target = targetRect else {
            glideActive = false
            presenceOpacity.step(to: 0.0, dt: dt, parameters: Self.fadeOutSpring)
            return .hidden
        }

        if glideActive {
            let activeSpring = isChunkJump ? Self.jumpSpring : Self.caretSpring
            posX.step(to: Double(target.minX), dt: dt, parameters: activeSpring)
            posY.step(to: Double(target.midY), dt: dt, parameters: activeSpring)
            height.step(to: Double(target.height), dt: dt, parameters: activeSpring)
        }

        let distToTarget = hypot(CGFloat(posX.value) - target.minX, CGFloat(posY.value) - target.midY)
        let timeSinceGlideStart = timestamp - lastGlideStartTimestamp
        let minHold: TimeInterval = isChunkJump ? 0.34 : 0.26
        let stillAnimating = glideActive && (distToTarget > 0.45 || timeSinceGlideStart < minHold)
        if glideActive && !stillAnimating {
            glideActive = false
        }

        let active = stillAnimating
        presenceOpacity.step(to: active ? 1.0 : 0.0, dt: dt, parameters: active ? Self.fadeInSpring : Self.fadeOutSpring)

        let baseAlpha = max(0.0, min(1.0, CGFloat(presenceOpacity.value)))
        guard baseAlpha > 0.01 else {
            return .hidden
        }

        let h = max(10.0, CGFloat(height.value))
        let w: CGFloat = 2.5
        let rendered = CGRect(x: CGFloat(posX.value) - w * 0.5, y: CGFloat(posY.value) - h * 0.5, width: w, height: h)
        return SmoothCaretRenderState(
            rect: rendered,
            opacity: baseAlpha * 0.96,
            isVisible: true,
            isDarkBackground: isDarkBackground
        )
    }
}
