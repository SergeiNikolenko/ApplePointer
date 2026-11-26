import CoreGraphics
import Foundation

public struct CursorHideSafetyPolicy: Sendable {
    public static let defaultMaxHeartbeatSilence: TimeInterval = 0.5

    public static let sensitiveSystemPromptBundleIDs: Set<String> = [
        "com.apple.SecurityAgent",
        "com.apple.UserNotificationCenter",
        "com.apple.CoreServicesUIAgent",
        "com.apple.localauthentication.UIAgent",
        "com.apple.OSDUIHelper"
    ]

    public static let screenshotCaptureBundleIDs: Set<String> = [
        "pl.maketheweb.cleanshotx",
        "pl.maketheweb.cleanshotx-setapp",
        "com.apple.screencaptureui",
        "com.apple.ScreenCapture",
        "com.apple.Screenshot"
    ]

    public static let screenshotCaptureOwnerNames: Set<String> = [
        "CleanShot X",
        "screencapture",
        "screencaptureui",
        "Screenshot",
        "ScreenCapture"
    ]

    public struct State: Equatable, Sendable {
        public var enabled: Bool
        public var overlayActive: Bool
        public var nativeResizeCursorActive: Bool
        public var customAppCursorActive: Bool
        public var pausedForPermissionSetup: Bool
        public var frontmostBundleID: String?
        public var excludedBundleIDs: Set<String>
        public var lastRenderedFrameUptime: TimeInterval?
        public var currentUptime: TimeInterval
        public var maxHeartbeatSilence: TimeInterval
        public var suppressHidingByEnvironment: Bool

        public init(
            enabled: Bool,
            overlayActive: Bool,
            nativeResizeCursorActive: Bool,
            customAppCursorActive: Bool = false,
            pausedForPermissionSetup: Bool,
            frontmostBundleID: String?,
            excludedBundleIDs: Set<String> = [],
            lastRenderedFrameUptime: TimeInterval?,
            currentUptime: TimeInterval,
            maxHeartbeatSilence: TimeInterval = CursorHideSafetyPolicy.defaultMaxHeartbeatSilence,
            suppressHidingByEnvironment: Bool = false
        ) {
            self.enabled = enabled
            self.overlayActive = overlayActive
            self.nativeResizeCursorActive = nativeResizeCursorActive
            self.customAppCursorActive = customAppCursorActive
            self.pausedForPermissionSetup = pausedForPermissionSetup
            self.frontmostBundleID = frontmostBundleID
            self.excludedBundleIDs = excludedBundleIDs
            self.lastRenderedFrameUptime = lastRenderedFrameUptime
            self.currentUptime = currentUptime
            self.maxHeartbeatSilence = maxHeartbeatSilence
            self.suppressHidingByEnvironment = suppressHidingByEnvironment
        }
    }

    public static func isSensitiveSystemPrompt(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return sensitiveSystemPromptBundleIDs.contains(bundleID)
    }

    public static func isExcludedApp(bundleID: String?, excludedBundleIDs: Set<String>) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    public static func isScreenshotCaptureOwner(bundleID: String?, ownerName: String) -> Bool {
        if let bundleID, screenshotCaptureBundleIDs.contains(bundleID) {
            return true
        }
        if screenshotCaptureOwnerNames.contains(ownerName) {
            return true
        }
        let lower = ownerName.lowercased()
        return lower == "screencapture" || lower == "screencaptureui" || lower == "cleanshot x"
    }

    /// Detects CleanShot X's Cmd+Shift+5 All-in-One / Video Recording floating toolbar (e.g. 694x69 at layer 103)
    /// so ApplePointer stays active (instead of falling back to the system arrow) during Cmd+Shift+5 video setup.
    public static func isCleanShotAllInOneToolbarWindow(
        bundleID: String?,
        ownerName: String,
        layer: Int,
        width: CGFloat,
        height: CGFloat,
        alpha: Double
    ) -> Bool {
        let isCleanShot = (bundleID == "pl.maketheweb.cleanshotx" || bundleID == "pl.maketheweb.cleanshotx-setapp" || ownerName == "CleanShot X")
        guard isCleanShot else { return false }
        return layer == 103 && alpha > 0.5 && width >= 400.0 && width <= 950.0 && height >= 44.0 && height <= 120.0
    }

    /// Detects CleanShot X's compact floating video-recording control bar (e.g. 157x21 at layer 103, alpha 0.6)
    /// so active video recordings keep ApplePointer running and visible in the recorded video instead of
    /// falling back to the native system arrow because of CleanShot X's recording border/keystroke overlays.
    public static func isActiveVideoRecordingHUDWindow(
        bundleID: String?,
        ownerName: String,
        layer: Int,
        width: CGFloat,
        height: CGFloat,
        alpha: Double
    ) -> Bool {
        let isCleanShot = (bundleID == "pl.maketheweb.cleanshotx" || bundleID == "pl.maketheweb.cleanshotx-setapp" || ownerName == "CleanShot X")
        guard isCleanShot else {
            return false
        }
        // CleanShot X's live video-recording status pill is a slim translucent strip (~157x21 at layer 103, alpha ~0.6).
        // Keep the height ceiling tight (<= 34pt) so taller area-screenshot ratio/size/hint HUDs never disable capture mode.
        return layer == 103 && alpha > 0.1 && alpha <= 0.92 && width >= 90.0 && width <= 300.0 && height >= 16.0 && height <= 34.0
    }

    /// Detects active on-screen screenshot selection overlays (such as CleanShot X's FSOverlay,
    /// which opens fullscreen at layer 103 with alphaValue == 0.0 before drag selection starts,
    /// shielding-level crosshair lines/HUD windows, and macOS screencaptureui overlays) while ignoring
    /// normal editor/settings windows (layer 0), menu bar icons, and Quick Access / FloatingOverlay popups (e.g. 672x741 at layer 101).
    public static func isActiveScreenshotCaptureWindow(
        bundleID: String?,
        ownerName: String,
        layer: Int,
        width: CGFloat,
        height: CGFloat,
        alpha: Double,
        screenSizes: [CGSize] = []
    ) -> Bool {
        guard isScreenshotCaptureOwner(bundleID: bundleID, ownerName: ownerName) else {
            return false
        }
        // Any shielding-level capture/crosshair overlay (including 1px crosshair lines and loupes)
        if layer >= 1000 && max(width, height) >= 20.0 && width >= 1.0 && height >= 1.0 {
            return true
        }
        // Fullscreen capture overlay (e.g. CleanShot X FSOverlay / OneOverlay at layer 103/101 and macOS
        // screencaptureui overlays), while ignoring non-fullscreen Quick Access popups (e.g. 672x741 at layer 101).
        if layer >= 20 {
            if !screenSizes.isEmpty {
                if screenSizes.contains(where: { width >= $0.width * 0.88 && height >= $0.height * 0.88 }) {
                    return true
                }
                return false
            }
            if layer == 101 {
                return false
            }
            if width >= 960.0 && height >= 600.0 {
                return true
            }
        }
        return false
    }


    public static func shouldHideSystemCursor(_ state: State) -> Bool {
        if !state.enabled
            || state.suppressHidingByEnvironment
            || !state.overlayActive
            || state.nativeResizeCursorActive
            || state.customAppCursorActive
            || state.pausedForPermissionSetup
            || isSensitiveSystemPrompt(bundleID: state.frontmostBundleID)
            || isExcludedApp(bundleID: state.frontmostBundleID, excludedBundleIDs: state.excludedBundleIDs) {
            return false
        }

        guard let hb = state.lastRenderedFrameUptime,
              hb > 0,
              (state.currentUptime - hb) <= state.maxHeartbeatSilence else {
            return false
        }

        return true
    }
}
