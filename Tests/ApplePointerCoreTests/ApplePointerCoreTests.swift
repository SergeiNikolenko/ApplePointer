import CoreGraphics
import Foundation
import Testing
@testable import ApplePointerCore

@Suite("ApplePointerCore Exact Apple Parity Tests")
struct ApplePointerCoreTests {
    @Test("Exact Apple constants match extracted binary defaults")
    func exactAppleConstants() {
        #expect(ApplePointerConstants.Geometry.systemPointerSize == 19.0)
        #expect(ApplePointerConstants.Geometry.axLargeSystemPointerCenterDotSize == 9.5)
        #expect(ApplePointerConstants.Geometry.defaultPointerCornerRadius == 8.0)
        #expect(ApplePointerConstants.Geometry.beamWidth == 3.0)
        #expect(ApplePointerConstants.Geometry.beamMinLength == 24.0)
        #expect(ApplePointerConstants.Geometry.beamMaxLength == 100.0)
        #expect(ApplePointerConstants.Geometry.beamMaxSnapLength == 100.0)
        #expect(ApplePointerConstants.Geometry.textLineRegionPadding == 10.0)

        #expect(ApplePointerConstants.SizeRule.explicitRequestMultiplier == 1.4)
        #expect(ApplePointerConstants.SizeRule.genericSizeRuleThreshold == 125.0)
        #expect(ApplePointerConstants.SizeRule.narrowAspectRuleMinorDimensionThreshold == 50.0)
        #expect(ApplePointerConstants.SizeRule.narrowAspectRuleMajorDimensionThreshold == 180.0)
        #expect(ApplePointerConstants.SizeRule.pointerSizeRuleMinorDimensionThreshold == 19.0)
        #expect(ApplePointerConstants.SizeRule.pointerSizeRuleMajorDimensionThreshold == 320.0)

        #expect(ApplePointerConstants.ControlBehavior.textButtonOutsetLeading == 10.0)
        #expect(ApplePointerConstants.ControlBehavior.textButtonOutsetTop == 7.5)
        #expect(ApplePointerConstants.ControlBehavior.textButtonOutsetBottom == 8.5)
        #expect(ApplePointerConstants.ControlBehavior.imageButtonOutset == 8.0)
        #expect(ApplePointerConstants.ControlBehavior.navToolbarCornerRadius == 8.0)

        #expect(ApplePointerConstants.Springs.standardShape == SpringParameters(dampingRatio: 0.9, response: 0.175))
        #expect(ApplePointerConstants.Springs.systemPosition == SpringParameters(dampingRatio: 1.0, response: 0.017))
        #expect(ApplePointerConstants.Springs.focusedPointerPosition == SpringParameters(dampingRatio: 1.0, response: 0.14))
        #expect(ApplePointerConstants.Springs.rampingExit == SpringParameters(dampingRatio: 1.0, response: 0.125))
        #expect(ApplePointerConstants.Springs.pressedScale == SpringParameters(dampingRatio: 1.0, response: 0.11))
        #expect(ApplePointerConstants.Springs.specularOpacity == SpringParameters(dampingRatio: 1.0, response: 0.17))

        #expect(ApplePointerConstants.Material.materialAlphaDot == 0.85)
        #expect(ApplePointerConstants.Material.materialAlphaIBeam == 1.0)
        #expect(ApplePointerConstants.Material.materialAlphaSmallItemLight == 0.25)
        #expect(ApplePointerConstants.Material.materialAlphaSmallItemDark == 0.30)
        #expect(ApplePointerConstants.Material.flexibleRectIntensityReductionRange == 300.0)
        #expect(ApplePointerConstants.Material.flexibleRectIntensityBaseBoost == 0.15)
        #expect(ApplePointerConstants.Material.minFlexibleRectDarkLuminanceIntensity == 0.25)
        #expect(ApplePointerConstants.Material.minFlexibleRectLightLuminanceIntensity == 0.325)
        #expect(ApplePointerConstants.Material.contentOverlayIntensityNormal == 0.5)
        #expect(ApplePointerConstants.Material.contentOverlayIntensityPressed == 0.9)

        #expect(ApplePointerConstants.Effect.highlightSlipX == 0.099)
        #expect(ApplePointerConstants.Effect.highlightSlipY == 0.09)
        #expect(ApplePointerConstants.Effect.highlightMaxSlipPoints == 15.0)
        #expect(ApplePointerConstants.Effect.liftSlipX == 0.055)
        #expect(ApplePointerConstants.Effect.liftSlipY == 0.055)
        #expect(ApplePointerConstants.Effect.sbAppIconScaleUpPoints == 9.5)
        #expect(ApplePointerConstants.Effect.sbAppIconOverrideSlipPoints == 4.5)
        #expect(ApplePointerConstants.Effect.systemPointerPressedScale == 0.9)
        #expect(ApplePointerConstants.Effect.underlayingPointerPressedScaleFactor == 1.02)

        #expect(ApplePointerConstants.Specular.standardOpacityMultiplier == 0.0475)
        #expect(ApplePointerConstants.Specular.prominentOpacityMultiplier == 0.08)
        #expect(ApplePointerConstants.Specular.radialStops.count == 11)
    }

    @Test("Analytical Spring1D stays stable at 60Hz and 120Hz for stiff response 0.017 and standardShape")
    func springStability() {
        for dt in [1.0 / 60.0, 1.0 / 120.0] {
            var stiff = Spring1D(value: 0.0)
            var prevDist = 100.0
            for _ in 0..<20 {
                stiff.step(to: 100.0, dt: dt, parameters: ApplePointerConstants.Springs.systemPosition)
                #expect(stiff.value.isFinite)
                #expect(stiff.velocity.isFinite)
                let dist = abs(100.0 - stiff.value)
                #expect(dist <= prevDist + 1e-9)
                prevDist = dist
            }
            #expect(abs(100.0 - stiff.value) < 1e-3)

            var shape = Spring1D(value: 19.0)
            let steps = Int(round(0.8 / dt))
            for _ in 0..<steps {
                shape.step(to: 120.0, dt: dt, parameters: ApplePointerConstants.Springs.standardShape)
                #expect(shape.value.isFinite)
            }
            #expect(abs(120.0 - shape.value) < 1e-3)
        }
    }

    @Test("Exact Apple mappedPointerSlip, maxSlipPoints clamping, and Dock overrideSlipPoints")
    func mappedSlipAndOverrideSlip() {
        // Highlight on 100x50 button: pts = (9.9, 4.5), mappedSlip = (9.9/50, 4.5/25) = (0.198, 0.18)
        let mappedHighlight = PointerEngine.mappedPointerSlip(
            shapeSize: CGSize(width: 100, height: 50),
            regionSize: CGSize(width: 100, height: 50),
            slipFactorX: 0.099,
            slipFactorY: 0.09,
            maxSlipPoints: 15.0
        )
        #expect(abs(mappedHighlight.x - 0.198) < 1e-6)
        #expect(abs(mappedHighlight.y - 0.18) < 1e-6)

        // Dock 60x60 with overrideSlipPoints = 4.5 -> mapped = 4.5 / 30 = 0.15
        let mappedDock = PointerEngine.mappedPointerSlip(
            shapeSize: CGSize(width: 69.5, height: 69.5),
            regionSize: CGSize(width: 60, height: 60),
            slipFactorX: 0.055,
            slipFactorY: 0.055,
            maxSlipPoints: 15.0,
            overrideSlipPoints: CGPoint(x: 4.5, y: 4.5)
        )
        #expect(abs(mappedDock.x - 0.15) < 1e-6)
        #expect(abs(mappedDock.y - 0.15) < 1e-6)

        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 1.0)
        let target = HitTarget(
            id: "btn",
            rect: CGRect(x: 50, y: 75, width: 100, height: 50), // center (100, 100)
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(target, at: 1.0)

        // Edge of 100x50 button: +50pt in X, +25pt in Y -> shifts by +9.9pt and +4.5pt
        var t = 1.0
        for i in 1...180 {
            t = 1.0 + Double(i) * (1.0 / 120.0)
            let jitter: CGFloat = (i % 2 == 0) ? 0.35 : -0.35
            engine.updatePointerPosition(CGPoint(x: 150 + jitter, y: 125), timestamp: t)
            _ = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        engine.updatePointerPosition(CGPoint(x: 150, y: 125), timestamp: t + 0.001)
        let settled = engine.step(dt: 1.0 / 120.0, timestamp: t + 0.001)
        #expect(abs(settled.center.x - 109.9) < 0.15)
        #expect(abs(settled.center.y - 104.5) < 0.15)

        // Wide 300x60 button: 300 * 0.099 = 29.7 -> clamped to maxSlipPoints = 15.0
        // mappedX = 15.0 / 150.0 = 0.10 -> at edge (+150pt) shifts by +15.0pt (center 150 -> 165)
        let wideTarget = HitTarget(
            id: "wide",
            rect: CGRect(x: 0, y: 0, width: 300, height: 60), // center (150, 30)
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        )
        engine.updatePointerPosition(CGPoint(x: 150, y: 30), timestamp: t + 0.002)
        engine.updateHitTarget(wideTarget, at: t + 0.002)
        for i in 1...180 {
            t += 1.0 / 120.0
            let jitter: CGFloat = (i % 2 == 0) ? 0.35 : -0.35
            engine.updatePointerPosition(CGPoint(x: 300 + jitter, y: 30), timestamp: t)
            _ = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        let clampedState = engine.step(dt: 1.0 / 120.0, timestamp: t)
        #expect(abs(clampedState.center.x - 165.0) < 0.15)

        // Dock 60x60 lift item with overrideSlipPoints = 4.5 -> at edge (+30pt) shifts by +4.5pt (center 50 -> 54.5)
        let dockTarget = HitTarget(
            id: "dock",
            rect: CGRect(x: 20, y: 20, width: 60, height: 60), // center (50, 50)
            cornerRadius: 13.4,
            kind: .lift,
            slipX: 0.055,
            slipY: 0.055,
            maxSlipPoints: 15.0,
            overrideSlipPoints: CGPoint(x: 4.5, y: 4.5),
            scaleUpPoints: 9.5,
            overlayEffectStyle: .prominent
        )
        engine.updatePointerPosition(CGPoint(x: 50, y: 50), timestamp: t + 0.002)
        engine.updateHitTarget(dockTarget, at: t + 0.002)
        for i in 1...180 {
            t += 1.0 / 120.0
            let jitter: CGFloat = (i % 2 == 0) ? 0.35 : -0.35
            engine.updatePointerPosition(CGPoint(x: 80 + jitter, y: 50), timestamp: t)
            _ = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        let dockState = engine.step(dt: 1.0 / 120.0, timestamp: t)
        #expect(abs(dockState.center.x - 54.5) < 0.15)
    }

    @Test("Jump-free mouseRecentering pulls to center and continues smoothly on next move")
    func jumpFreeMouseRecentering() {
        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0.0)
        let target = HitTarget(
            id: "btn",
            rect: CGRect(x: 50, y: 75, width: 100, height: 50), // center (100, 100), mappedSlipX = 0.198
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(target, at: 0.0)

        var t = 0.0
        for i in 1...150 {
            t = Double(i) / 120.0
            let jitter: CGFloat = (i % 2 == 0) ? 0.35 : -0.35
            engine.updatePointerPosition(CGPoint(x: 140 + jitter, y: 100), timestamp: t)
            _ = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        let beforeIdle = engine.step(dt: 1.0 / 120.0, timestamp: t)
        #expect(beforeIdle.center.x > 107.0)

        // Pause > 0.04s for 1.5s -> mouseRecentering pulls smoothly back to center (100.0)
        for _ in 1...180 {
            t += 1.0 / 120.0
            _ = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        let recentered = engine.step(dt: 1.0 / 120.0, timestamp: t)
        #expect(abs(recentered.center.x - 100.0) < 0.1)

        // Subsequent 2pt mouse move must NOT jump back toward 107.92!
        t += 1.0 / 120.0
        engine.updatePointerPosition(CGPoint(x: 142, y: 100), timestamp: t)
        let afterTinyMove = engine.step(dt: 1.0 / 120.0, timestamp: t)
        #expect(abs(afterTinyMove.center.x - 100.0) < 1.0)

        // Stepping 1s with micro-jitter settles smoothly around +2pt * 0.198 = 100.396
        for i in 1...120 {
            t += 1.0 / 120.0
            let jitter: CGFloat = (i % 2 == 0) ? 0.35 : -0.35
            engine.updatePointerPosition(CGPoint(x: 142 + jitter, y: 100), timestamp: t)
            _ = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        let settledAfterTinyMove = engine.step(dt: 1.0 / 120.0, timestamp: t)
        #expect(abs(settledAfterTinyMove.center.x - 100.396) < 0.25)
    }

    @Test("Lift uses Apple contentScale while Highlight preserves uninflated bounds")
    func liftContentScaleVsHighlight() {
        let engine = PointerEngine(initialPosition: CGPoint(x: 50, y: 50), timestamp: 0)
        let dockTarget = HitTarget(
            id: "dock",
            rect: CGRect(x: 20, y: 20, width: 60, height: 60),
            cornerRadius: 13.4,
            kind: .lift,
            slipX: 0.055,
            slipY: 0.055,
            maxSlipPoints: 15.0,
            overrideSlipPoints: CGPoint(x: 4.5, y: 4.5),
            scaleUpPoints: 9.5,
            overlayEffectStyle: .prominent
        )
        engine.updateHitTarget(dockTarget, at: 0)

        var state: PointerRenderState!
        for i in 1...180 {
            state = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(abs(state.size.width - 69.5) < 0.05)
        #expect(abs(state.size.height - 69.5) < 0.05)

        let highlightTarget = HitTarget(
            id: "btn",
            rect: CGRect(x: 0, y: 25, width: 100, height: 50),
            cornerRadius: 8.0,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            scaleUpPoints: 4.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(highlightTarget, at: 2.0)
        for i in 181...400 {
            state = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(abs(state.size.width - 100.0) < 0.05)
        #expect(abs(state.size.height - 50.0) < 0.05)
    }

    @Test("Ramping exit decays smoothly from focusedPointerPosition to systemPosition")
    func rampingExitBehavior() {
        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0)
        let target = HitTarget(
            id: "btn",
            rect: CGRect(x: 80, y: 80, width: 40, height: 40),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(target, at: 0)
        _ = engine.step(dt: 1.0 / 120.0, timestamp: 1.0 / 120.0)

        engine.updateHitTarget(nil, at: 2.0 / 120.0)
        engine.updatePointerPosition(CGPoint(x: 200, y: 100), timestamp: 2.0 / 120.0)
        let firstExitFrame = engine.step(dt: 1.0 / 120.0, timestamp: 2.0 / 120.0)
        #expect(firstExitFrame.center.x < 120.0)

        var last = firstExitFrame
        for i in 3...60 {
            let t = Double(i) / 120.0
            last = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        #expect(abs(last.center.x - 200.0) < 0.5)
    }

    @Test("SizeRuleEvaluator honors exact Apple 125, 50x180, 19x320 and 1.4x rules")
    func sizeRuleEligibility() {
        #expect(SizeRuleEvaluator.isEligible(size: CGSize(width: 80, height: 32), explicitControl: false))
        #expect(SizeRuleEvaluator.isEligible(size: CGSize(width: 125, height: 125), explicitControl: false))
        #expect(SizeRuleEvaluator.isEligible(size: CGSize(width: 180, height: 50), explicitControl: false))
        #expect(SizeRuleEvaluator.isEligible(size: CGSize(width: 320, height: 19), explicitControl: false))

        // 60x170 and 120x170 fail implicit rules (60 > 50, 170 > 125), pass explicit 1.4x (generic = 175)
        #expect(!SizeRuleEvaluator.isEligible(size: CGSize(width: 170, height: 60), explicitControl: false))
        #expect(SizeRuleEvaluator.isEligible(size: CGSize(width: 170, height: 60), explicitControl: true))
        #expect(!SizeRuleEvaluator.isEligible(size: CGSize(width: 170, height: 120), explicitControl: false))
        #expect(SizeRuleEvaluator.isEligible(size: CGSize(width: 170, height: 120), explicitControl: true))

        // 25x400 passes explicit pointer-size rule (19*1.4=26.6, 320*1.4=448), fails implicit
        #expect(!SizeRuleEvaluator.isEligible(size: CGSize(width: 400, height: 25), explicitControl: false))
        #expect(SizeRuleEvaluator.isEligible(size: CGSize(width: 400, height: 25), explicitControl: true))

        #expect(!SizeRuleEvaluator.isEligible(size: CGSize(width: 300, height: 30), explicitControl: true))
        #expect(!SizeRuleEvaluator.isEligible(size: CGSize(width: 400, height: 400), explicitControl: true))
    }

    @Test("FlexibleRect intensity reduction over 300pt range matches Apple SmallItem + pointeruid formula")
    func flexibleRectIntensityReduction() {
        // Small target (36x36) -> capped at visualIntensity + 0.15 = 0.45 (light bg) / 0.40 (dark bg)
        let smallLightBg = PointerEngine.flexibleRectIntensity(for: CGSize(width: 36, height: 36), isDarkBackground: false)
        let smallDarkBg = PointerEngine.flexibleRectIntensity(for: CGSize(width: 36, height: 36), isDarkBackground: true)
        #expect(abs(smallLightBg - 0.45) < 1e-4)
        #expect(abs(smallDarkBg - 0.40) < 1e-4)

        // Very large target (>= 317.1pt) -> minFlexibleRectDark (0.25) on light bg, minFlexibleRectLight (0.325) on dark bg
        let largeLightBg = PointerEngine.flexibleRectIntensity(for: CGSize(width: 350, height: 40), isDarkBackground: false)
        let largeDarkBg = PointerEngine.flexibleRectIntensity(for: CGSize(width: 350, height: 40), isDarkBackground: true)
        #expect(abs(largeLightBg - 0.25) < 1e-4)
        #expect(abs(largeDarkBg - 0.325) < 1e-4)

        // Uncapped explicit baseIntensity 1.0 -> mid target (167.1pt = halfway across 300pt) -> 0.625 on light bg
        let midUncapped = PointerEngine.flexibleRectIntensity(for: CGSize(width: 167.1, height: 32), isDarkBackground: false, visualIntensity: 1.0)
        #expect(abs(midUncapped - 0.625) < 1e-4)

        // Verify PointerEngine.step() passes SmallItem visualIntensity (0.45 light / 0.40 dark) for snapped button
        let engine = PointerEngine(initialPosition: CGPoint(x: 50, y: 50), timestamp: 0)
        engine.updateHitTarget(HitTarget(
            id: "btn",
            rect: CGRect(x: 32, y: 32, width: 36, height: 36),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        ), at: 0)
        var s: PointerRenderState!
        for i in 1...180 {
            s = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(abs(s.intensity - 0.72) < 0.02)

        engine.updateBackgroundLuma(0.2)
        for i in 181...360 {
            s = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(abs(s.intensity - 0.67) < 0.02)
    }

    @Test("Specular highlight alpha and scale follow standard and prominent multipliers")
    func specularHighlightMath() {
        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0)
        let dockTarget = HitTarget(
            id: "dock",
            rect: CGRect(x: 70, y: 70, width: 60, height: 60),
            cornerRadius: 13,
            kind: .lift,
            slipX: 0.055,
            slipY: 0.055,
            maxSlipPoints: 15.0,
            overrideSlipPoints: CGPoint(x: 4.5, y: 4.5),
            scaleUpPoints: 9.5,
            overlayEffectStyle: .prominent
        )
        engine.updateHitTarget(dockTarget, at: 0)

        var state: PointerRenderState!
        for i in 1...180 {
            state = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(abs(state.specularScale - 2.0) < 1e-3)
        #expect(abs(state.specularAlpha - 0.08) < 1e-3)

        let tinyTarget = HitTarget(
            id: "tiny",
            rect: CGRect(x: 95, y: 95, width: 10, height: 10),
            cornerRadius: 5,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(tinyTarget, at: 2.0)
        for i in 181...400 {
            state = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(abs(state.specularScale - 1.5) < 0.02)
        #expect(abs(state.specularAlpha - 0.02375) < 0.002)
    }

    @Test("Luma hysteresis and ColorMatrix including PSContentOverlayVibrantColorMatrixForLuminance")
    func lumaHysteresisAndColorMatrix() {
        let engine = PointerEngine()
        #expect(!engine.isDarkBackground)

        engine.updateBackgroundLuma(0.50)
        #expect(!engine.isDarkBackground)

        engine.updateBackgroundLuma(0.40)
        #expect(engine.isDarkBackground)

        engine.updateBackgroundLuma(0.52)
        #expect(engine.isDarkBackground)

        engine.updateBackgroundLuma(0.60)
        #expect(!engine.isDarkBackground)

        let a = PointerColorMatrix.classicLightBackground
        let b = PointerColorMatrix.classicDarkBackground
        let mid = PointerColorMatrix.lerp(a, b, t: 0.5)
        #expect(abs(mid.m15 - (a.m15 + b.m15) * 0.5) < 1e-6)
        #expect(abs(mid.m45 - (a.m45 + b.m45) * 0.5) < 1e-6)

        #expect(abs(PointerColorMatrix.contentOverlayLightBackground.m11 - 0.8402) < 1e-6)
        #expect(abs(PointerColorMatrix.contentOverlayLightBackground.m15 - 0.05) < 1e-6)
        #expect(abs(PointerColorMatrix.contentOverlayDarkBackground.m11 - 0.9304) < 1e-6)
        #expect(abs(PointerColorMatrix.contentOverlayDarkBackground.m45 - (-0.6)) < 1e-6)
    }

    @Test("Rejects stale targets, scroll-cooldown targets, and drag-time snaps")
    func staleScrollAndDragGuards() {
        let engine = PointerEngine(initialPosition: CGPoint(x: 300, y: 300), timestamp: 1.0)
        let farTarget = HitTarget(
            id: "far",
            rect: CGRect(x: 0, y: 0, width: 50, height: 50),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(farTarget, at: 1.0)
        #expect(engine.currentTarget == nil)

        // Snap while inside target, then scroll -> clears target and ignores targets during scroll cooldown
        let nearTarget = HitTarget(
            id: "near",
            rect: CGRect(x: 280, y: 280, width: 40, height: 40),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(nearTarget, at: 2.0)
        #expect(engine.currentTarget?.id == "near")

        engine.registerScrollOrActivity(timestamp: 2.1)
        #expect(engine.currentTarget == nil)

        engine.updateHitTarget(nearTarget, at: 2.15) // within 0.15s cooldown
        #expect(engine.currentTarget == nil)

        engine.updateHitTarget(nearTarget, at: 2.30) // after cooldown
        #expect(engine.currentTarget?.id == "near")

        // Reject entering new target while dragging (isPressed = true)
        engine.updatePointerPosition(CGPoint(x: 400, y: 400), timestamp: 3.0)
        #expect(engine.currentTarget == nil)
        engine.setPressed(true, timestamp: 3.01)
        let dragTarget = HitTarget(
            id: "drag",
            rect: CGRect(x: 380, y: 380, width: 40, height: 40),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 15.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(dragTarget, at: 3.02)
        #expect(engine.currentTarget == nil)
    }

    @Test("Autohide hide/wake transitions and ShakeToFindDetector")
    func autohideAndShakeToFind() {
        var config = PointerConfiguration()
        config.autohideDuration = 2.0
        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0.0, configuration: config)

        var state = engine.step(dt: 0.016, timestamp: 2.1)
        #expect(engine.isAutohidden)
        for i in 1...120 {
            state = engine.step(dt: 0.016, timestamp: 2.1 + Double(i) * 0.016)
        }
        #expect(state.opacity < 0.01)
        #expect(abs(state.blurRadius - 1.5) < 0.05)
        #expect(abs(state.totalScale - 0.96) < 0.01)

        engine.updatePointerPosition(CGPoint(x: 110, y: 100), timestamp: 5.0)
        #expect(!engine.isAutohidden)
        let wakeState = engine.step(dt: 0.001, timestamp: 5.001)
        #expect(wakeState.totalScale > 1.5)
        #expect(wakeState.blurRadius > 8.0)

        var detector = ShakeToFindDetector()
        var ts = 10.0
        for i in 0..<12 {
            let x: CGFloat = (i % 2 == 0) ? 100 : 250
            detector.recordMove(point: CGPoint(x: x, y: 100), timestamp: ts)
            ts += 0.03
        }
        #expect(detector.targetMultiplier > 1.0)
        detector.update(at: ts + 0.25)
        #expect(detector.targetMultiplier == 1.0)
    }

    @Test("CursorHideSafetyPolicy prevents cursor lockout on missing heartbeat, prompts, and pauses")
    func cursorHideSafetyPolicyGuards() {
        let validState = CursorHideSafetyPolicy.State(
            enabled: true,
            overlayActive: true,
            nativeResizeCursorActive: false,
            pausedForPermissionSetup: false,
            frontmostBundleID: "com.apple.Safari",
            lastRenderedFrameUptime: 100.0,
            currentUptime: 100.1,
            suppressHidingByEnvironment: false
        )
        #expect(CursorHideSafetyPolicy.shouldHideSystemCursor(validState))

        // Must NOT hide before the first rendered overlay frame
        var noHeartbeat = validState
        noHeartbeat.lastRenderedFrameUptime = nil
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(noHeartbeat))

        // Dead-man's switch: must restore native cursor if heartbeat is older than 0.5s
        var staleHeartbeat = validState
        staleHeartbeat.currentUptime = 100.51
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(staleHeartbeat))

        // Boundary <= 0.5s remains allowed
        var boundaryHeartbeat = validState
        boundaryHeartbeat.currentUptime = 100.5
        #expect(CursorHideSafetyPolicy.shouldHideSystemCursor(boundaryHeartbeat))

        // Must NOT hide when overlay is inactive
        var inactiveOverlay = validState
        inactiveOverlay.overlayActive = false
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(inactiveOverlay))

        // Must NOT hide during permission prompts or sensitive system agents
        for bundleID in [
            "com.apple.SecurityAgent",
            "com.apple.UserNotificationCenter",
            "com.apple.CoreServicesUIAgent",
            "com.apple.localauthentication.UIAgent",
            "com.apple.OSDUIHelper"
        ] {
            var promptState = validState
            promptState.frontmostBundleID = bundleID
            #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(promptState))
        }

        // Must NOT hide when paused for permission setup, native resize cursor, disabled, or env override
        var paused = validState
        paused.pausedForPermissionSetup = true
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(paused))

        var resizing = validState
        resizing.nativeResizeCursorActive = true
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(resizing))

        var disabled = validState
        disabled.enabled = false
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(disabled))

        var envSuppressed = validState
        envSuppressed.suppressHidingByEnvironment = true
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(envSuppressed))
    }

    @Test("Apple Mouse & iPadOS Dot modes morph cleanly into button highlight, instant I-beam, resize, and hide while typing")
    func appleMouseDotIBeamResizeAndTypingHide() {
        let config = PointerConfiguration()
        #expect(config.pointerShapeStyle == .appleMouse)
        #expect(config.hideWhileTyping)
        #expect(!config.showNativeResizeCursors)

        let engine = PointerEngine(initialPosition: CGPoint(x: 200, y: 200), timestamp: 0.0, configuration: config)
        let freeState = engine.step(dt: 1.0 / 120.0, timestamp: 1.0 / 120.0)
        #expect(freeState.arrowBlend > 0.99)
        #expect(freeState.resizeBlend < 0.01)
        #expect(freeState.resizeKind == .none)
        #expect(!freeState.isBeam)

        // Frame-0 instant system I-beam works immediately without waiting for AX or magnetism
        engine.updateSystemIBeam(true)
        let immediateBeam = engine.step(dt: 1.0 / 120.0, timestamp: 0.02)
        #expect(immediateBeam.isBeam)
        #expect(immediateBeam.isSnapped)
        var settledBeam = immediateBeam
        for i in 1...120 {
            settledBeam = engine.step(dt: 1.0 / 120.0, timestamp: 0.02 + Double(i) / 120.0)
        }
        #expect(settledBeam.isBeam)
        #expect(settledBeam.arrowBlend < 0.02)
        #expect(abs(settledBeam.size.width - ApplePointerConstants.Geometry.beamWidth) < 0.1)
        #expect(settledBeam.size.height >= 20.0)

        // Wrapper highlight cannot override active system I-beam
        let wrapper = HitTarget(
            id: "wrapper",
            rect: CGRect(x: 150, y: 150, width: 100, height: 100),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 8.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(wrapper, at: 1.1)
        let stillBeam = engine.step(dt: 1.0 / 120.0, timestamp: 1.11)
        #expect(stillBeam.isBeam)

        // Leaving text restores Apple Mouse arrow cleanly
        engine.updateSystemIBeam(false)
        var backFromBeam = stillBeam
        for i in 1...120 {
            backFromBeam = engine.step(dt: 1.0 / 120.0, timestamp: 1.12 + Double(i) / 120.0)
        }
        #expect(!backFromBeam.isBeam)
        #expect(backFromBeam.arrowBlend > 0.98)

        // Switching to Dot mode morphs arrowBlend -> 0
        engine.configuration.pointerShapeStyle = .ipadDot
        var dotState = backFromBeam
        for i in 1...120 {
            dotState = engine.step(dt: 1.0 / 120.0, timestamp: 2.2 + Double(i) / 120.0)
        }
        #expect(dotState.arrowBlend < 0.02)
        #expect(dotState.pointerShapeStyle == .ipadDot)

        // Switch back to Mouse mode, then snap to button -> arrowBlend -> 0
        engine.configuration.pointerShapeStyle = .appleMouse
        for i in 1...120 {
            _ = engine.step(dt: 1.0 / 120.0, timestamp: 3.3 + Double(i) / 120.0)
        }
        let btn = HitTarget(
            id: "btn",
            rect: CGRect(x: 180, y: 180, width: 40, height: 40),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 8.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(btn, at: 4.4)
        var snappedState = dotState
        for i in 1...120 {
            snappedState = engine.step(dt: 1.0 / 120.0, timestamp: 4.4 + Double(i) / 120.0)
        }
        #expect(snappedState.arrowBlend < 0.02)
        #expect(snappedState.isSnapped)

        // Entering split-view divider overrides button snap and morphs into splitHorizontal resize cursor
        engine.updateResizeCursor(.splitHorizontal)
        var resizeState = snappedState
        for i in 1...120 {
            resizeState = engine.step(dt: 1.0 / 120.0, timestamp: 5.5 + Double(i) / 120.0)
        }
        #expect(resizeState.resizeKind == .splitHorizontal)
        #expect(resizeState.resizeBlend > 0.98)
        #expect(resizeState.arrowBlend < 0.02)
        #expect(!resizeState.isSnapped)

        // Leaving resize morphs cleanly back to Apple Mouse
        engine.updateResizeCursor(.none)
        var backToArrow = resizeState
        for i in 1...120 {
            backToArrow = engine.step(dt: 1.0 / 120.0, timestamp: 6.6 + Double(i) / 120.0)
        }
        #expect(backToArrow.arrowBlend > 0.98)
        #expect(backToArrow.resizeBlend < 0.02)

        // Typing hides the idle pointer, and mouse move wakes it cleanly
        engine.hideForTyping(at: 7.7)
        #expect(engine.isHiddenByTyping)
        var hiddenState = backToArrow
        for i in 1...60 {
            hiddenState = engine.step(dt: 1.0 / 120.0, timestamp: 7.7 + Double(i) / 120.0)
        }
        #expect(hiddenState.opacity < 0.05)

        engine.updatePointerPosition(CGPoint(x: 220, y: 200), timestamp: 8.5)
        #expect(!engine.isHiddenByTyping)
        #expect(!engine.isAutohidden)
        var wokenState = hiddenState
        for i in 1...90 {
            wokenState = engine.step(dt: 1.0 / 120.0, timestamp: 8.5 + Double(i) / 120.0)
        }
        #expect(wokenState.opacity > 0.95)
    }

    @Test("Per-type pointer sizes, exact Apple pointerMatrix + Increase Contrast over buttons, zero-slip menuItem, and screenshot crosshair")
    func perTypeSizesAppleContrastMenuItemAndCrosshair() {
        // Dot can shrink down to 0.5x (~10pt), while Mouse clamps at >= 1.0x
        var cfg = PointerConfiguration(
            pointerShapeStyle: .ipadDot,
            dotSizeMultiplier: 0.55,
            mouseSizeMultiplier: 0.60
        )
        #expect(abs(cfg.dotSizeMultiplier - 0.55) < 1e-6)
        #expect(abs(cfg.mouseSizeMultiplier - 1.00) < 1e-6)
        #expect(abs(cfg.activeSizeMultiplier - 0.55) < 1e-6)

        cfg.pointerShapeStyle = .appleMouse
        #expect(abs(cfg.activeSizeMultiplier - 1.00) < 1e-6)
        cfg.pointerSizeMultiplier = 1.45
        #expect(abs(cfg.mouseSizeMultiplier - 1.45) < 1e-6)
        #expect(abs(cfg.dotSizeMultiplier - 0.55) < 1e-6)

        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0.0, configuration: cfg)
        engine.updateBackgroundLuma(0.15) // dark background
        var freeState = engine.step(dt: 1.0 / 120.0, timestamp: 0.01)
        for i in 1...180 {
            freeState = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        // Free-floating uses Apple's latest iPadOS 27 Liquid Glass (plasmaDarkBackground) by default
        #expect(abs(freeState.colorMatrix.m15 - PointerColorMatrix.plasmaDarkBackground.m15) < 0.02)
        #expect(abs(freeState.pointerSizeMultiplier - 1.45) < 1e-6)

        // Snapping onto a button in Mouse mode STILL snaps & morphs AND preserves exact Apple pointerMatrix
        // (including all Increase Contrast variants rather than washing out with contentOverlayMatrix)
        let btn = HitTarget(
            id: "toolbar-btn",
            rect: CGRect(x: 80, y: 82, width: 40, height: 36),
            cornerRadius: 18.0,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 6.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(btn, at: 2.0)
        var snappedState = freeState
        for i in 1...180 {
            snappedState = engine.step(dt: 1.0 / 120.0, timestamp: 2.0 + Double(i) / 120.0)
        }
        #expect(snappedState.isSnapped)
        #expect(snappedState.arrowBlend < 0.02)
        #expect(abs(snappedState.cornerRadius - 18.0) < 0.2)
        let expectedDefaultDark = PointerColorMatrix.contentOverlayDarkBackground.applyingHighlightContrast(
            isDarkBackground: true,
            contrast: Float(PointerConfiguration.defaultHighlightContrast)
        )
        #expect(abs(snappedState.colorMatrix.m15 - expectedDefaultDark.m15) < 0.02)
        #expect(abs(snappedState.colorMatrix.m45 - expectedDefaultDark.m45) < 0.02)

        // Enabling Increase Contrast boosts snapped highlight intensity cleanly
        engine.configuration.highContrast = true
        var hcSnappedState = snappedState
        for i in 1...60 {
            hcSnappedState = engine.step(dt: 1.0 / 120.0, timestamp: 3.6 + Double(i) / 120.0)
        }
        #expect(hcSnappedState.intensity > snappedState.intensity + 0.05)
        engine.configuration.highContrast = false

        // Native menu item stays strictly locked (zero slip) with subtle intensity
        let menuItem = HitTarget(
            id: "menu-row",
            rect: CGRect(x: 20, y: 88, width: 220, height: 24),
            cornerRadius: 6.0,
            kind: .menuItem,
            slipX: 0.0,
            slipY: 0.0,
            maxSlipPoints: 0.0,
            overlayEffectStyle: .standard
        )
        engine.updatePointerPosition(CGPoint(x: 210, y: 100), timestamp: 4.0)
        engine.updateHitTarget(menuItem, at: 4.0)
        var menuState = snappedState
        for i in 1...180 {
            menuState = engine.step(dt: 1.0 / 120.0, timestamp: 4.0 + Double(i) / 120.0)
        }
        #expect(menuState.isSnapped)
        #expect(abs(menuState.center.x - 130.0) < 0.2) // strictly centered, zero edge overflow
        #expect(menuState.intensity < 0.26)

        // Screenshot crosshair overrides snapping and morphs cleanly
        engine.updateSystemCrosshair(true)
        var crossState = menuState
        for i in 1...120 {
            crossState = engine.step(dt: 1.0 / 120.0, timestamp: 6.0 + Double(i) / 120.0)
        }
        #expect(crossState.isCrosshair)
        #expect(crossState.crosshairBlend > 0.98)
        #expect(!crossState.isSnapped)
        #expect(crossState.arrowBlend < 0.02)

        engine.updateSystemCrosshair(false)
        var afterCross = crossState
        for i in 1...120 {
            afterCross = engine.step(dt: 1.0 / 120.0, timestamp: 7.5 + Double(i) / 120.0)
        }
        #expect(!afterCross.isCrosshair)
        #expect(afterCross.crosshairBlend < 0.02)
        #expect(afterCross.arrowBlend > 0.98)
    }

    @Test("Small dot automatically boosts intensity & vividness while dotIntensity slider scales cleanly")
    func smallDotAutoIntensityAndSlider() {
        var cfg = PointerConfiguration(
            pointerShapeStyle: .ipadDot,
            dotSizeMultiplier: 1.0,
            dotIntensity: 1.0
        )
        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0.0, configuration: cfg)
        var defaultState = engine.step(dt: 1.0 / 120.0, timestamp: 0.01)
        for i in 1...180 {
            defaultState = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(abs(defaultState.intensity - 0.74) < 0.02)
        #expect(defaultState.dotVividnessBoost < 0.01)

        // Shrinking dot to 0.50x (~10pt) gently increases intensity without overpowering object highlights
        cfg.dotSizeMultiplier = 0.50
        engine.configuration = cfg
        var smallState = defaultState
        for i in 1...180 {
            smallState = engine.step(dt: 1.0 / 120.0, timestamp: 2.0 + Double(i) / 120.0)
        }
        #expect(smallState.intensity > defaultState.intensity + 0.06)
        #expect(smallState.intensity < 0.90)

        // Manual Dot Intensity slider at 1.40x boosts even standard 1.0x dot
        cfg.dotSizeMultiplier = 1.0
        cfg.dotIntensity = 1.40
        engine.configuration = cfg
        var vividState = smallState
        for i in 1...180 {
            vividState = engine.step(dt: 1.0 / 120.0, timestamp: 4.0 + Double(i) / 120.0)
        }
        #expect(vividState.intensity > 0.84)
        #expect(vividState.dotVividnessBoost > 0.7)

        // Lowering Dot Intensity slider to 0.60x softens standard dot cleanly
        cfg.dotIntensity = 0.60
        engine.configuration = cfg
        var subtleState = vividState
        for i in 1...180 {
            subtleState = engine.step(dt: 1.0 / 120.0, timestamp: 6.0 + Double(i) / 120.0)
        }
        #expect(abs(subtleState.intensity - (0.74 * 0.60)) < 0.02)
        #expect(subtleState.dotVividnessBoost < 0.01)
    }

    @Test("Highlight contrast slider scales snapped intensity and color matrix cleanly on light and dark backgrounds")
    func highlightContrastSliderScalesSnappedMaterial() {
        var cfg = PointerConfiguration(highlightContrast: 0.20)
        #expect(abs(cfg.highlightContrast - PointerConfiguration.highlightContrastRange.lowerBound) < 1e-6)
        cfg = PointerConfiguration(highlightContrast: 3.50)
        #expect(abs(cfg.highlightContrast - PointerConfiguration.highlightContrastRange.upperBound) < 1e-6)

        // Legacy config JSON without highlightContrast decodes to defaultHighlightContrast (1.0)
        let legacyJSON = Data(#"{"enabled":true}"#.utf8)
        let legacyDecoded = try! JSONDecoder().decode(PointerConfiguration.self, from: legacyJSON)
        #expect(abs(legacyDecoded.highlightContrast - PointerConfiguration.defaultHighlightContrast) < 1e-6)

        let btn = HitTarget(
            id: "contrast-btn",
            rect: CGRect(x: 80, y: 82, width: 60, height: 34),
            cornerRadius: 10.0,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 6.0,
            overlayEffectStyle: .standard
        )

        func settle(contrast: CGFloat, dark: Bool) -> PointerRenderState {
            let engine = PointerEngine(
                initialPosition: CGPoint(x: 110, y: 99),
                timestamp: 0.0,
                configuration: PointerConfiguration(highlightContrast: contrast)
            )
            engine.updateBackgroundLuma(dark ? 0.15 : 0.90)
            engine.updateHitTarget(btn, at: 0.0)
            var st = engine.step(dt: 1.0 / 120.0, timestamp: 0.01)
            for i in 1...180 {
                st = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
            }
            return st
        }

        let darkLow = settle(contrast: 0.50, dark: true)
        let darkDefault = settle(contrast: 1.00, dark: true)
        let darkHigh = settle(contrast: 1.80, dark: true)
        #expect(darkDefault.intensity > darkLow.intensity + 0.08)
        #expect(darkHigh.intensity > darkDefault.intensity + 0.12)
        #expect(darkDefault.colorMatrix.m15 > darkLow.colorMatrix.m15 + 0.05)
        #expect(darkDefault.colorMatrix.m45 > darkLow.colorMatrix.m45 + 0.10)
        #expect(darkHigh.colorMatrix.m15 > darkDefault.colorMatrix.m15 + 0.08)

        let lightLow = settle(contrast: 0.50, dark: false)
        let lightDefault = settle(contrast: 1.00, dark: false)
        let lightHigh = settle(contrast: 1.80, dark: false)
        #expect(lightDefault.intensity > lightLow.intensity + 0.08)
        #expect(lightHigh.intensity > lightDefault.intensity + 0.12)
        #expect(lightDefault.colorMatrix.m15 < lightLow.colorMatrix.m15 - 0.03)
        #expect(lightDefault.colorMatrix.m45 > lightLow.colorMatrix.m45 + 0.10)
        #expect(lightHigh.colorMatrix.m15 < lightDefault.colorMatrix.m15 - 0.05)
    }

    @Test("Constrained vertical I-beam tracks X 1:1 while magnetically aligning Y to text line center")
    func constrainedVerticalIBeamLineMagnetism() {
        let engine = PointerEngine(initialPosition: CGPoint(x: 200, y: 106), timestamp: 0.0)
        engine.updateSystemIBeam(true)

        // Text line centered at y = 100 (height = 22), cursor is 6pt below line center at y = 106
        let lineBeam = HitTarget(
            id: "ibeam-AXStaticText-100-22",
            rect: CGRect(x: 198.5, y: 89.0, width: 3.0, height: 22.0),
            regionRect: CGRect(x: 100.0, y: 88.0, width: 400.0, height: 24.0),
            cornerRadius: 1.5,
            kind: .beam,
            slipX: 1.0,
            slipY: 0.22,
            maxSlipPoints: 3.0,
            overlayEffectStyle: .none
        )
        engine.updateHitTarget(lineBeam, at: 0.0)

        // Move horizontally across the line while staying 6pt below line center
        var t = 0.0
        var state = engine.step(dt: 1.0 / 120.0, timestamp: t)
        for i in 1...180 {
            t = Double(i) / 120.0
            let x = 200.0 + CGFloat(i) * 0.5 // moves to x = 290
            engine.updatePointerPosition(CGPoint(x: x, y: 106.0), timestamp: t)
            state = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        // X tracks 1:1 freely (close to 290), while Y stays magnetically near line center (100 + 6*0.22 = 101.32)
        #expect(state.isBeam)
        #expect(abs(state.center.x - 290.0) < 1.5)
        #expect(abs(state.center.y - 101.32) < 0.35)

        // Pause > 0.04s -> mouseRecentering pulls Y right onto exact line center (100.0)
        for _ in 1...180 {
            t += 1.0 / 120.0
            state = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        #expect(abs(state.center.x - 290.0) < 0.2)
        #expect(abs(state.center.y - 100.0) < 0.15)
    }

    @Test("Typing palm-rejection wake threshold, fast-flight velocity projection, press intensity boost, elastic stretch, sliders, scrollbars, special cursors, and excluded apps")
    func advancedAppleParityFeatures() {
        // 1. Typing-hide palm rejection: tiny 2pt tremor does NOT wake, >= 5pt deliberate move wakes
        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0.0)
        engine.hideForTyping(at: 0.0)
        #expect(engine.isHiddenByTyping)
        engine.updatePointerPosition(CGPoint(x: 112, y: 101), timestamp: 0.1)
        #expect(engine.isHiddenByTyping)
        engine.updatePointerPosition(CGPoint(x: 128, y: 100), timestamp: 0.2)
        #expect(!engine.isHiddenByTyping)

        // 2. Fast-flight velocity projection skips intermediate button when flying > 1000 pt/s past it
        engine.updatePointerPosition(CGPoint(x: 100, y: 100), timestamp: 1.0)
        engine.updatePointerPosition(CGPoint(x: 120, y: 100), timestamp: 1.008) // 2500 pt/s
        engine.updatePointerPosition(CGPoint(x: 140, y: 100), timestamp: 1.016) // 2500 pt/s (2nd fast frame)
        let flyoverBtn = HitTarget(
            id: "mid-btn",
            rect: CGRect(x: 120, y: 80, width: 40, height: 40),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 6.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(flyoverBtn, at: 1.016)
        #expect(engine.currentTarget == nil)

        // Once slowed down over button, snaps cleanly + press deepens intensity + pulling edge stretches elastically
        engine.updatePointerPosition(CGPoint(x: 140, y: 100), timestamp: 1.30)
        engine.updateHitTarget(flyoverBtn, at: 1.30)
        #expect(engine.currentTarget?.id == "mid-btn")
        var t = 1.30
        var idleSnap = engine.step(dt: 1.0 / 120.0, timestamp: t)
        for _ in 1...120 {
            t += 1.0 / 120.0
            idleSnap = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        engine.setPressed(true, timestamp: t + 0.01)
        var pressedSnap = idleSnap
        for _ in 1...120 {
            t += 1.0 / 120.0
            pressedSnap = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        #expect(pressedSnap.intensity > idleSnap.intensity + 0.12)
        engine.setPressed(false, timestamp: t + 0.01)

        // Pulling toward right edge produces subtle elastic X stretch
        engine.configuration.materialPreset = .liquidGlass
        engine.updatePointerPosition(CGPoint(x: 160, y: 100), timestamp: t + 0.02)
        var stretched = pressedSnap
        for _ in 1...60 {
            t += 1.0 / 120.0
            stretched = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        #expect(stretched.elasticScaleX > 1.015)

        // 3. Slider accessory & Scrollbar thumb
        let slider = HitTarget(
            id: "slider-knob",
            rect: CGRect(x: 150, y: 90, width: 20, height: 20),
            cornerRadius: 10,
            kind: .highlight,
            slipX: 0.14,
            slipY: 0.06,
            maxSlipPoints: 4.0,
            overlayEffectStyle: .standard,
            accessoryKind: .horizontalArrows
        )
        engine.updateHitTarget(slider, at: t)
        var sliderState = stretched
        for _ in 1...90 {
            t += 1.0 / 120.0
            sliderState = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        #expect(sliderState.accessoryKind == .horizontalArrows)
        #expect(sliderState.accessoryBlend > 0.95)

        let scroll = HitTarget(
            id: "scroll-v",
            rect: CGRect(x: 155, y: 60, width: 10, height: 80),
            cornerRadius: 5,
            kind: .scrollThumb,
            slipX: 0.08,
            slipY: 1.0,
            maxSlipPoints: 2.5,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(scroll, at: t)
        var scrollState = sliderState
        for _ in 1...90 {
            t += 1.0 / 120.0
            scrollState = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        #expect(scrollState.isSnapped)
        #expect(abs(scrollState.cornerRadius - 5.0) < 0.2)

        // 4. Special cursors morph cleanly and all 14 glyphs produce non-empty CGPaths
        engine.updateSpecialCursor(.eyedropper)
        var specialState = scrollState
        for _ in 1...90 {
            t += 1.0 / 120.0
            specialState = engine.step(dt: 1.0 / 120.0, timestamp: t)
        }
        #expect(specialState.specialCursorKind == .eyedropper)
        #expect(specialState.specialCursorBlend > 0.95)
        for kind in SpecialCursorKind.allCases where kind != .none {
            #expect(!IPadSpecialCursorPaths.makePath(kind: kind).isEmpty)
        }

        // 5. Excluded apps & unknown custom app cursor safety policy
        let excludedState = CursorHideSafetyPolicy.State(
            enabled: true,
            overlayActive: true,
            nativeResizeCursorActive: false,
            customAppCursorActive: false,
            pausedForPermissionSetup: false,
            frontmostBundleID: "com.carriez.rustdesk",
            excludedBundleIDs: Set(PointerConfiguration.defaultExcludedBundleIDs),
            lastRenderedFrameUptime: 100.0,
            currentUptime: 100.1
        )
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(excludedState))

        var customToolState = excludedState
        customToolState.frontmostBundleID = "com.figma.Desktop"
        customToolState.customAppCursorActive = true
        #expect(!CursorHideSafetyPolicy.shouldHideSystemCursor(customToolState))
    }

    @Test("Balanced Liquid Glass rim contrast, smooth typing caret physics, inertia toggle, zoom scaling, and fullscreen video autohide")
    func balancedLiquidGlassSmoothCaretInertiaZoomAndFullscreenAutohide() {
        var cfg = PointerConfiguration(
            pointerShapeStyle: .ipadDot,
            inertiaEnabled: false,
            autohideDuration: 10.0,
            scaleWithZoomEnabled: true
        )
        let engine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0.0, configuration: cfg)
        engine.updateBackgroundLuma(0.12)

        // 1. Free Liquid Glass dot has delicate glass rim (softer than snapped object highlight)
        var freeState = engine.step(dt: 1.0 / 120.0, timestamp: 0.01)
        for i in 1...60 {
            freeState = engine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(freeState.rimSpecularAlpha > 0.30 && freeState.rimSpecularAlpha < 0.50)

        // 2. Accessibility zoom scales pointer size smoothly when scaleWithZoomEnabled = true
        engine.updateAccessibilityZoomFactor(2.0)
        var zoomedState = freeState
        for i in 1...90 {
            zoomedState = engine.step(dt: 1.0 / 120.0, timestamp: 0.6 + Double(i) / 120.0)
        }
        #expect(zoomedState.size.width > freeState.size.width * 1.35)
        engine.updateAccessibilityZoomFactor(1.0)

        // 3. Dock lift target has stronger glass rim than free dot, soft shadow, and directional light tracking
        let dock = HitTarget(
            id: "dock-lift",
            rect: CGRect(x: 70, y: 70, width: 60, height: 60),
            cornerRadius: 13.4,
            kind: .lift,
            slipX: 0.055,
            slipY: 0.055,
            maxSlipPoints: 15.0,
            overrideSlipPoints: CGPoint(x: 4.5, y: 4.5),
            scaleUpPoints: 4.0,
            overlayEffectStyle: .prominent
        )
        engine.updatePointerPosition(CGPoint(x: 120, y: 80), timestamp: 2.0)
        engine.updateHitTarget(dock, at: 2.0)
        var liftState = zoomedState
        for i in 1...120 {
            liftState = engine.step(dt: 1.0 / 120.0, timestamp: 2.0 + Double(i) / 120.0)
        }
        #expect(liftState.liftShadowAlpha > 0.20)
        #expect(liftState.rimSpecularAlpha > freeState.rimSpecularAlpha + 0.30)
        #expect(liftState.rimLightDirection.x > 0.2)

        // 3b. VS Code-style SmoothCaretEngine glides locally on typing, fades out once settled (no double caret),
        // and teleports cleanly on mouse clicks or paragraph jumps without flying across the screen.
        let caretEngine = SmoothCaretEngine()
        caretEngine.updateTargetCaret(CGRect(x: 100, y: 200, width: 2, height: 20), at: 0.0, source: .typing)
        var cState = caretEngine.step(dt: 1.0 / 120.0, timestamp: 0.01, enabled: true, isDarkBackground: true)
        #expect(!cState.isVisible) // initial seed stays invisible until actual glide
        caretEngine.updateTargetCaret(CGRect(x: 112, y: 200, width: 2, height: 20), at: 0.02, source: .typing)
        let midGlide = caretEngine.step(dt: 1.0 / 120.0, timestamp: 0.028, enabled: true, isDarkBackground: true)
        #expect(midGlide.isVisible)
        #expect(midGlide.isDarkBackground)
        #expect(midGlide.rect.midX > 100.2 && midGlide.rect.midX < 111.5)
        for i in 1...120 {
            cState = caretEngine.step(dt: 1.0 / 120.0, timestamp: 0.028 + Double(i) / 120.0, enabled: true, isDarkBackground: true)
        }
        #expect(!cState.isVisible) // fades out cleanly after settling so native caret never doubles

        // Apple iPadOS-style jump between text chunks (paragraph jump & mouse click within 520pt) glides smoothly,
        // while huge cross-screen teleports (> 520pt) snap cleanly without flying across the monitor.
        caretEngine.updateTargetCaret(CGRect(x: 140, y: 265, width: 2, height: 20), at: 2.0, source: .keyboardNavigation)
        let jumped = caretEngine.step(dt: 1.0 / 120.0, timestamp: 2.008, enabled: true)
        #expect(jumped.isVisible)
        #expect(jumped.rect.midY > 205.0 && jumped.rect.midY < 275.0)
        caretEngine.updateTargetCaret(CGRect(x: 190, y: 310, width: 2, height: 20), at: 2.5, source: .mouseClick)
        let clicked = caretEngine.step(dt: 1.0 / 120.0, timestamp: 2.508, enabled: true)
        #expect(clicked.isVisible)
        caretEngine.updateTargetCaret(CGRect(x: 190, y: 980, width: 2, height: 20), at: 3.0, source: .mouseClick)
        let teleported = caretEngine.step(dt: 1.0 / 120.0, timestamp: 3.008, enabled: true)
        #expect(!teleported.isVisible)

        // Circular traffic light with padding keeps exact circular cornerRadius (never turns squircle/square)
        let trafficLight = HitTarget(
            id: "traffic-close",
            rect: CGRect(x: 93, y: 93, width: 14, height: 14),
            cornerRadius: 7.0,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 4.0,
            horizontalPadding: 2.0,
            verticalPadding: 2.0,
            overlayEffectStyle: .standard
        )
        engine.updatePointerPosition(CGPoint(x: 100, y: 100), timestamp: 2.6)
        engine.updateHitTarget(trafficLight, at: 2.6)
        var circleState = liftState
        for i in 1...120 {
            circleState = engine.step(dt: 1.0 / 120.0, timestamp: 2.6 + Double(i) / 120.0)
        }
        #expect(abs(circleState.size.width - 18.0) < 0.1)
        #expect(abs(circleState.cornerRadius - 9.0) < 0.1)

        // 4. Fullscreen video caps idle autohide to 2.0s even when configured delay is 10.0s
        engine.updateHitTarget(nil, at: 3.1)
        engine.updateFullscreenVideoActive(true)
        _ = engine.step(dt: 1.0 / 120.0, timestamp: 5.5)
        #expect(engine.isAutohidden)

        // 5. Disabling Pointer Inertia allows snapping even on high-velocity entry
        engine.updateFullscreenVideoActive(false)
        engine.updatePointerPosition(CGPoint(x: 100, y: 100), timestamp: 6.0)
        engine.updatePointerPosition(CGPoint(x: 120, y: 100), timestamp: 6.008)
        engine.updatePointerPosition(CGPoint(x: 140, y: 100), timestamp: 6.016)
        let btn = HitTarget(
            id: "fast-btn",
            rect: CGRect(x: 120, y: 80, width: 40, height: 40),
            cornerRadius: 8,
            kind: .highlight,
            slipX: 0.099,
            slipY: 0.09,
            maxSlipPoints: 6.0,
            overlayEffectStyle: .standard
        )
        engine.updateHitTarget(btn, at: 6.016)
        #expect(engine.currentTarget?.id == "fast-btn")
        cfg.inertiaEnabled = true
        engine.configuration = cfg

        // 6. Disabling Liquid Glass persists via Codable and turns off glass rim, lift shadow, and elastic stretch
        var classicCfg = PointerConfiguration(pointerShapeStyle: .ipadDot)
        #expect(classicCfg.liquidGlassEnabled)
        classicCfg.liquidGlassEnabled = false
        classicCfg.dotLiquidGlassEnabled = false
        #expect(classicCfg.materialPreset == .classicIPadOS)
        let encoded = try! JSONEncoder().encode(classicCfg)
        let decoded = try! JSONDecoder().decode(PointerConfiguration.self, from: encoded)
        #expect(!decoded.liquidGlassEnabled)
        #expect(decoded.materialPreset == .classicIPadOS)

        let classicEngine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0.0, configuration: decoded)
        classicEngine.updateBackgroundLuma(0.12)
        var classicFree = classicEngine.step(dt: 1.0 / 120.0, timestamp: 0.01)
        for i in 1...120 {
            classicFree = classicEngine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(classicFree.materialPreset == .classicIPadOS)
        #expect(classicFree.rimSpecularAlpha == 0.0)
        #expect(abs(classicFree.colorMatrix.m15 - PointerColorMatrix.classicDarkBackground.m15) < 0.02)

        classicEngine.updateHitTarget(dock, at: 2.0)
        classicEngine.updatePointerPosition(CGPoint(x: 125, y: 100), timestamp: 2.02)
        var classicLift = classicFree
        for i in 1...120 {
            classicLift = classicEngine.step(dt: 1.0 / 120.0, timestamp: 2.02 + Double(i) / 120.0)
        }
        #expect(classicLift.rimSpecularAlpha == 0.0)
        #expect(classicLift.liftShadowAlpha < 0.01)
        #expect(abs(classicLift.elasticScaleX - 1.0) < 0.005)

        // 7. Zero-idle settling & nextAutohideDelay allow pausing CADisplayLink with 0% idle CPU
        var idleCfg = PointerConfiguration(autohideEnabled: true, autohideDuration: 8.0)
        let idleEngine = PointerEngine(initialPosition: CGPoint(x: 200, y: 200), timestamp: 0.0, configuration: idleCfg)
        var idleT = 0.0
        for _ in 1...80 {
            idleT += 1.0 / 120.0
            _ = idleEngine.step(dt: 1.0 / 120.0, timestamp: idleT)
        }
        #expect(idleEngine.isIdleSettled(at: idleT))
        let nextDelay = idleEngine.nextAutohideDelay(at: idleT)
        #expect(nextDelay != nil && nextDelay! > 7.0 && nextDelay! <= 8.0)
        idleEngine.updatePointerPosition(CGPoint(x: 220, y: 200), timestamp: idleT + 0.01)
        #expect(!idleEngine.isIdleSettled(at: idleT + 0.01))
        idleCfg.autohideEnabled = false
        idleEngine.configuration = idleCfg
        #expect(idleEngine.nextAutohideDelay(at: idleT + 0.01) == nil)

        // 8. Click-and-hold Apple contrast shift on free Dot and snapped highlight, settling cleanly on release
        let pressEngine = PointerEngine(
            initialPosition: CGPoint(x: 150, y: 150),
            timestamp: 0.0,
            configuration: PointerConfiguration(pointerShapeStyle: .ipadDot)
        )
        pressEngine.updateBackgroundLuma(0.15)
        var freeRest = pressEngine.step(dt: 1.0 / 120.0, timestamp: 0.01)
        for i in 1...120 {
            freeRest = pressEngine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        pressEngine.setPressed(true, timestamp: 1.1)
        var freePressed = freeRest
        for i in 1...60 {
            freePressed = pressEngine.step(dt: 1.0 / 120.0, timestamp: 1.1 + Double(i) / 120.0)
        }
        #expect(freePressed.intensity > freeRest.intensity + 0.08)
        #expect(freePressed.dotVividnessBoost > freeRest.dotVividnessBoost + 0.20)
        #expect(freePressed.colorMatrix.m15 > freeRest.colorMatrix.m15 + 0.04)
        #expect(freePressed.colorMatrix.m45 > freeRest.colorMatrix.m45 + 0.05)
        #expect(freePressed.rimSpecularAlpha > freeRest.rimSpecularAlpha + 0.08)

        pressEngine.setPressed(false, timestamp: 1.7)
        var freeReleased = freePressed
        for i in 1...120 {
            freeReleased = pressEngine.step(dt: 1.0 / 120.0, timestamp: 1.7 + Double(i) / 120.0)
        }
        #expect(abs(freeReleased.intensity - freeRest.intensity) < 0.02)
        #expect(abs(freeReleased.colorMatrix.m15 - freeRest.colorMatrix.m15) < 0.01)

        // 9. Stage Manager 3D perspective tilt & inner pointer dot on large snapped cards
        let stageEngine = PointerEngine(
            initialPosition: CGPoint(x: 110, y: 240),
            timestamp: 0.0,
            configuration: PointerConfiguration(pointerShapeStyle: .ipadDot)
        )
        let tiltRad: CGFloat = 24.0 * .pi / 180.0
        let stageCard = HitTarget(
            id: "stagemanager-10-160-180x140",
            rect: CGRect(x: 10, y: 160, width: 180, height: 140),
            cornerRadius: 14.0,
            kind: .highlight,
            slipX: 0.025,
            slipY: 0.025,
            maxSlipPoints: 4.0,
            overlayEffectStyle: .standard,
            perspectiveTiltY: tiltRad
        )
        stageEngine.updateHitTarget(stageCard, at: 0.1)
        stageEngine.updatePointerPosition(CGPoint(x: 145, y: 255), timestamp: 0.12)
        var stageState = stageEngine.step(dt: 1.0 / 120.0, timestamp: 0.13)
        for i in 1...120 {
            stageState = stageEngine.step(dt: 1.0 / 120.0, timestamp: 0.13 + Double(i) / 120.0)
        }
        #expect(abs(stageState.perspectiveTiltY - tiltRad) < 0.02)
        #expect(stageState.innerPointerAlpha > 0.90)
        #expect(abs((stageState.center.x + stageState.innerPointerOffset.x) - 145.0) < 0.5)
        #expect(abs((stageState.center.y + stageState.innerPointerOffset.y) - 255.0) < 0.5)

        // Small buttons should NOT show an inner pointer dot or perspective tilt
        let smallButton = HitTarget(
            id: "AXButton-small",
            rect: CGRect(x: 300, y: 300, width: 32, height: 32),
            cornerRadius: 16.0,
            kind: .highlight,
            slipX: 0.1,
            slipY: 0.1,
            maxSlipPoints: 4.0,
            overlayEffectStyle: .standard
        )
        stageEngine.updatePointerPosition(CGPoint(x: 316, y: 316), timestamp: 1.5)
        stageEngine.updateHitTarget(smallButton, at: 1.5)
        var smallState = stageState
        for i in 1...120 {
            smallState = stageEngine.step(dt: 1.0 / 120.0, timestamp: 1.5 + Double(i) / 120.0)
        }
        #expect(abs(smallState.perspectiveTiltY) < 0.01)
        #expect(smallState.innerPointerAlpha < 0.02)

        // 10. Independent Glass Dot toggle: non-glass Dot with Liquid Glass snapped UI (and vice versa)
        var splitCfg = PointerConfiguration(
            pointerShapeStyle: .ipadDot,
            materialPreset: .liquidGlass,
            dotLiquidGlassEnabled: false
        )
        let splitEncoded = try! JSONEncoder().encode(splitCfg)
        let splitDecoded = try! JSONDecoder().decode(PointerConfiguration.self, from: splitEncoded)
        #expect(splitDecoded.liquidGlassEnabled)
        #expect(!splitDecoded.dotLiquidGlassEnabled)

        let splitEngine = PointerEngine(initialPosition: CGPoint(x: 100, y: 100), timestamp: 0.0, configuration: splitDecoded)
        splitEngine.updateBackgroundLuma(0.12)
        var nonGlassDot = splitEngine.step(dt: 1.0 / 120.0, timestamp: 0.01)
        for i in 1...120 {
            nonGlassDot = splitEngine.step(dt: 1.0 / 120.0, timestamp: Double(i) / 120.0)
        }
        #expect(!nonGlassDot.isDotLiquidGlass)
        #expect(nonGlassDot.rimSpecularAlpha == 0.0)
        #expect(abs(nonGlassDot.colorMatrix.m15 - PointerColorMatrix.classicDarkBackground.m15) < 0.02)

        splitEngine.updateHitTarget(dock, at: 1.5)
        var glassSnappedWithNonGlassDot = nonGlassDot
        for i in 1...120 {
            glassSnappedWithNonGlassDot = splitEngine.step(dt: 1.0 / 120.0, timestamp: 1.5 + Double(i) / 120.0)
        }
        #expect(glassSnappedWithNonGlassDot.rimSpecularAlpha > 0.70)
        #expect(glassSnappedWithNonGlassDot.liftShadowAlpha > 0.18)

        splitCfg.liquidGlassEnabled = false
        splitCfg.dotLiquidGlassEnabled = true
        splitEngine.configuration = splitCfg
        splitEngine.updateHitTarget(nil, at: 3.0)
        var glassDotWithClassicUI = glassSnappedWithNonGlassDot
        for i in 1...120 {
            glassDotWithClassicUI = splitEngine.step(dt: 1.0 / 120.0, timestamp: 3.0 + Double(i) / 120.0)
        }
        #expect(glassDotWithClassicUI.isDotLiquidGlass)
        #expect(glassDotWithClassicUI.rimSpecularAlpha > 0.30)

        // 11. All four curved window-corner resize paths curve toward their respective corner quadrant
        let nwBox = IPadResizePaths.makeCenteredPath(kind: .cornerNW).boundingBoxOfPath
        let neBox = IPadResizePaths.makeCenteredPath(kind: .cornerNE).boundingBoxOfPath
        let swBox = IPadResizePaths.makeCenteredPath(kind: .cornerSW).boundingBoxOfPath
        let seBox = IPadResizePaths.makeCenteredPath(kind: .cornerSE).boundingBoxOfPath
        let mid = IPadResizePaths.canvasSize.width * 0.5
        #expect(!nwBox.isEmpty && !neBox.isEmpty && !swBox.isEmpty && !seBox.isEmpty)
        // In Y-up coordinates, NW & NE arcs sit slightly higher, SE & SW slightly lower;
        // verify all four paths have valid geometry centered around the 44x44 canvas.
        for box in [nwBox, neBox, swBox, seBox] {
            #expect(box.width > 14.0 && box.height > 14.0)
            #expect(abs(box.midX - mid) < 4.0 && abs(box.midY - mid) < 4.0)
        }

        // 12. Dark Mode menu bar and camera notch targets always resolve to light-on-dark highlight
        // even if CABackdropLayer last sampled a bright window below.
        let menuEngine = PointerEngine(
            initialPosition: CGPoint(x: 80, y: 12),
            timestamp: 0.0,
            configuration: PointerConfiguration(pointerShapeStyle: .ipadDot)
        )
        menuEngine.updateBackgroundLuma(0.92) // bright app window below
        menuEngine.updateSystemDarkAppearance(true)
        let menuTarget = HitTarget(
            id: "menubar-60-0",
            rect: CGRect(x: 60, y: 0, width: 44, height: 24),
            cornerRadius: 8.0,
            kind: .highlight,
            slipX: 0.09,
            slipY: 0.09,
            maxSlipPoints: 2.5,
            overlayEffectStyle: .standard
        )
        menuEngine.updateHitTarget(menuTarget, at: 0.1)
        var menuState = menuEngine.step(dt: 1.0 / 120.0, timestamp: 0.11)
        for i in 1...120 {
            menuState = menuEngine.step(dt: 1.0 / 120.0, timestamp: 0.11 + Double(i) / 120.0)
        }
        #expect(menuState.isDarkBackground)
        #expect(menuState.lumaMix > 0.90)
    }

    @Test("Detects CleanShot X FSOverlay even at alpha 0.0 before drag selection starts while ignoring small preview popups")
    func screenshotCaptureOverlayWindowDetection() {
        // CleanShot X FSOverlay opens fullscreen at layer 103 with alphaValue == 0.0 before mouse-down drag starts
        #expect(CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 103,
            width: 1920,
            height: 1080,
            alpha: 0.0
        ))
        // CleanShot X FSOverlay faded in during capture / fullscreen freeze (layer 103, alpha 1.0)
        #expect(CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 103,
            width: 1920,
            height: 1080,
            alpha: 1.0
        ))
        // CleanShot X CrosshairController thin 1px shielding-level crosshair lines & OneRatioControl
        #expect(CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 2147483629,
            width: 300,
            height: 60,
            alpha: 1.0
        ))
        #expect(CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 2147483628,
            width: 1,
            height: 745,
            alpha: 1.0
        ))
        #expect(CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 2147483628,
            width: 1147,
            height: 1,
            alpha: 1.0
        ))
        // CleanShot X compact recording HUD strip (layer 103, ~157x21, alpha 0.6) must NOT disable ApplePointer
        #expect(!CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 103,
            width: 157,
            height: 21,
            alpha: 0.6
        ))
        #expect(CursorHideSafetyPolicy.isActiveVideoRecordingHUDWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 103,
            width: 157,
            height: 21,
            alpha: 0.6
        ))
        // Taller CleanShot X capture HUD / ratio control (e.g. 220x48 at layer 103, alpha 1.0) must NOT be mistaken for a video-recording HUD
        #expect(!CursorHideSafetyPolicy.isActiveVideoRecordingHUDWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 103,
            width: 220,
            height: 48,
            alpha: 1.0
        ))
        // macOS built-in screencaptureui fullscreen overlay
        #expect(CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "com.apple.screencaptureui",
            ownerName: "screencaptureui",
            layer: 25,
            width: 1440,
            height: 900,
            alpha: 0.0
        ))
        // Small CleanShot X FloatingOverlay Quick Access preview thumbnail (layer 103) must NOT disable ApplePointer
        #expect(!CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 103,
            width: 280,
            height: 180,
            alpha: 1.0
        ))
        // Large CleanShot X Quick Access / FloatingOverlay post-capture popup (layer 101, 672x741) must NOT keep capture mode active
        #expect(!CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 101,
            width: 672,
            height: 741,
            alpha: 1.0,
            screenSizes: [CGSize(width: 1920, height: 1080), CGSize(width: 1024, height: 665)]
        ))
        // Lowercase macOS screencapture touchshield overlay (layer 1498) must trigger capture pass-through
        #expect(CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: nil,
            ownerName: "screencapture",
            layer: 1498,
            width: 2944,
            height: 1080,
            alpha: 1.0
        ))
        // CleanShot X Cmd+Shift+5 All-in-One floating toolbar (694x69 at layer 103) is identified as video/All-in-One UI
        #expect(CursorHideSafetyPolicy.isCleanShotAllInOneToolbarWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 103,
            width: 694,
            height: 69,
            alpha: 1.0
        ))
        // CleanShot X Annotate / Settings / About normal windows (layer 0) must NOT disable ApplePointer
        #expect(!CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "pl.maketheweb.cleanshotx",
            ownerName: "CleanShot X",
            layer: 0,
            width: 1200,
            height: 800,
            alpha: 1.0
        ))
        // Unrelated app fullscreen overlay must NOT trigger screenshot capture pass-through
        #expect(!CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
            bundleID: "com.apple.Safari",
            ownerName: "Safari",
            layer: 103,
            width: 1920,
            height: 1080,
            alpha: 0.0
        ))
    }

    @Test("SmoothCaretEngine survives transient nil AX polls while typing and clears on click outside text")
    func smoothCaretTransientNilResilience() {
        let caret = SmoothCaretEngine()
        let r1 = CGRect(x: 100, y: 200, width: 2.4, height: 18)
        let r2 = CGRect(x: 110, y: 200, width: 2.4, height: 18)
        let r3 = CGRect(x: 120, y: 200, width: 2.4, height: 18)

        #expect(!caret.updateTargetCaret(r1, at: 1.0, source: .typing))
        #expect(caret.updateTargetCaret(r2, at: 1.05, source: .typing))

        // Two transient nil AX timeouts during typing must NOT kill the seeded caret
        _ = caret.updateTargetCaret(nil, at: 1.08, source: .typing)
        _ = caret.updateTargetCaret(nil, at: 1.11, source: .typing)
        #expect(caret.updateTargetCaret(r3, at: 1.14, source: .typing))
        let mid = caret.step(dt: 1.0 / 120.0, timestamp: 1.15, enabled: true, isDarkBackground: true)
        #expect(mid.isVisible)

        // Clicking outside text clears immediately
        #expect(!caret.updateTargetCaret(nil, at: 1.30, source: .mouseClick))
        let hidden = caret.step(dt: 1.0 / 120.0, timestamp: 1.31, enabled: true, isDarkBackground: true)
        #expect(!hidden.isVisible)
    }

    @Test("Burette3DTargetParser maps normalized Mol* piece tokens into Quartz HitTargets and rejects stale points")
    func burette3DTargetParserAndDragRelease() {
        let host = CGRect(x: 900, y: 80, width: 1000, height: 1000)
        let makePieceClass = { (pieceId: String, shape: String, coords: [Int]) in
            Burette3DTargetParser.tokenPrefix + ([pieceId, shape] + coords.map(String.init)).joined(separator: "-")
        }
        // Water sphere circle at 50%..51.8%, 40%..41.8% -> (1400..1418, 480..498), 18x18
        let waterClass = makePieceClass("abc123", "c", [5000, 4000, 5180, 4180])
        let water = Burette3DTargetParser.parse(
            token: waterClass,
            hostFrame: host,
            point: CGPoint(x: 1409, y: 489)
        )
        #expect(water != nil)
        #expect(water?.id == "burette-3d-abc123")
        #expect(water?.rect.width == 18.0)
        #expect(water?.rect.height == 18.0)
        #expect(water?.cornerRadius == 9.0)
        #expect(water?.suppressOutline == true)
        #expect(water?.organicContour?.radii.count == OrganicContour.sampleCount)

        // Diagonal tilted bond/ribbon polygon contour (45-degree capsule hull) wraps along diagonal without outline
        let diagonalClass = makePieceClass("diag9", "p", [2000, 3120, 2120, 3000, 2620, 3500, 2500, 3620])
        let diagonal = Burette3DTargetParser.parse(
            token: diagonalClass,
            hostFrame: host,
            point: CGPoint(x: 1131, y: 411)
        )
        #expect(diagonal != nil)
        #expect(diagonal?.suppressOutline == true)
        if let radii = diagonal?.organicContour?.radii {
            #expect(radii.count == OrganicContour.sampleCount)
            // Diagonal along +45 deg (index 3) must be significantly longer than perpendicular -45 deg (index 9)
            #expect(radii[3] > radii[9] * 1.6)
        }

        // Distant/stale cursor must be rejected
        let stale = Burette3DTargetParser.parse(
            token: waterClass,
            hostFrame: host,
            point: CGPoint(x: 1600, y: 700)
        )
        #expect(stale == nil)

        // Engine morphs into borderless organic contour (no rim, no lift shadow) and releases immediately on drag
        let engine = PointerEngine(initialPosition: CGPoint(x: 1131, y: 411), timestamp: 1.0)
        engine.updateHitTarget(diagonal, at: 1.0)
        var state = engine.step(dt: 1.0 / 120.0, timestamp: 1.01)
        for i in 1...60 {
            state = engine.step(dt: 1.0 / 120.0, timestamp: 1.01 + Double(i) / 120.0)
        }
        #expect(state.suppressSnappedOutline)
        #expect(state.rimSpecularAlpha == 0.0)
        #expect(state.liftShadowAlpha == 0.0)
        #expect(state.organicContourRadii?.count == OrganicContour.sampleCount)
        engine.setPressed(true, timestamp: 1.60)
        engine.updatePointerPosition(CGPoint(x: 1135, y: 413), timestamp: 1.61)
        #expect(engine.currentTarget == nil)
    }

    @Test("ElementGeometryResolver parses CSS/Electron/token radii, preserves real button/icon shapes, and accepts wide interactive rows")
    func elementGeometryResolverShapesAndEligibility() {
        // 1. Platform-prefixed Tailwind & CSS custom radius tokens
        #expect(ElementGeometryResolver.domCornerRadius(classes: ["electron:rounded-md"], minDim: 32) == 6.0)
        #expect(ElementGeometryResolver.domCornerRadius(classes: ["rounded-none"], minDim: 32) == 0.0)
        #expect(ElementGeometryResolver.domCornerRadius(classes: ["rounded-[10px]"], minDim: 36) == 10.0)
        #expect(ElementGeometryResolver.domCornerRadius(classes: ["rounded-[0.5rem]"], minDim: 36) == 8.0)
        #expect(ElementGeometryResolver.domCornerRadius(classes: ["hover:rounded-full", "rounded-lg"], minDim: 36) == 8.0)
        #expect(ElementGeometryResolver.domCornerRadius(
            classes: ["Button-BZrLNX"],
            minDim: 36,
            ancestorTokenClasses: ["browser:[--radius-token-row:10px]"]
        ) == 10.0)

        // 2. Native/fallback corner radius respects real control shape (not blindly turning <=44pt into circles/pills)
        let railIcon = ElementGeometryResolver.resolveCornerRadius(
            visualRect: CGRect(x: 8, y: 51, width: 36, height: 36),
            role: "AXButton",
            subrole: "",
            isInsideToolbar: false,
            isSidebarRow: false,
            isCircularCloseOrDelete: false,
            isNotchButton: false,
            domRadius: nil
        )
        #expect(railIcon >= 9.0 && railIcon <= 10.5)

        let rectButton = ElementGeometryResolver.resolveCornerRadius(
            visualRect: CGRect(x: 0, y: 0, width: 120, height: 32),
            role: "AXButton",
            subrole: "",
            isInsideToolbar: false,
            isSidebarRow: false,
            isCircularCloseOrDelete: false,
            isNotchButton: false,
            domRadius: nil
        )
        #expect(rectButton == ApplePointerConstants.Geometry.defaultPointerCornerRadius)

        let toggleSwitch = ElementGeometryResolver.resolveCornerRadius(
            visualRect: CGRect(x: 0, y: 0, width: 38, height: 22),
            role: "AXCheckBox",
            subrole: "AXSwitch",
            isInsideToolbar: false,
            isSidebarRow: false,
            isCircularCloseOrDelete: false,
            isNotchButton: false,
            domRadius: nil
        )
        #expect(toggleSwitch == 11.0)

        let toolbarPill = ElementGeometryResolver.resolveCornerRadius(
            visualRect: CGRect(x: 0, y: 0, width: 64, height: 34),
            role: "AXButton",
            subrole: "",
            isInsideToolbar: true,
            isSidebarRow: false,
            isCircularCloseOrDelete: false,
            isNotchButton: false,
            domRadius: nil
        )
        #expect(toolbarPill == 17.0)

        // 3. Wide toolbar items normalize height cleanly even when width > height
        let normWide = ElementGeometryResolver.normalizeToolbarRect(CGRect(x: 100, y: 0, width: 120, height: 52), isInsideToolbar: true)
        #expect(normWide.height == 36.0 && normWide.width == 120.0 && normWide.midY == 26.0)

        // 4. Wide CTA buttons (596x50), sidebar rows (320x36), and clickable cards (219x184) are eligible,
        // while huge window panes (500x300) remain rejected.
        #expect(ElementGeometryResolver.isControlSizeEligible(
            size: CGSize(width: 596, height: 50),
            role: "AXButton",
            subrole: "",
            isExplicitControl: true,
            isInsideToolbar: false,
            isSidebarRow: false
        ))
        #expect(ElementGeometryResolver.isControlSizeEligible(
            size: CGSize(width: 219, height: 184),
            role: "AXPopUpButton",
            subrole: "",
            isExplicitControl: true,
            isInsideToolbar: false,
            isSidebarRow: false
        ))
        #expect(ElementGeometryResolver.isControlSizeEligible(
            size: CGSize(width: 320, height: 36),
            role: "AXRow",
            subrole: "AXOutlineRow",
            isExplicitControl: false,
            isInsideToolbar: false,
            isSidebarRow: true
        ))
        #expect(!ElementGeometryResolver.isControlSizeEligible(
            size: CGSize(width: 500, height: 300),
            role: "AXButton",
            subrole: "",
            isExplicitControl: true,
            isInsideToolbar: false,
            isSidebarRow: false
        ))

        // 5. Large interactive cards receive crisp card corner radius (<= 16pt), handles are round
        let cardRadius = ElementGeometryResolver.resolveCornerRadius(
            visualRect: CGRect(x: 0, y: 0, width: 219, height: 184),
            role: "AXPopUpButton",
            subrole: "",
            isInsideToolbar: false,
            isSidebarRow: false,
            isCircularCloseOrDelete: false,
            isNotchButton: false,
            domRadius: nil
        )
        #expect(cardRadius == 16.0)

        let handleRadius = ElementGeometryResolver.resolveCornerRadius(
            visualRect: CGRect(x: 0, y: 0, width: 16, height: 16),
            role: "AXHandle",
            subrole: "",
            isInsideToolbar: false,
            isSidebarRow: false,
            isCircularCloseOrDelete: false,
            isNotchButton: false,
            domRadius: nil
        )
        #expect(handleRadius == 8.0)
    }
}
