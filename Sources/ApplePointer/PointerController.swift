import AppKit
import ApplePointerCore
import ApplicationServices
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

struct ResolvedExcludedApp: Identifiable, Hashable {
    let bundleID: String
    let displayName: String
    let appURL: URL?

    var id: String { bundleID }
}

@MainActor
final class PointerController: ObservableObject {
    private static let defaultsKey = "com.nikolenko.ApplePointer.configuration.v4"
    private static let legacyDefaultsKey = "com.nikolenko.ApplePointer.configuration.v3"
    private static let screenContinuityMigratedKey = "com.nikolenko.ApplePointer.migratedScreenContinuity.v1"
    private static let smoothCaretDefaultOffMigratedKey = "com.nikolenko.ApplePointer.migratedSmoothCaretOff.v1"

    @Published var configuration: PointerConfiguration {
        didSet {
            saveConfiguration()
            applyConfiguration()
        }
    }

    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var mouseTrackingActive: Bool = false
    @Published private(set) var pausedForPermissionSetup: Bool = false
    @Published private(set) var currentLuma: Double = 1.0
    @Published private(set) var launchAtLoginEnabled: Bool = false
    @Published private(set) var frontmostAppName: String?
    @Published private(set) var frontmostAppBundleID: String?

    private let engine: PointerEngine
    private let smoothCaretEngine = SmoothCaretEngine()
    private let engineLock = NSLock()
    private let cursorHider = SystemCursorHider()
    private let hitTester = AccessibilityHitTester()
    private let overlayController = OverlayWindowController()
    private var eventTapManager: EventTapManager?
    private var statusPollTimer: Timer?
    private var autohideWakeTimer: Timer?
    private var captureMonitorTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    private var frontmostBundleID: String?
    private var lastProbedIBeamActive: Bool = false
    private var lastObservedKeyAge: TimeInterval = .infinity
    private var lastTypingKeyDownUptime: TimeInterval = -.infinity
    private var lastCaretPollUptime: TimeInterval = 0
    private var lastClickUptime: TimeInterval = -.infinity
    private var lastExcludedWindowScanUptime: TimeInterval = -.infinity
    private var visibleNormalWindows: [(rect: CGRect, bundleID: String)] = []
    private var excludedAppHasOnScreenWindow: Set<String> = []
    private var pidToBundleID: [pid_t: String] = [:]
    private var excludedPIDs: Set<pid_t> = []
    private var captureOverlayPIDs: Set<pid_t> = []
    private var excludedBundleIDSet: Set<String> = []
    private var cachedOwnWindowRects: [CGRect] = []
    private var cachedDockEdgeBands: [CGRect] = []
    private var cachedDockActiveBands: [CGRect] = []
    private var cachedDockOrientation: String = "bottom"
    private var onScreenDockRects: [CGRect] = []
    private var dockPID: pid_t = 0
    private var lastOverDockUptime: TimeInterval = -.infinity
    private var lastKnownVisibleDockRect: CGRect?
    private var lastKnownVisibleDockUptime: TimeInterval = -.infinity
    private var lastFrameNearDockEdge: Bool = false
    private var onScreenResizeWindowRects: [CGRect] = []
    private var onScreenNotificationHoverRects: [CGRect] = []
    private var lockedDragResizeKind: ResizeCursorKind = .none
    private var cachedScreenQuartzRects: [CGRect] = []
    private var lastFrameWasOverDock: Bool = false
    private nonisolated(unsafe) var lastHitTargetIsDock: Bool = false
    private nonisolated(unsafe) var lastHitTargetIsNotificationCenter: Bool = false
    private var lastFrameWasExcludedOrNative: Bool = false
    private var lastSmoothCaretVisible: Bool = false
    private var isMissionControlLikelyActive: Bool = false
    private var isScreenshotCaptureActive: Bool = false
    private var lastWindowScanCursorSeed: Int32 = 0
    private var needsImmediateWindowScan: Bool = false
    private var keepAwakeUntilUptime: TimeInterval = 0
    private var dynamic3DFollowUpWorkItems: [DispatchWorkItem] = []
    private var typingAXObserver: AXObserver?
    private var typingAXObservedPID: pid_t = 0
    private var typingAXObservedAppElement: AXUIElement?
    private var typingAXObservingSelection: Bool = false
    private nonisolated(unsafe) var hasLoggedInitialLuma = false
    private nonisolated static let debugLoggingEnabled = ProcessInfo.processInfo.environment["APPLEPOINTER_DEBUG"] == "1"
    private static let mediaPlayerBundleIDs: Set<String> = [
        "com.apple.QuickTimePlayerX",
        "com.apple.TV",
        "com.colliderli.iina",
        "org.videolan.vlc",
        "io.mpv"
    ]

    init() {
        let loaded = Self.loadConfiguration()
        self.configuration = loaded
        self.frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let initialPos = EventTapManager.currentQuartzMouseLocation()
        self.engine = PointerEngine(
            initialPosition: initialPos,
            timestamp: ProcessInfo.processInfo.systemUptime,
            configuration: loaded
        )

        setupSubsystems()
        refreshPermissions()
        refreshLaunchAtLoginStatus()
        rebuildRunningAppCache()
        refreshVisibleWindowMap(at: ProcessInfo.processInfo.systemUptime)
        refreshScreenGeometry()
        syncOwnWindowRects()
        attachTypingAXObserver(for: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        applyConfiguration()
    }

    func shutdown() {
        detachTypingAXObserver()
        cancelDynamic3DFollowUpProbes()
        autohideWakeTimer?.invalidate()
        autohideWakeTimer = nil
        captureMonitorTimer?.invalidate()
        captureMonitorTimer = nil
        statusPollTimer?.invalidate()
        statusPollTimer = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
            self.themeObserver = nil
        }
        eventTapManager?.stop()
        cursorHider.stop()
        overlayController.stop()
    }

    func toggleEnabled() {
        configuration.enabled.toggle()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            fputs("[ApplePointer] SMAppService launch-at-login error: \(error)\n", stderr)
            fflush(stderr)
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func toggleExcludedApp(bundleID: String) {
        if let idx = configuration.excludedBundleIDs.firstIndex(of: bundleID) {
            configuration.excludedBundleIDs.remove(at: idx)
        } else {
            configuration.excludedBundleIDs.append(bundleID)
        }
    }

    func resolvedExcludedApps() -> [ResolvedExcludedApp] {
        configuration.excludedBundleIDs.map { bid in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            let name: String
            if let url {
                name = FileManager.default.displayName(atPath: url.path)
            } else if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first?.localizedName {
                name = running
            } else {
                name = bid.split(separator: ".").last.map(String.init) ?? bid
            }
            return ResolvedExcludedApp(bundleID: bid, displayName: name, appURL: url)
        }
    }

    func addExcludedAppViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK,
           let url = panel.url,
           let bundle = Bundle(url: url),
           let bid = bundle.bundleIdentifier {
            if !configuration.excludedBundleIDs.contains(bid) {
                configuration.excludedBundleIDs.append(bid)
            }
        }
    }

    func requestPermissions() {
        enterPermissionPause()
        AccessibilityHitTester.requestAccessibilityPrompt()
        refreshPermissions()
    }

    func openAccessibilitySettings() {
        enterPermissionPause()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func resumeFromPermissionPause() {
        pausedForPermissionSetup = false
        syncSafetyAndOverlayState()
        overlayController.bringOverlaysToFront()
    }

    func suspendAXForOwnWindow() {
        hitTester.reset()
        engineLock.lock()
        engine.updateHitTarget(nil)
        engineLock.unlock()
        syncOwnWindowRects()
    }

    /// Snapshot Quartz frames of ApplePointer's own interactive windows (popover, status item, alerts)
    /// so the background AX queue never calls AXUIElementCopyElementAtPosition over our own SwiftUI
    /// NSHostingView (which would invoke NSHostingView.hitTest off the MainActor and trap with SIGTRAP).
    @discardableResult
    func syncOwnWindowRects() -> [CGRect] {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        var rects: [CGRect] = []
        for win in NSApp.windows {
            guard !win.ignoresMouseEvents, win.isVisible || win.alphaValue > 0 else { continue }
            let f = win.frame
            guard f.width > 0, f.height > 0 else { continue }
            let quartzRect = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            rects.append(quartzRect.insetBy(dx: -16.0, dy: -16.0))
        }
        hitTester.updateOwnWindowRects(rects)
        cachedOwnWindowRects = rects
        return rects
    }

    private func enterPermissionPause() {
        pausedForPermissionSetup = true
        syncSafetyAndOverlayState()
        overlayController.bringOverlaysToFront()
    }

    private func syncSafetyAndOverlayState() {
        let currentFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? frontmostBundleID
        frontmostBundleID = currentFrontmost
        let excludedSet = Set(configuration.excludedBundleIDs)
        let cursorPos = EventTapManager.currentQuartzMouseLocation()
        let effectiveBundleID = resolvedEffectiveBundleID(at: cursorPos, frontmost: currentFrontmost, excludedSet: excludedSet)
        cursorHider.updateSafetyState(
            overlayActive: overlayController.hasActiveOverlay,
            nativeResizeActive: false,
            customAppCursorActive: isScreenshotCaptureActive,
            pausedForPermissionSetup: pausedForPermissionSetup,
            frontmostBundleID: effectiveBundleID,
            excludedBundleIDs: excludedSet
        )
        // Keep the overlay panels mounted whenever ApplePointer is enabled so hovering out of an
        // excluded app (e.g. iPhone Mirroring) onto the Dock, Desktop, or Notifications immediately resumes.
        let shouldShowOverlay = configuration.enabled && !pausedForPermissionSetup
        overlayController.setVisible(shouldShowOverlay)
    }

    private func setupSubsystems() {
        cursorHider.onNeedsWake = { [weak self] in
            guard let self else { return }
            self.needsImmediateWindowScan = true
            self.overlayController.bringOverlaysToFront()
            self.keepAwake(for: 0.45)
            self.wakeRenderLoop()
        }

        overlayController.onSpaceChanged = { [weak self] in
            guard let self else { return }
            self.handleSpaceOrMissionControlWake(at: ProcessInfo.processInfo.systemUptime)
        }

        hitTester.onResult = { [weak self] target in
            guard let self else { return }
            let uptime = ProcessInfo.processInfo.systemUptime
            self.engineLock.lock()
            self.engine.updateHitTarget(target, at: uptime)
            self.lastHitTargetIsDock = target?.id.hasPrefix("dock-") ?? false
            self.lastHitTargetIsNotificationCenter = target?.id.hasPrefix("nc-") ?? false
            self.engineLock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.wakeRenderLoop()
            }
        }

        overlayController.setScreensLumaCallback { [weak self] luma in
            guard let self else { return }
            self.engineLock.lock()
            let prevDark = self.engine.isDarkBackground
            self.engine.updateBackgroundLuma(luma)
            let newDark = self.engine.isDarkBackground
            let shouldLog = !self.hasLoggedInitialLuma || (prevDark != newDark)
            self.hasLoggedInitialLuma = true
            self.engineLock.unlock()
            if Self.debugLoggingEnabled && shouldLog {
                fputs("[ApplePointer] backdropLayer:didChangeLuma: \(String(format: "%.4f", luma)) darkBg=\(newDark)\n", stderr)
                fflush(stderr)
            }
            DispatchQueue.main.async { [weak self] in
                self?.currentLuma = luma
                if prevDark != newDark {
                    self?.wakeRenderLoop()
                }
            }
        }

        overlayController.onFrame = { [weak self] dt, uptime in
            guard let self else { return nil }

            let livePos = EventTapManager.currentQuartzMouseLocation()
            let livePrimaryPressed = (NSEvent.pressedMouseButtons & 1) != 0

            self.engineLock.lock()
            let prevPos = self.engine.modelCursorPosition
            let moved = hypot(livePos.x - prevPos.x, livePos.y - prevPos.y) > 0.25
            if moved {
                self.engine.updatePointerPosition(livePos, timestamp: uptime, isTrackpad: nil)
            }
            if self.engine.isPressed && !livePrimaryPressed {
                self.engine.setPressed(false, timestamp: uptime)
            }
            let enabled = self.engine.configuration.enabled
            let magnetism = self.engine.configuration.magnetismEnabled
            let isPressedNow = self.engine.isPressed
            let currentSpeed = hypot(self.engine.smoothedVelocity.x, self.engine.smoothedVelocity.y)
            self.engineLock.unlock()

            // Hide idle pointer smoothly while actively typing so it never lingers next to the text caret
            // Check both combinedSessionState and hidSystemState so slight trackpad palm tremor never blocks hiding.
            let combinedKeyAge = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            let hidKeyAge = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
            let keyAge = min(combinedKeyAge, hidKeyAge)
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let shortcutModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
            let hasShortcutModifier = !flags.intersection(shortcutModifiers).isEmpty
            let isFreshKeyDown = keyAge >= 0 && keyAge < 0.28 && (keyAge < self.lastObservedKeyAge - 0.004 || (self.lastObservedKeyAge.isInfinite && keyAge < 0.08))
            self.lastObservedKeyAge = keyAge

            if isFreshKeyDown && !hasShortcutModifier {
                self.handleTypingSignal(at: uptime, source: .typing, hidePointer: true, isPressedNow: isPressedNow, currentSpeed: currentSpeed)
            } else if self.configuration.smoothTypingCaretEnabled
                        && !hasShortcutModifier
                        && (uptime - self.lastTypingKeyDownUptime) < 0.14
                        && (uptime - self.lastCaretPollUptime) >= 0.024 {
                self.pollFocusedCaret(at: uptime, source: .typing)
            }

            let rawResizeKind = self.cursorHider.currentResizeCursorKind()
            let resizeKind = self.resolvedResizeCursorKind(rawResizeKind, at: livePos, isPressed: isPressedNow)
            let useNativeResize = self.configuration.enabled
                && self.configuration.showNativeResizeCursors
                && resizeKind != .none

            let overDock = self.isPointInDockEdgeBand(livePos)
            let nearDockEdge = self.cachedDockActiveBands.contains { $0.contains(livePos) }
            self.lastFrameNearDockEdge = nearDockEdge
            if overDock {
                self.lastOverDockUptime = uptime
            }
            let inDockGrace = nearDockEdge && (uptime - self.lastOverDockUptime) < 0.55
            let effectiveOverDock = overDock || inDockGrace
            self.lastFrameWasOverDock = effectiveOverDock
            let rawCrosshairActive = (resizeKind == .none) && self.cursorHider.isSystemCrosshairCursorActive()
            let specialCursorKind = (resizeKind == .none && !rawCrosshairActive) ? self.cursorHider.currentSpecialCursorKind() : .none
            let effectiveCrosshairActive = (resizeKind == .none)
                && (rawCrosshairActive || (self.isScreenshotCaptureActive && specialCursorKind != .screenshotWindow))
            let unknownCustomCursorActive = self.configuration.passThroughUnknownCustomCursors
                && !effectiveOverDock
                && !self.isScreenshotCaptureActive
                && resizeKind == .none
                && !effectiveCrosshairActive
                && specialCursorKind == .none
                && self.cursorHider.isUnknownCustomAppCursorActive()
            let iBeamActive = (resizeKind == .none) && !effectiveCrosshairActive && specialCursorKind == .none && !unknownCustomCursorActive && self.cursorHider.isSystemIBeamCursorActive()
            let iBeamChanged = iBeamActive != self.lastProbedIBeamActive
            self.lastProbedIBeamActive = iBeamActive
            self.hitTester.updateSystemIBeamActive(iBeamActive)

            self.engineLock.lock()
            self.engine.updateResizeCursor(useNativeResize ? .none : resizeKind)
            self.engine.updateSystemCrosshair(effectiveCrosshairActive)
            self.engine.updateSpecialCursor(specialCursorKind)
            self.engine.updateSystemIBeam(iBeamActive)
            let snappedToDock = self.lastHitTargetIsDock
            let snappedToNotification = self.lastHitTargetIsNotificationCenter
            self.engineLock.unlock()

            let ownRects = self.cachedOwnWindowRects
            let overOwnWindow = ownRects.contains { $0.contains(livePos) }

            if enabled && !isPressedNow && resizeKind == .none && !effectiveCrosshairActive && specialCursorKind == .none && !unknownCustomCursorActive {
                if overOwnWindow {
                    self.hitTester.reset()
                    self.engineLock.lock()
                    self.engine.updateHitTarget(nil)
                    self.engineLock.unlock()
                } else if iBeamChanged || (!(self.eventTapManager?.isRunning ?? false) && moved && (magnetism || iBeamActive)) {
                    self.hitTester.probe(at: livePos)
                }
            }

            let frontmost = self.frontmostBundleID
            let currentSeed = self.cursorHider.currentCursorSeed()
            let seedChangedForScan = currentSeed != 0 && currentSeed != self.lastWindowScanCursorSeed
            let unexpectedVisibleCursor = !self.isScreenshotCaptureActive
                && !effectiveOverDock
                && !useNativeResize
                && !unknownCustomCursorActive
                && !rawCrosshairActive
                && (uptime - self.lastExcludedWindowScanUptime) >= 0.05
                && self.cursorHider.isSystemCursorCurrentlyVisible()
            let hasCaptureOrExcluded = !self.excludedPIDs.isEmpty || !self.captureOverlayPIDs.isEmpty
            let minScanInterval: TimeInterval = (self.isScreenshotCaptureActive || effectiveCrosshairActive || effectiveOverDock || nearDockEdge) ? 0.05 : (hasCaptureOrExcluded ? 0.14 : 0.25)
            let periodicScanInterval: TimeInterval = (self.isScreenshotCaptureActive || effectiveCrosshairActive) ? 0.15 : (hasCaptureOrExcluded ? 0.35 : 1.5)
            let shouldScanNow = self.needsImmediateWindowScan
                || seedChangedForScan
                || unexpectedVisibleCursor
                || ((moved || (uptime - self.lastExcludedWindowScanUptime) >= periodicScanInterval)
                    && (uptime - self.lastExcludedWindowScanUptime) >= minScanInterval)
            if shouldScanNow {
                self.needsImmediateWindowScan = false
                self.lastWindowScanCursorSeed = currentSeed
                self.refreshVisibleWindowMap(at: uptime)
            }
            let excludedSet = self.excludedBundleIDSet
            let effectiveBundleID = self.resolvedEffectiveBundleID(at: livePos, frontmost: frontmost, excludedSet: excludedSet)
            let isExcludedApp = CursorHideSafetyPolicy.isExcludedApp(bundleID: effectiveBundleID, excludedBundleIDs: excludedSet)
            let captureOverlayMode = self.isScreenshotCaptureActive
                || rawCrosshairActive
                || specialCursorKind == .screenshotWindow
            self.overlayController.setElevatedAboveCaptureOverlays(false)
            let passThroughCustomOrCapture = unknownCustomCursorActive || captureOverlayMode
            if passThroughCustomOrCapture {
                self.hitTester.reset()
                self.engineLock.lock()
                self.engine.updateHitTarget(nil)
                self.engineLock.unlock()
            }
            self.overlayController.setCaptureSuspended(passThroughCustomOrCapture)

            self.cursorHider.updateSafetyState(
                overlayActive: self.overlayController.hasActiveOverlay,
                nativeResizeActive: useNativeResize,
                customAppCursorActive: passThroughCustomOrCapture,
                pausedForPermissionSetup: self.pausedForPermissionSetup,
                frontmostBundleID: effectiveBundleID,
                excludedBundleIDs: excludedSet
            )

            if useNativeResize
                || passThroughCustomOrCapture
                || isExcludedApp
                || self.pausedForPermissionSetup
                || CursorHideSafetyPolicy.isSensitiveSystemPrompt(bundleID: frontmost)
                || !self.overlayController.hasActiveOverlay {
                self.lastFrameWasExcludedOrNative = true
                return nil
            }
            self.lastFrameWasExcludedOrNative = false

            self.engineLock.lock()
            let state = self.engine.step(dt: dt, timestamp: uptime)
            self.engineLock.unlock()

            if self.configuration.enabled {
                let dockActiveNow = effectiveOverDock || snappedToDock
                if dockActiveNow {
                    self.lastOverDockUptime = uptime
                }
                let overNotification = snappedToNotification || self.isPointInNotificationHoverZone(livePos)
                self.cursorHider.ensureHiddenOnFrame(
                    at: uptime,
                    isOverDock: dockActiveNow,
                    isScreenshotCapture: captureOverlayMode,
                    needsHoverTrackingVisible: overNotification && !dockActiveNow
                )
            }

            return state
        }

        overlayController.onSmoothCaretFrame = { [weak self] dt, uptime in
            guard let self else { return .hidden }
            let enabled = self.configuration.enabled && self.configuration.smoothTypingCaretEnabled && !self.pausedForPermissionSetup
            guard enabled else {
                self.lastSmoothCaretVisible = false
                return .hidden
            }
            self.engineLock.lock()
            let isDark = self.engine.isDarkBackground
            let caretState = self.smoothCaretEngine.step(dt: dt, timestamp: uptime, enabled: enabled, isDarkBackground: isDark)
            self.engineLock.unlock()
            self.lastSmoothCaretVisible = caretState.isVisible
            return caretState
        }

        overlayController.onAfterFrame = { [weak self] uptime in
            guard let self else { return }
            self.evaluateIdlePause(at: uptime)
        }

        eventTapManager = EventTapManager(callbacks: .init(
            onMove: { [weak self] point, uptime, isTrackpad in
                guard let self else { return }
                self.wakeRenderLoop()
                self.engineLock.lock()
                let enabled = self.engine.configuration.enabled
                let magnetism = self.engine.configuration.magnetismEnabled
                let pressed = self.engine.isPressed
                self.engine.updatePointerPosition(point, timestamp: uptime, isTrackpad: isTrackpad)
                self.engineLock.unlock()

                let ownRects = self.cachedOwnWindowRects
                let overOwnWindow = ownRects.contains { $0.contains(point) }
                if overOwnWindow {
                    self.cancelDynamic3DFollowUpProbes()
                    self.hitTester.reset()
                    self.engineLock.lock()
                    self.engine.updateHitTarget(nil)
                    self.engineLock.unlock()
                } else if enabled && magnetism && !pressed && !self.isScreenshotCaptureActive {
                    self.hitTester.probe(at: point)
                    if self.hitTester.isLastHitInDynamic3DViewport {
                        self.scheduleDynamic3DFollowUpProbes(at: point)
                    } else if !self.dynamic3DFollowUpWorkItems.isEmpty {
                        self.cancelDynamic3DFollowUpProbes()
                    }
                }
            },
            onButton: { [weak self] pressed, point, uptime in
                guard let self else { return }
                self.wakeRenderLoop()
                self.cancelDynamic3DFollowUpProbes()
                self.engineLock.lock()
                let enabled = self.engine.configuration.enabled
                let magnetism = self.engine.configuration.magnetismEnabled
                self.engine.updatePointerPosition(point, timestamp: uptime)
                self.engine.setPressed(pressed, timestamp: uptime)
                self.engineLock.unlock()

                let ownRects = self.syncOwnWindowRects()
                let overOwnWindow = ownRects.contains { $0.contains(point) }
                if !self.excludedPIDs.isEmpty || !self.captureOverlayPIDs.isEmpty {
                    self.needsImmediateWindowScan = true
                }
                if !pressed && !overOwnWindow {
                    self.lastClickUptime = uptime
                    if !self.excludedPIDs.isEmpty || !self.captureOverlayPIDs.isEmpty {
                        let wasCapturing = self.isScreenshotCaptureActive
                        self.refreshVisibleWindowMap(at: uptime)
                        let delays: [TimeInterval] = wasCapturing ? [0.06, 0.20, 0.42] : [0.08, 0.22]
                        for delay in delays {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                                guard let self else { return }
                                self.refreshVisibleWindowMap(at: ProcessInfo.processInfo.systemUptime)
                                if !self.isScreenshotCaptureActive {
                                    self.wakeRenderLoop()
                                }
                            }
                        }
                    }
                    if self.configuration.smoothTypingCaretEnabled {
                        self.pollFocusedCaret(at: uptime, source: .mouseClick)
                        self.scheduleFollowUpCaretPolls(source: .mouseClick)
                    }
                }
                if overOwnWindow {
                    self.hitTester.reset()
                    self.engineLock.lock()
                    self.engine.updateHitTarget(nil)
                    self.engineLock.unlock()
                } else if !pressed && enabled && magnetism && !self.isScreenshotCaptureActive {
                    self.hitTester.invalidateSpatialCache()
                    self.hitTester.probe(at: point)
                }
            },
            onScroll: { [weak self] uptime, isTrackpad in
                guard let self else { return }
                self.wakeRenderLoop()
                self.cancelDynamic3DFollowUpProbes()
                self.hitTester.reset()
                self.engineLock.lock()
                self.engine.registerScrollOrActivity(timestamp: uptime, isTrackpad: isTrackpad)
                self.engineLock.unlock()
            },
            onKeyDown: { [weak self] uptime, flags, keyCode in
                guard let self else { return }
                // Mission Control / Exposé / Spaces shortcuts (F3=160, Ctrl+Arrows=123..126)
                let isSpaceOrMissionControlShortcut = (keyCode == 160)
                    || (flags.contains(.control) && (keyCode >= 123 && keyCode <= 126))
                if isSpaceOrMissionControlShortcut {
                    self.handleSpaceOrMissionControlWake(at: uptime)
                    return
                }
                let shortcutMask: NSEvent.ModifierFlags = [.command, .control, .option]
                // Esc (53), Return (36), Numpad Enter (76), Space (49) confirm/cancel/switch capture mode
                let captureControlKeys: Set<UInt16> = [53, 36, 76, 49]
                let isCaptureControlKey = self.isScreenshotCaptureActive && captureControlKeys.contains(keyCode)
                let isFunctionKey = (keyCode == 122 || keyCode == 120 || keyCode == 99 || keyCode == 118 || keyCode == 96 || keyCode == 97 || keyCode == 98 || keyCode == 100 || keyCode == 101 || keyCode == 109 || keyCode == 103 || keyCode == 111)
                if !flags.intersection(shortcutMask).isEmpty || isCaptureControlKey || isFunctionKey {
                    // Fast-check screenshot capture overlays (e.g. CleanShot X / macOS Cmd+Shift+4) right after hotkeys
                    self.keepAwake(for: 0.45)
                    self.wakeRenderLoop()
                    for delay in [0.005, 0.025, 0.08, 0.20, 0.42] as [TimeInterval] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard let self else { return }
                            self.refreshVisibleWindowMap(at: ProcessInfo.processInfo.systemUptime)
                            if !self.isScreenshotCaptureActive {
                                self.wakeRenderLoop()
                            }
                        }
                    }
                    return
                }
                self.wakeRenderLoop()
                // Arrow keys & navigation keys (left=123, right=124, down=125, up=126, home=115, end=119, pgup=116, pgdn=121)
                let navKeyCodes: Set<UInt16> = [115, 116, 119, 121, 123, 124, 125, 126]
                let isNavKey = navKeyCodes.contains(keyCode)
                self.engineLock.lock()
                let isPressedNow = self.engine.isPressed
                let currentSpeed = hypot(self.engine.smoothedVelocity.x, self.engine.smoothedVelocity.y)
                self.engineLock.unlock()
                self.handleTypingSignal(
                    at: uptime,
                    source: isNavKey ? .keyboardNavigation : .typing,
                    hidePointer: true,
                    isPressedNow: isPressedNow,
                    currentSpeed: currentSpeed
                )
            },
            onSystemGesture: { [weak self] uptime in
                guard let self else { return }
                self.handleSpaceOrMissionControlWake(at: uptime)
            },
            onToggleShortcut: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.toggleEnabled()
                }
            }
        ))

        overlayController.start()

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                self?.handleFrontmostAppChanged(bundleID)
            }
        }

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildRunningAppCache()
                self?.refreshVisibleWindowMap(at: ProcessInfo.processInfo.systemUptime)
            }
        }

        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildRunningAppCache()
                self?.refreshVisibleWindowMap(at: ProcessInfo.processInfo.systemUptime)
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreenGeometry()
                self?.cursorHider.handleDisplayConfigurationChanged()
                self?.overlayController.bringOverlaysToFront()
                self?.keepAwake(for: 0.6)
                self?.wakeRenderLoop()
            }
        }

        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissions()
                self?.refreshSystemZoomAndFullscreenState()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        statusPollTimer = timer
        refreshSystemZoomAndFullscreenState()
        refreshSystemDarkAppearance()
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshSystemDarkAppearance()
            }
        }
    }

    private func refreshSystemDarkAppearance() {
        let isDark = (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
        engineLock.lock()
        engine.updateSystemDarkAppearance(isDark)
        engineLock.unlock()
    }

    private func handleFrontmostAppChanged(_ bundleID: String?) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let resolved = bundleID ?? frontApp?.bundleIdentifier
        frontmostBundleID = resolved
        if let resolved, resolved != Bundle.main.bundleIdentifier {
            frontmostAppBundleID = resolved
            frontmostAppName = frontApp?.localizedName ?? resolved
        }
        engineLock.lock()
        smoothCaretEngine.reset()
        engineLock.unlock()
        refreshVisibleWindowMap(at: ProcessInfo.processInfo.systemUptime)
        attachTypingAXObserver(for: frontApp?.processIdentifier)
        if pausedForPermissionSetup,
           resolved != "com.apple.systempreferences",
           !CursorHideSafetyPolicy.isSensitiveSystemPrompt(bundleID: resolved) {
            pausedForPermissionSetup = false
        }
        syncSafetyAndOverlayState()
        overlayController.bringOverlaysToFront()
        wakeRenderLoop()
    }

    private func keepAwake(for duration: TimeInterval) {
        keepAwakeUntilUptime = max(keepAwakeUntilUptime, ProcessInfo.processInfo.systemUptime + duration)
    }

    private func cancelDynamic3DFollowUpProbes() {
        for item in dynamic3DFollowUpWorkItems {
            item.cancel()
        }
        dynamic3DFollowUpWorkItems.removeAll(keepingCapacity: true)
    }

    private func scheduleDynamic3DFollowUpProbes(at point: CGPoint) {
        cancelDynamic3DFollowUpProbes()
        let delays: [TimeInterval] = [0.045, 0.115]
        for delay in delays {
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.engineLock.lock()
                let enabled = self.engine.configuration.enabled
                let magnetism = self.engine.configuration.magnetismEnabled
                let pressed = self.engine.isPressed
                let curPos = self.engine.modelCursorPosition
                self.engineLock.unlock()
                guard enabled, magnetism, !pressed, !self.pausedForPermissionSetup else { return }
                guard hypot(curPos.x - point.x, curPos.y - point.y) <= 6.0 else { return }
                self.hitTester.probe(at: curPos)
            }
            dynamic3DFollowUpWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func handleSpaceOrMissionControlWake(at uptime: TimeInterval) {
        hitTester.reset()
        engineLock.lock()
        engine.updateHitTarget(nil)
        engine.markNeedsAnimation()
        engineLock.unlock()
        refreshVisibleWindowMap(at: uptime)
        refreshScreenGeometry()
        overlayController.bringOverlaysToFront()
        keepAwake(for: 0.75)
        wakeRenderLoop()
    }

    private func wakeRenderLoop() {
        autohideWakeTimer?.invalidate()
        autohideWakeTimer = nil
        cursorHider.setOverlayIdlePaused(false)
        if overlayController.isDisplayLinkPaused && (!excludedPIDs.isEmpty || !captureOverlayPIDs.isEmpty) {
            needsImmediateWindowScan = true
        }
        if configuration.enabled && !pausedForPermissionSetup {
            overlayController.wakeDisplayLink()
        }
    }

    private func evaluateIdlePause(at uptime: TimeInterval) {
        guard configuration.enabled, !pausedForPermissionSetup else {
            overlayController.setDisplayLinkPaused(true)
            cursorHider.setOverlayIdlePaused(false)
            return
        }
        guard !lastSmoothCaretVisible else { return }
        guard uptime >= keepAwakeUntilUptime else { return }
        if lastFrameWasExcludedOrNative {
            let sinceMove: TimeInterval
            engineLock.lock()
            sinceMove = uptime - engine.lastInteractionTimestamp
            engineLock.unlock()
            if sinceMove >= 0.35 {
                overlayController.setDisplayLinkPaused(true)
                cursorHider.setOverlayIdlePaused(false)
            }
            return
        }

        engineLock.lock()
        let settled = engine.isIdleSettled(at: uptime)
        let sinceDockActivity = uptime - engine.lastInteractionTimestamp
        let nextAutohide = engine.nextAutohideDelay(at: uptime)
        engineLock.unlock()

        guard settled else { return }
        if lastFrameWasOverDock && sinceDockActivity < 0.75 {
            return
        }

        overlayController.setDisplayLinkPaused(true)
        cursorHider.setOverlayIdlePaused(true)

        autohideWakeTimer?.invalidate()
        autohideWakeTimer = nil
        if let delay = nextAutohide {
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.wakeRenderLoop()
                }
            }
            timer.tolerance = min(0.25, delay * 0.15)
            RunLoop.main.add(timer, forMode: .common)
            autohideWakeTimer = timer
        }
    }

    private func handleTypingSignal(
        at uptime: TimeInterval,
        source: CaretMoveSource,
        hidePointer: Bool,
        isPressedNow: Bool,
        currentSpeed: CGFloat
    ) {
        lastTypingKeyDownUptime = uptime
        if hidePointer && configuration.hideWhileTyping && !isPressedNow && currentSpeed < 180.0 {
            wakeRenderLoop()
            hitTester.reset()
            engineLock.lock()
            engine.updateHitTarget(nil)
            engine.hideForTyping(at: uptime)
            engineLock.unlock()
        }
        if configuration.smoothTypingCaretEnabled {
            keepAwake(for: 0.65)
            wakeRenderLoop()
            pollFocusedCaret(at: uptime, source: source)
            scheduleFollowUpCaretPolls(source: source)
        }
    }

    private func handleAXTextNotification(isValueChange: Bool) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let recentClick = (uptime - lastClickUptime) < 0.60
        let hidKeyAge = min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        )
        let recentKey = (uptime - lastTypingKeyDownUptime) < 1.50 || (hidKeyAge >= 0 && hidKeyAge < 1.50)
        // Ignore unsolicited AX text/value mutations (e.g. LLM streaming, logs, clocks) when the user is not typing or clicking.
        guard recentKey || recentClick else { return }
        if recentKey {
            lastTypingKeyDownUptime = uptime
        }
        engineLock.lock()
        let isPressedNow = engine.isPressed
        let currentSpeed = hypot(engine.smoothedVelocity.x, engine.smoothedVelocity.y)
        engineLock.unlock()

        if isValueChange {
            guard recentKey else { return }
            handleTypingSignal(
                at: uptime,
                source: .typing,
                hidePointer: true,
                isPressedNow: isPressedNow,
                currentSpeed: currentSpeed
            )
        } else if configuration.smoothTypingCaretEnabled {
            keepAwake(for: 0.65)
            wakeRenderLoop()
            let source: CaretMoveSource = recentClick ? .mouseClick : (recentKey ? .keyboardNavigation : .mouseClick)
            pollFocusedCaret(at: uptime, source: source)
        }
    }

    private func attachTypingAXObserver(for pid: pid_t?) {
        let needObserver = configuration.enabled && (configuration.hideWhileTyping || configuration.smoothTypingCaretEnabled)
        let wantSelection = configuration.smoothTypingCaretEnabled
        guard needObserver, AXIsProcessTrusted(), let pid, pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
            detachTypingAXObserver()
            return
        }
        if pid == typingAXObservedPID, typingAXObserver != nil, typingAXObservingSelection == wantSelection {
            return
        }
        detachTypingAXObserver()

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<PointerController>.fromOpaque(refcon).takeUnretainedValue()
            let notifName = notification as String
            let isValueChange = (notifName == (kAXValueChangedNotification as String))
            DispatchQueue.main.async {
                controller.handleAXTextNotification(isValueChange: isValueChange)
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            return
        }
        let appEl = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(observer, appEl, kAXValueChangedNotification as CFString, refcon)
        if wantSelection {
            _ = AXObserverAddNotification(observer, appEl, kAXSelectedTextChangedNotification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        typingAXObserver = observer
        typingAXObservedPID = pid
        typingAXObservedAppElement = appEl
        typingAXObservingSelection = wantSelection
    }

    private func detachTypingAXObserver() {
        if let observer = typingAXObserver {
            if let appEl = typingAXObservedAppElement {
                _ = AXObserverRemoveNotification(observer, appEl, kAXValueChangedNotification as CFString)
                _ = AXObserverRemoveNotification(observer, appEl, kAXSelectedTextChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            typingAXObserver = nil
        }
        typingAXObservedPID = 0
        typingAXObservedAppElement = nil
        typingAXObservingSelection = false
    }

    private func rebuildRunningAppCache() {
        let excludedSet = Set(configuration.excludedBundleIDs)
        excludedBundleIDSet = excludedSet
        var map: [pid_t: String] = [:]
        var exPIDs: Set<pid_t> = []
        var capPIDs: Set<pid_t> = []
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier {
                let pid = app.processIdentifier
                map[pid] = bid
                if bid == "com.apple.dock" {
                    dockPID = pid
                }
                if excludedSet.contains(bid) {
                    exPIDs.insert(pid)
                }
                if CursorHideSafetyPolicy.screenshotCaptureBundleIDs.contains(bid) {
                    capPIDs.insert(pid)
                }
            }
        }
        pidToBundleID = map
        excludedPIDs = exPIDs
        captureOverlayPIDs = capPIDs
        if exPIDs.isEmpty {
            visibleNormalWindows = []
            excludedAppHasOnScreenWindow = []
        }
        if capPIDs.isEmpty {
            isScreenshotCaptureActive = false
        }
    }

    private func refreshVisibleWindowMap(at uptime: TimeInterval) {
        lastExcludedWindowScanUptime = uptime
        guard let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            visibleNormalWindows = []
            excludedAppHasOnScreenWindow = []
            isMissionControlLikelyActive = false
            isScreenshotCaptureActive = false
            hitTester.updateStageManagerCards([])
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var entries: [(rect: CGRect, bundleID: String)] = []
        var excludedWithVisibleWindows: Set<String> = []
        var dockRects: [CGRect] = []
        var resizeWindowRects: [CGRect] = []
        var notificationHoverRects: [CGRect] = []
        var stageCards: [StageManagerCardWindow] = []
        var frontOccludingRects: [CGRect] = []
        let screenRects = cachedScreenQuartzRects
        let screenSizes = screenRects.map(\.size)
        var missionControlDetected = false
        var screenshotCaptureDetected = false
        var videoRecordingHUDDetected = false
        var cleanShotAllInOneToolbarDetected = false
        var hasShieldingCaptureWindow = false
        var dockOverlayScreenRects: [CGRect] = []
        for w in wins {
            guard let layer = w[kCGWindowLayer as String] as? Int,
                  let bDict = w[kCGWindowBounds as String] as? [String: Any],
                  let x = bDict["X"] as? CGFloat,
                  let y = bDict["Y"] as? CGFloat,
                  let width = bDict["Width"] as? CGFloat,
                  let height = bDict["Height"] as? CGFloat else {
                continue
            }
            let ownerName = w[kCGWindowOwnerName as String] as? String ?? ""
            let winName = w[kCGWindowName as String] as? String ?? ""
            if layer >= 18,
               ownerName == "Dock",
               winName != "Dock",
               width >= 600.0, height >= 400.0 {
                missionControlDetected = true
            }
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 0.0
            let pid = (w[kCGWindowOwnerPID as String] as? pid_t) ?? 0
            if pid == ownPID { continue }
            let bid = pidToBundleID[pid] ?? (ownerName == "Window Server" ? "com.apple.windowserver" : nil)
            if captureOverlayPIDs.contains(pid) || CursorHideSafetyPolicy.isScreenshotCaptureOwner(bundleID: bid, ownerName: ownerName) {
                if CursorHideSafetyPolicy.isActiveVideoRecordingHUDWindow(
                    bundleID: bid,
                    ownerName: ownerName,
                    layer: layer,
                    width: width,
                    height: height,
                    alpha: alpha
                ) {
                    videoRecordingHUDDetected = true
                }
                if CursorHideSafetyPolicy.isCleanShotAllInOneToolbarWindow(
                    bundleID: bid,
                    ownerName: ownerName,
                    layer: layer,
                    width: width,
                    height: height,
                    alpha: alpha
                ) {
                    cleanShotAllInOneToolbarDetected = true
                }
                if layer >= 1000 && max(width, height) >= 20.0 && width >= 1.0 && height >= 1.0 {
                    hasShieldingCaptureWindow = true
                }
                if !screenshotCaptureDetected,
                   CursorHideSafetyPolicy.isActiveScreenshotCaptureWindow(
                       bundleID: bid,
                       ownerName: ownerName,
                       layer: layer,
                       width: width,
                       height: height,
                       alpha: alpha,
                       screenSizes: screenSizes
                   ) {
                    screenshotCaptureDetected = true
                }
            }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            if ownerName == "WindowManager",
               layer >= 0 && layer <= 25,
               width >= 56.0 && width <= 420.0,
               height >= 44.0 && height <= 420.0,
               (winName == "Gesture Blocking Overlay" || alpha > 0.01) {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                if let screen = screenRects.first(where: { $0.contains(center) }) ?? screenRects.first {
                    let tiltRad: CGFloat = 24.0 * .pi / 180.0
                    if center.x < screen.minX + screen.width * 0.35 {
                        stageCards.append(StageManagerCardWindow(
                            rect: rect,
                            tiltY: tiltRad,
                            occludingRects: frontOccludingRects
                        ))
                    } else if center.x > screen.maxX - screen.width * 0.35 {
                        stageCards.append(StageManagerCardWindow(
                            rect: rect,
                            tiltY: -tiltRad,
                            occludingRects: frontOccludingRects
                        ))
                    }
                }
                continue
            }
            if alpha > 0.05 && width > 16.0 && height > 16.0 && layer >= 0 && layer <= 26 {
                if ownerName != "WindowManager" {
                    frontOccludingRects.append(rect)
                }
            }
            guard alpha > 0.01,
                  width > 16.0, height > 16.0 else {
                continue
            }
            if ownerName == "Dock" && layer == 20 {
                if width < 260.0 || height < 260.0 {
                    dockRects.append(CGRect(x: x, y: y, width: width, height: height).insetBy(dx: -28.0, dy: -32.0))
                } else if winName == "Dock" || winName.isEmpty {
                    // macOS 26/27 renders the active Dock glass bar inside a fullscreen layer-20 "Dock" window.
                    dockOverlayScreenRects.append(rect)
                }
            }
            if layer == 0 && width >= 80.0 && height >= 80.0 && ownerName != "WindowManager" && ownerName != "Dock" {
                resizeWindowRects.append(rect)
            }
            if (ownerName == "Notification Center"
                || ownerName == "NotificationCenter"
                || bid == "com.apple.notificationcenterui"
                || bid == "com.apple.UserNotificationCenter"),
               layer >= 18 {
                if width <= 640.0 && height <= 640.0 {
                    notificationHoverRects.append(rect.insetBy(dx: -40.0, dy: -40.0))
                } else {
                    // macOS 26/27 Notification Center renders banners inside a fullscreen layer-23 overlay;
                    // track the right-hand 460pt banner/tray strip on that display.
                    let stripW = min(460.0, width)
                    notificationHoverRects.append(CGRect(x: rect.maxX - stripW, y: rect.minY, width: stripW, height: height))
                }
            }
            guard !excludedPIDs.isEmpty else { continue }
            guard let bid else { continue }
            let isExcludedOwner = excludedPIDs.contains(pid)
            let isDockBar = (bid == "com.apple.dock" || ownerName == "Dock") && layer == 20 && (width < 260.0 || height < 260.0)
            let isNotificationBanner = (bid == "com.apple.notificationcenterui" || bid == "com.apple.UserNotificationCenter")
                && layer >= 18 && width < 600.0 && height < 600.0
            let isMenuBar = (ownerName == "Window Server" && layer == 24 && height <= 50.0)
            let isNotchUtility = (layer == 26 && width < 600.0 && height < 600.0)
            guard layer == 0 || isExcludedOwner || isDockBar || isNotificationBanner || isMenuBar || isNotchUtility else {
                continue
            }
            entries.append((rect, bid))
            if isExcludedOwner {
                excludedWithVisibleWindows.insert(bid)
            }
        }
        if !dockOverlayScreenRects.isEmpty || lastFrameNearDockEdge {
            if let axDock = queryLiveDockBarRect() {
                lastKnownVisibleDockRect = axDock
                lastKnownVisibleDockUptime = uptime
                dockRects.append(axDock.insetBy(dx: -36.0, dy: -40.0))
            } else if let cachedDock = lastKnownVisibleDockRect,
                      (uptime - lastKnownVisibleDockUptime) < 0.60 {
                dockRects.append(cachedDock.insetBy(dx: -36.0, dy: -40.0))
            }
            for overlayRect in dockOverlayScreenRects {
                dockRects.append(activeDockBand(forScreenRect: overlayRect, thickness: 132.0))
            }
        } else if (uptime - lastKnownVisibleDockUptime) >= 0.60 {
            lastKnownVisibleDockRect = nil
        }
        // When CleanShot X is actively recording video (its compact recording HUD is on screen and
        // no shielding-level capture/crosshair overlay is active) or in Cmd+Shift+5 All-in-One video bar mode
        // (without shielding capture windows or crosshair cursor), keep ApplePointer active so Cmd+Shift+5 and recorded videos show ApplePointer
        // rather than falling back to the native system arrow.
        if (videoRecordingHUDDetected || cleanShotAllInOneToolbarDetected) && !hasShieldingCaptureWindow && !cursorHider.isSystemCrosshairCursorActive() {
            screenshotCaptureDetected = false
        }
        let captureTransitioned = screenshotCaptureDetected != isScreenshotCaptureActive
        isMissionControlLikelyActive = missionControlDetected
        isScreenshotCaptureActive = screenshotCaptureDetected
        excludedAppHasOnScreenWindow = excludedWithVisibleWindows
        visibleNormalWindows = entries
        onScreenDockRects = dockRects
        onScreenResizeWindowRects = resizeWindowRects
        onScreenNotificationHoverRects = notificationHoverRects
        hitTester.updateStageManagerCards(stageCards)
        if captureTransitioned {
            overlayController.setElevatedAboveCaptureOverlays(false)
            overlayController.setCaptureSuspended(screenshotCaptureDetected)
            updateCaptureMonitorTimer(active: screenshotCaptureDetected)
            if screenshotCaptureDetected {
                hitTester.reset()
                engineLock.lock()
                engine.updateHitTarget(nil)
                engineLock.unlock()
                cursorHider.releaseHidingForExternalApp()
                syncSafetyAndOverlayState()
            } else {
                cursorHider.invalidateCursorClassificationCache()
                cursorHider.refreshHeartbeat(at: uptime)
                engineLock.lock()
                engine.wakeFromAutohide()
                engine.markNeedsAnimation()
                engineLock.unlock()
                syncSafetyAndOverlayState()
                overlayController.bringOverlaysToFront()
                keepAwake(for: 0.45)
                wakeRenderLoop()
            }
        }
    }

    private func updateCaptureMonitorTimer(active: Bool) {
        if active {
            guard captureMonitorTimer == nil else { return }
            let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    self.refreshVisibleWindowMap(at: now)
                    if !self.isScreenshotCaptureActive {
                        self.wakeRenderLoop()
                    }
                }
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            captureMonitorTimer = timer
        } else {
            captureMonitorTimer?.invalidate()
            captureMonitorTimer = nil
        }
    }

    private func resolvedEffectiveBundleID(at quartzPoint: CGPoint, frontmost: String?, excludedSet: Set<String>) -> String? {
        if isMissionControlLikelyActive {
            return nil
        }
        if !excludedPIDs.isEmpty {
            if let hoveredBundleID = hoveredNormalWindowBundleID(at: quartzPoint) {
                return hoveredBundleID
            }
            if let frontmost,
               excludedSet.contains(frontmost),
               excludedAppHasOnScreenWindow.contains(frontmost) {
                // Cursor is outside all visible windows of the excluded frontmost app (e.g. Desktop / Dock edge).
                return nil
            }
        }
        return frontmost
    }

    private func refreshScreenGeometry() {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        var notchRects: [CGRect] = []
        var dockBands: [CGRect] = []
        var dockActiveBands: [CGRect] = []
        var screenQuartzRects: [CGRect] = []
        let dockPrefs = UserDefaults(suiteName: "com.apple.dock")
        let dockOrientation = dockPrefs?.string(forKey: "orientation") ?? "bottom"
        let dockAutoHide = dockPrefs?.bool(forKey: "autohide") ?? false
        let dockTileSize = CGFloat(dockPrefs?.double(forKey: "tilesize") ?? 56.0)
        let dockLargeSize = CGFloat(dockPrefs?.double(forKey: "largesize") ?? Double(dockTileSize))
        let activeThickness = max(126.0, max(dockTileSize, dockLargeSize) + 64.0)
        cachedDockOrientation = dockOrientation
        for screen in NSScreen.screens {
            let frame = screen.frame
            let qMinX = frame.minX
            let qMinY = primaryHeight - frame.maxY
            let qRect = CGRect(x: qMinX, y: qMinY, width: frame.width, height: frame.height)
            screenQuartzRects.append(qRect)
            // Keep the Dock trigger band strictly on the configured Dock edge so normal app text inputs
            // near the bottom (e.g. Codex prompt bar) never trigger Dock cursor hiding while auto-hidden.
            let bandThickness: CGFloat = dockAutoHide ? 20.0 : activeThickness
            dockBands.append(activeDockBand(forScreenRect: qRect, thickness: bandThickness))
            dockActiveBands.append(activeDockBand(forScreenRect: qRect, thickness: activeThickness))

            if #available(macOS 12.0, *) {
                let safeTop = screen.safeAreaInsets.top
                if safeTop > 4.0,
                   let auxL = screen.auxiliaryTopLeftArea,
                   let auxR = screen.auxiliaryTopRightArea {
                    let notchWidth = auxR.minX - auxL.maxX
                    if notchWidth >= 40.0 && notchWidth <= 420.0 {
                        let notchQuartz = CGRect(x: auxL.maxX, y: primaryHeight - frame.maxY, width: notchWidth, height: safeTop)
                        notchRects.append(notchQuartz)
                    }
                }
            }
        }
        cachedDockEdgeBands = dockBands
        cachedDockActiveBands = dockActiveBands
        cachedScreenQuartzRects = screenQuartzRects
        hitTester.updateCameraNotchRects(notchRects)
        hitTester.updateScreenQuartzRects(screenQuartzRects)
    }

    private func activeDockBand(forScreenRect qRect: CGRect, thickness: CGFloat) -> CGRect {
        switch cachedDockOrientation {
        case "left":
            return CGRect(x: qRect.minX, y: qRect.minY, width: thickness, height: qRect.height)
        case "right":
            return CGRect(x: qRect.maxX - thickness, y: qRect.minY, width: thickness, height: qRect.height)
        default:
            return CGRect(x: qRect.minX, y: qRect.maxY - thickness, width: qRect.width, height: thickness)
        }
    }

    /// Reads the live on-screen bounds of the Dock's AXList (e.g. when an auto-hidden Dock slides in).
    private func queryLiveDockBarRect() -> CGRect? {
        guard dockPID > 0, AXIsProcessTrusted() else { return nil }
        let appEl = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(appEl, 0.02)
        var childrenVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXChildrenAttribute as CFString, &childrenVal) == .success,
              let children = childrenVal as? [AXUIElement] else {
            return nil
        }
        for child in children {
            var roleVal: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleVal) == .success,
                  (roleVal as? String) == "AXList" else {
                continue
            }
            var posVal: CFTypeRef?
            var sizeVal: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posVal) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeVal) == .success,
                  let pAX = posVal, let sAX = sizeVal,
                  CFGetTypeID(pAX) == AXValueGetTypeID(),
                  CFGetTypeID(sAX) == AXValueGetTypeID() else {
                continue
            }
            var pt = CGPoint.zero
            var sz = CGSize.zero
            guard AXValueGetValue(unsafeDowncast(pAX, to: AXValue.self), .cgPoint, &pt),
                  AXValueGetValue(unsafeDowncast(sAX, to: AXValue.self), .cgSize, &sz),
                  sz.width > 20.0, sz.height > 20.0 else {
                continue
            }
            let r = CGRect(origin: pt, size: sz)
            // Only treat as visible when intersecting a display (hidden auto-hide Dock sits off-edge).
            if cachedScreenQuartzRects.contains(where: {
                let overlap = $0.intersection(r)
                return !overlap.isNull && overlap.width > 2.0 && overlap.height > 2.0
            }) {
                return r
            }
        }
        return nil
    }

    private func isPointInDockEdgeBand(_ point: CGPoint) -> Bool {
        cachedDockEdgeBands.contains { $0.contains(point) }
            || onScreenDockRects.contains { $0.contains(point) }
    }

    private func isPointInNotificationHoverZone(_ point: CGPoint) -> Bool {
        onScreenNotificationHoverRects.contains { $0.contains(point) }
    }

    /// Resolves ambiguous two-way diagonal resize cursors (NWSE / NESW) to the exact window corner
    /// (NW, NE, SW, SE) so the curved iPadOS corner resize glyph always hugs the hovered window corner.
    private func resolvedResizeCursorKind(
        _ rawKind: ResizeCursorKind,
        at point: CGPoint,
        isPressed: Bool
    ) -> ResizeCursorKind {
        guard rawKind != .none else {
            lockedDragResizeKind = .none
            return .none
        }
        if isPressed && lockedDragResizeKind != .none {
            return lockedDragResizeKind
        }
        guard rawKind == .diagonalNWSE || rawKind == .diagonalNESW else {
            lockedDragResizeKind = rawKind
            return rawKind
        }

        var bestKind: ResizeCursorKind = rawKind
        var bestDist: CGFloat = 34.0
        for rect in onScreenResizeWindowRects {
            guard rect.insetBy(dx: -28.0, dy: -28.0).contains(point) else { continue }
            if rawKind == .diagonalNWSE {
                let dNW = hypot(point.x - rect.minX, point.y - rect.minY)
                let dSE = hypot(point.x - rect.maxX, point.y - rect.maxY)
                if dNW <= dSE && dNW < bestDist {
                    bestDist = dNW
                    bestKind = .cornerNW
                } else if dSE < dNW && dSE < bestDist {
                    bestDist = dSE
                    bestKind = .cornerSE
                }
            } else {
                let dNE = hypot(point.x - rect.maxX, point.y - rect.minY)
                let dSW = hypot(point.x - rect.minX, point.y - rect.maxY)
                if dNE <= dSW && dNE < bestDist {
                    bestDist = dNE
                    bestKind = .cornerNE
                } else if dSW < dNE && dSW < bestDist {
                    bestDist = dSW
                    bestKind = .cornerSW
                }
            }
            if bestDist < 18.0 {
                break
            }
        }
        lockedDragResizeKind = bestKind
        return bestKind
    }

    private func hoveredNormalWindowBundleID(at quartzPoint: CGPoint) -> String? {
        for entry in visibleNormalWindows {
            if entry.rect.contains(quartzPoint) {
                return entry.bundleID
            }
        }
        return nil
    }

    private func refreshPermissions() {
        accessibilityGranted = AccessibilityHitTester.isAccessibilityGranted()
        if accessibilityGranted && pausedForPermissionSetup {
            pausedForPermissionSetup = false
            syncSafetyAndOverlayState()
        }
        if configuration.enabled && !(eventTapManager?.isRunning ?? false) {
            _ = eventTapManager?.start()
        }
        mouseTrackingActive = eventTapManager?.isRunning ?? false
    }

    /// Polls macOS Universal Access zoom level and fullscreen media window state at a light 0.5Hz cadence.
    private func refreshSystemZoomAndFullscreenState() {
        let ua = UserDefaults(suiteName: "com.apple.universalaccess")
        let zoomed = ua?.bool(forKey: "closeViewZoomed") ?? false
        let rawFactor = ua?.double(forKey: "closeViewZoomFactor") ?? 1.0
        let zoomFactor: CGFloat = (zoomed && rawFactor > 1.05) ? CGFloat(rawFactor) : 1.0

        var isFullscreenMedia = false
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bid = frontApp.bundleIdentifier,
           Self.mediaPlayerBundleIDs.contains(bid) {
            let pid = frontApp.processIdentifier
            if let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                let screenSizes = NSScreen.screens.map { $0.frame.size }
                for w in wins where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
                    if let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                       let bDict = w[kCGWindowBounds as String] as? [String: Any],
                       let bw = bDict["Width"] as? CGFloat,
                       let bh = bDict["Height"] as? CGFloat {
                        if screenSizes.contains(where: { abs($0.width - bw) <= 2.0 && abs($0.height - bh) <= 2.0 }) {
                            isFullscreenMedia = true
                            break
                        }
                    }
                }
            }
        }

        engineLock.lock()
        engine.updateAccessibilityZoomFactor(zoomFactor)
        engine.updateFullscreenVideoActive(isFullscreenMedia)
        engineLock.unlock()
    }

    private func applyConfiguration() {
        engineLock.lock()
        engine.configuration = configuration
        engine.markNeedsAnimation()
        if !configuration.magnetismEnabled {
            engine.updateHitTarget(nil)
        }
        engineLock.unlock()

        rebuildRunningAppCache()
        refreshVisibleWindowMap(at: ProcessInfo.processInfo.systemUptime)
        attachTypingAXObserver(for: NSWorkspace.shared.frontmostApplication?.processIdentifier)

        if configuration.enabled {
            _ = eventTapManager?.start()
            mouseTrackingActive = eventTapManager?.isRunning ?? false
            cursorHider.start()
            syncSafetyAndOverlayState()
            wakeRenderLoop()
        } else {
            pausedForPermissionSetup = false
            hitTester.reset()
            cursorHider.stop()
            engineLock.lock()
            smoothCaretEngine.reset()
            engineLock.unlock()
            autohideWakeTimer?.invalidate()
            autohideWakeTimer = nil
            overlayController.setVisible(false)
        }
    }

    private func pollFocusedCaret(at uptime: TimeInterval, source: CaretMoveSource) {
        if source != .mouseClick && (uptime - lastCaretPollUptime) < 0.018 {
            return
        }
        lastCaretPollUptime = uptime
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier
        let bid = frontApp.bundleIdentifier
        let excludedSet = Set(configuration.excludedBundleIDs)
        if CursorHideSafetyPolicy.isExcludedApp(bundleID: bid, excludedBundleIDs: excludedSet) {
            engineLock.lock()
            smoothCaretEngine.updateTargetCaret(nil, at: uptime, source: source)
            engineLock.unlock()
            return
        }
        hitTester.queryFocusedCaretAsync(frontmostPID: pid, bundleID: bid) { [weak self] rect in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.engineLock.lock()
            let gliding = self.smoothCaretEngine.updateTargetCaret(rect, at: now, source: source)
            self.engineLock.unlock()
            if gliding {
                DispatchQueue.main.async { [weak self] in
                    self?.keepAwake(for: 0.35)
                    self?.wakeRenderLoop()
                }
            }
        }
    }

    private func scheduleFollowUpCaretPolls(source: CaretMoveSource) {
        for delay in [0.020, 0.065, 0.130] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.configuration.enabled, self.configuration.smoothTypingCaretEnabled else { return }
                self.pollFocusedCaret(at: ProcessInfo.processInfo.systemUptime, source: source)
            }
        }
    }

    private func saveConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func loadConfiguration() -> PointerConfiguration {
        var loaded: PointerConfiguration
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(PointerConfiguration.self, from: data) {
            loaded = decoded
        } else if let legacyData = UserDefaults.standard.data(forKey: legacyDefaultsKey),
                  let decoded = try? JSONDecoder().decode(PointerConfiguration.self, from: legacyData) {
            loaded = decoded
        } else {
            loaded = PointerConfiguration()
        }
        if !UserDefaults.standard.bool(forKey: screenContinuityMigratedKey) {
            UserDefaults.standard.set(true, forKey: screenContinuityMigratedKey)
            if !loaded.excludedBundleIDs.contains("com.apple.ScreenContinuity") {
                loaded.excludedBundleIDs.append("com.apple.ScreenContinuity")
            }
        }
        if !UserDefaults.standard.bool(forKey: smoothCaretDefaultOffMigratedKey) {
            UserDefaults.standard.set(true, forKey: smoothCaretDefaultOffMigratedKey)
            loaded.smoothTypingCaretEnabled = false
        }
        return loaded
    }
}
