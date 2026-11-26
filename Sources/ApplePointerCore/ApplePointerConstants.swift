import CoreGraphics
import Foundation

/// Exact constants extracted from Apple's iPadOS pointer implementation
/// (`pointeruid`, `PointerUIServices.framework`, and `UIKitCore.framework`).
public enum ApplePointerConstants {
    public enum Geometry {
        public static let systemPointerSize: CGFloat = 19.0
        public static let axLargeSystemPointerCenterDotSize: CGFloat = 9.5
        public static let defaultPointerCornerRadius: CGFloat = 8.0
        public static let beamWidth: CGFloat = 3.0
        public static let beamMinLength: CGFloat = 24.0
        public static let beamMaxLength: CGFloat = 100.0
        public static let beamMaxSnapLength: CGFloat = 100.0
        public static let textLineRegionPadding: CGFloat = 10.0
        public static let textRegionCaptureMultiplier: CGFloat = 3.0
    }

    public enum SizeRule {
        public static let explicitRequestMultiplier: CGFloat = 1.4
        public static let genericSizeRuleThreshold: CGFloat = 125.0
        public static let narrowAspectRuleMinorDimensionThreshold: CGFloat = 50.0
        public static let narrowAspectRuleMajorDimensionThreshold: CGFloat = 180.0
        public static let pointerSizeRuleMinorDimensionThreshold: CGFloat = 19.0
        public static let pointerSizeRuleMajorDimensionThreshold: CGFloat = 320.0
    }

    public enum ControlBehavior {
        public static let textButtonOutsetLeading: CGFloat = 10.0
        public static let textButtonOutsetTrailing: CGFloat = 10.0
        public static let textButtonOutsetTop: CGFloat = 7.5
        public static let textButtonOutsetBottom: CGFloat = 8.5
        public static let imageButtonOutset: CGFloat = 8.0
        public static let roundButtonOutset: CGFloat = 8.0
        public static let closeButtonOutset: CGFloat = 0.0
        public static let navToolbarCornerRadius: CGFloat = 8.0
        public static let navToolbarHorizontalPadding: CGFloat = 10.0
        public static let navToolbarVerticalPadding: CGFloat = 4.0
    }

    public enum Effect {
        // Highlight (_UIPointerEffectSettings)
        public static let highlightSlipX: CGFloat = 0.099
        public static let highlightSlipY: CGFloat = 0.09
        public static let highlightMaxSlipPoints: CGFloat = 15.0
        public static let highlightScaleUpPoints: CGFloat = 4.0
        public static let highlightParallaxAmount: CGFloat = 0.3

        // Lift (_UIPointerLiftEffectSettings + _UIPointerSBAppIconEffectSettings)
        public static let liftSlipX: CGFloat = 0.055
        public static let liftSlipY: CGFloat = 0.055
        public static let liftMaxSlipPoints: CGFloat = 15.0
        public static let liftScaleUpPoints: CGFloat = 7.6
        public static let liftParallaxAmount: CGFloat = 1.0
        public static let sbAppIconScaleUpPoints: CGFloat = 9.5
        public static let sbAppIconOverrideSlipPoints: CGFloat = 4.5

        // Hover (_UIPointerHoverEffectSettings)
        public static let hoverSlipX: CGFloat = 1.0
        public static let hoverSlipY: CGFloat = 1.0
        public static let hoverScaleUpPoints: CGFloat = 6.0

        // Freeform (_UIFreeformPointerSettings)
        public static let freeformSlipX: CGFloat = 0.25
        public static let freeformSlipY: CGFloat = 0.1
        public static let freeformCornerRadius: CGFloat = 8.0

        // Beam (_UIBeamPointerSettings)
        public static let beamSlipX: CGFloat = 1.0
        public static let beamSlipY: CGFloat = 1.0

        // Pressed (PUIDPointerSettings)
        public static let systemPointerPressedScale: CGFloat = 0.9
        public static let underlayingPointerPressedScaleFactor: CGFloat = 1.02
        public static let tapToClickButtonDownTime: TimeInterval = 0.073
    }

    public enum Springs {
        public static let standardShape = SpringParameters(dampingRatio: 0.9, response: 0.175)
        public static let customShapeMorph = SpringParameters(dampingRatio: 1.0, response: 0.24)
        public static let systemPosition = SpringParameters(dampingRatio: 1.0, response: 0.017)
        public static let focusedPointerPosition = SpringParameters(dampingRatio: 1.0, response: 0.14)
        public static let focusedContentPosition = SpringParameters(dampingRatio: 1.0, response: 0.25)
        public static let rampingExit = SpringParameters(dampingRatio: 1.0, response: 0.125)
        public static let pressedScale = SpringParameters(dampingRatio: 1.0, response: 0.11)
        public static let specularOpacity = SpringParameters(dampingRatio: 1.0, response: 0.17)
        public static let visibleIntensity = SpringParameters(dampingRatio: 1.0, response: 0.15)
        public static let zTransitionOpacity = SpringParameters(dampingRatio: 1.0, response: 0.15)
        public static let materialTransition = SpringParameters(dampingRatio: 1.0, response: 0.5)
        public static let visibleToHidden = SpringParameters(dampingRatio: 1.0, response: 0.5)
        public static let hiddenToVisible = SpringParameters(dampingRatio: 1.0, response: 0.2)
        public static let hiddenToVisibleScale = SpringParameters(dampingRatio: 1.0, response: 0.15)
        public static let shakeToFindExpansion = SpringParameters(dampingRatio: 1.0, response: 0.2)
        public static let shakeToFindContraction = SpringParameters(dampingRatio: 1.0, response: 0.2)
        public static let trackpadRecentering = SpringParameters(mass: 1.0, stiffness: 3262.0, damping: 114.0)
        public static let mouseRecentering = SpringParameters(mass: 1.0, stiffness: 218.0, damping: 28.0)

        public static let rampingMinimumSlipThreshold: CGFloat = 0.15
        public static let delayBeforeRecenteringAfterMouseMovement: TimeInterval = 0.04
        public static let positionToPositionAnimationThreshold: CGFloat = 90.0
        public static let visibleToHiddenPointerScale: CGFloat = 0.96
        public static let visibleToHiddenPointerBlurRadius: CGFloat = 1.5
        public static let hiddenToVisiblePointerScale: CGFloat = 1.75
        public static let hiddenToVisiblePointerBlurRadius: CGFloat = 10.0
    }

    public enum Material {
        public static let materialAlphaDot: CGFloat = 0.85
        public static let materialAlphaIBeam: CGFloat = 1.0
        public static let materialAlphaSmallItemLight: CGFloat = 0.25
        public static let materialAlphaSmallItemDark: CGFloat = 0.30
        public static let materialAlphaSmallItemDarkHighContrast: CGFloat = 0.30
        public static let flexibleRectIntensityReductionRange: CGFloat = 300.0
        public static let flexibleRectIntensityBaseBoost: CGFloat = 0.15
        public static let minFlexibleRectDarkLuminanceIntensity: CGFloat = 0.25
        public static let minFlexibleRectLightLuminanceIntensity: CGFloat = 0.325
        public static let contentOverlayIntensityNormal: CGFloat = 0.5
        public static let contentOverlayIntensityPressed: CGFloat = 0.9
        public static let lumaLowerThreshold: Double = 0.45
        public static let lumaUpperThreshold: Double = 0.55
    }

    public enum Specular {
        public static let standardLongestSideBaseMultiplier: CGFloat = 0.05
        public static let standardOpacityMultiplier: CGFloat = 0.0475
        public static let prominentLongestSideBaseMultiplier: CGFloat = 0.05
        public static let prominentOpacityMultiplier: CGFloat = 0.08

        /// Exact radial alpha profile sampled from Apple's `Specular@2x.png` (300x300).
        public static let radialStops: [(location: CGFloat, alpha: CGFloat)] = [
            (0.0, 230.0 / 255.0),
            (0.1, 215.0 / 255.0),
            (0.2, 171.0 / 255.0),
            (0.3, 116.0 / 255.0),
            (0.4, 68.0 / 255.0),
            (0.5, 39.0 / 255.0),
            (0.6, 20.0 / 255.0),
            (0.7, 9.0 / 255.0),
            (0.8, 3.0 / 255.0),
            (0.9, 1.0 / 255.0),
            (1.0, 0.0)
        ]
    }

    public enum Behavior {
        public static let autohideDurationTrackpad: TimeInterval = 3.25
        public static let autohideDurationMouse: TimeInterval = 8.0
        public static let automaticRegionExitDelayInterval: TimeInterval = 0.2
        public static let scrollSnapCooldown: TimeInterval = 0.15
        public static let regionExitHysteresis: CGFloat = 4.0
        public static let minimumVelocityThresholdForDeceleration: CGFloat = 1000.0
        public static let pointerVelocitySmoothingWeight: CGFloat = 0.75
        public static let pointerPositionProjectionScaleFactor: CGFloat = 0.6

        public static func decelerationRate(accelerationFactor a: Double) -> Double {
            let a2 = a * a
            let a3 = a2 * a
            let a4 = a3 * a
            return 0.00192151 * a4 - 0.0120353 * a3 + 0.0237803 * a2 - 0.025559 * a + 0.991966
        }

        public static let shakeToFindWiggleCount: Int = 8
        public static let shakeToFindGestureInterval: TimeInterval = 0.1
        public static let shakeToFindDecayInterval: TimeInterval = 0.1
        public static let shakeToFindScaleFactor: CGFloat = 0.5
        public static let shakeToFindMaxScaleUpFactor: CGFloat = 5.0
        public static let shakeToFindSlopeVarianceThreshold: CGFloat = 0.2
        public static let shakeToFindScaleUpdateInterval: TimeInterval = 1.0 / 120.0
    }
}
