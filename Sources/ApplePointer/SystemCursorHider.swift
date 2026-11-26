import AppKit
import ApplePointerCore
import CoreGraphics
import Foundation

final class SystemCursorHider: @unchecked Sendable {
    typealias ConnectionID = UInt32
    private typealias MainConnectionFn = @convention(c) () -> ConnectionID
    private typealias SetConnectionPropertyFn = @convention(c) (ConnectionID, ConnectionID, CFString, CFTypeRef) -> CGError
    private typealias NoArgBoolFn = @convention(c) () -> Int32
    private typealias ConnBoolFn = @convention(c) (ConnectionID) -> Bool
    private typealias ConnErrFn = @convention(c) (ConnectionID) -> CGError
    private typealias SeedFn = @convention(c) () -> Int32

    private struct SkyLightBindings: @unchecked Sendable {
        let mainConnection: MainConnectionFn?
        let setConnectionProperty: SetConnectionPropertyFn?
        let cgCursorIsVisible: NoArgBoolFn?
        let slsCursorIsVisible: ConnBoolFn?
        let slsCurrentCursorSeed: SeedFn?
        let slsForceShowCursor: ConnErrFn?
        let slsHideCursor: ConnErrFn?
        let slsShowCursor: ConnErrFn?
        let slsObscureCursor: ConnErrFn?
        let slsRevealCursor: ConnErrFn?

        static let shared = SkyLightBindings()

        private init() {
            let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
            let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

            func load(_ names: [String]) -> UnsafeMutableRawPointer? {
                for name in names {
                    if let skyLight, let sym = dlsym(skyLight, name) {
                        return sym
                    }
                    if let sym = dlsym(rtldDefault, name) {
                        return sym
                    }
                }
                return nil
            }

            mainConnection = load(["CGSMainConnectionID", "_CGSDefaultConnection"]).map {
                unsafeBitCast($0, to: MainConnectionFn.self)
            }
            setConnectionProperty = load(["CGSSetConnectionProperty", "SLSSetConnectionProperty"]).map {
                unsafeBitCast($0, to: SetConnectionPropertyFn.self)
            }
            cgCursorIsVisible = load(["CGCursorIsVisible"]).map {
                unsafeBitCast($0, to: NoArgBoolFn.self)
            }
            slsCursorIsVisible = load(["SLSCursorIsVisible"]).map {
                unsafeBitCast($0, to: ConnBoolFn.self)
            }
            slsCurrentCursorSeed = load(["SLSCurrentCursorSeed", "CGSCurrentCursorSeed"]).map {
                unsafeBitCast($0, to: SeedFn.self)
            }
            slsForceShowCursor = load(["SLSForceShowCursor"]).map {
                unsafeBitCast($0, to: ConnErrFn.self)
            }
            slsHideCursor = load(["SLSHideCursor", "CGSHideCursor"]).map {
                unsafeBitCast($0, to: ConnErrFn.self)
            }
            slsShowCursor = load(["SLSShowCursor", "CGSShowCursor"]).map {
                unsafeBitCast($0, to: ConnErrFn.self)
            }
            slsObscureCursor = load(["SLSObscureCursor", "CGSObscureCursor"]).map {
                unsafeBitCast($0, to: ConnErrFn.self)
            }
            slsRevealCursor = load(["SLSRevealCursor"]).map {
                unsafeBitCast($0, to: ConnErrFn.self)
            }
        }
    }

    private static let lock = NSLock()
    private static nonisolated(unsafe) var activeHiders: [ObjectIdentifier: SystemCursorHider] = [:]
    private static nonisolated(unsafe) var installedExitHooks = false

    private let bindings = SkyLightBindings.shared
    private let cachedMainConnectionID: ConnectionID
    private let suppressHidingByEnvironment: Bool = ProcessInfo.processInfo.environment["APPLEPOINTER_NO_HIDE"] == "1"

    private var hideCallCount = 0
    private var slsHideCallCount = 0
    private var desiredHidden = false
    private var overlayActive = false
    private var isOverlayIdlePaused = false
    private var nativeResizeActive = false
    private var customAppCursorActive = false
    private var pausedForPermissionSetup = false
    private var frontmostBundleID: String?
    private var excludedBundleIDs: Set<String> = []
    private var lastRenderedFrameUptime: TimeInterval?
    private var lastDockRehideUptime: TimeInterval = -.infinity
    private var wasOverDock = false
    private var lastHiddenCursorSeed: Int32 = 0
    private var isInvisibleDockCursorApplied = false
    private var isTransparentVisibleHoverMode = false
    private var lastDockCursorSeed: Int32 = 0
    private var lastOwnInvisibleCursorSeed: Int32 = 0
    private var lastClearedOwnInvisibleCursorUptime: TimeInterval = -.infinity
    private var invisibleDockCursorToggle = false
    private var lastWatchdogKeyAge: TimeInterval = .infinity
    private var lastWatchdogMouseLocation: NSPoint = .zero
    private static func makeTransparent1x1Cursor() -> NSCursor {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: .zero)
    }
    private lazy var invisibleDockCursorA: NSCursor = Self.makeTransparent1x1Cursor()
    private lazy var invisibleDockCursorB: NSCursor = Self.makeTransparent1x1Cursor()

    private var hasLoggedConnectionProp = false
    private var watchdogTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    private var cachedResizeKindBySig: [Data: ResizeCursorKind] = [:]
    private var cachedSpecialKindBySig: [Data: SpecialCursorKind] = [:]
    private var cachedIBeamSigs: Set<Data> = []
    private var cachedCrosshairSigs: Set<Data> = []
    private var cachedStandardPointerSigs: Set<Data> = []
    private var lastCursorSeed: Int32 = 0
    private var cachedResizeKind: ResizeCursorKind = .none
    private var cachedSpecialKind: SpecialCursorKind = .none
    private var cachedIsIBeam = false
    private var cachedIsCrosshair = false
    private var cachedIsUnknownCustomCursor = false
    var onNeedsWake: (@MainActor () -> Void)?

    init() {
        self.cachedMainConnectionID = bindings.mainConnection?() ?? 0
        registerForCleanup()
        configureBackgroundCursorProperty(logResult: true)
        buildCursorSignatures()
        if suppressHidingByEnvironment {
            logDiag("APPLEPOINTER_NO_HIDE=1 active; system cursor will remain visible")
        }
    }

    deinit {
        stop()
        unregisterForCleanup()
    }

    func start() {
        assertMainThread()
        desiredHidden = true
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated {
                    self?.handleFrontmostApplicationChanged(bundleID)
                }
            }
        }

        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleSpaceOrMissionControlTransition()
                }
            }
        }

        if terminationObserver == nil {
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                }
            }
        }

        if watchdogTimer == nil {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.watchdogTick()
                }
            }
            timer.tolerance = 0.015
            RunLoop.main.add(timer, forMode: .common)
            watchdogTimer = timer
        }
    }

    func stop() {
        desiredHidden = false
        isOverlayIdlePaused = false
        nativeResizeActive = false
        customAppCursorActive = false
        pausedForPermissionSetup = false
        overlayActive = false
        lastRenderedFrameUptime = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil

        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }

        restoreNativeCursorNow()
    }

    func updateSafetyState(
        overlayActive: Bool,
        nativeResizeActive: Bool,
        customAppCursorActive: Bool = false,
        pausedForPermissionSetup: Bool,
        frontmostBundleID: String?,
        excludedBundleIDs: Set<String> = []
    ) {
        self.overlayActive = overlayActive
        self.nativeResizeActive = nativeResizeActive
        self.customAppCursorActive = customAppCursorActive
        self.pausedForPermissionSetup = pausedForPermissionSetup
        self.frontmostBundleID = frontmostBundleID
        self.excludedBundleIDs = excludedBundleIDs

        if !evaluateShouldHide(at: ProcessInfo.processInfo.systemUptime) {
            if !desiredHidden || pausedForPermissionSetup {
                restoreNativeCursorNow(forceGlobalShow: true)
            } else if customAppCursorActive || nativeResizeActive {
                // Hand off cleanly to CleanShot X / screencaptureui / custom tool cursors:
                // only undo ApplePointer's own hide count and dock cursor without forcing global show or NSCursor.arrow.
                if hasPendingHideOrOverride() {
                    releaseHidingForExternalApp()
                }
            } else if hasPendingHideOrOverride() {
                restoreNativeCursorNow(forceGlobalShow: false)
            }
        }
    }

    func refreshHeartbeat(at uptime: TimeInterval) {
        lastRenderedFrameUptime = uptime
    }

    func invalidateCursorClassificationCache() {
        lastCursorSeed = 0
        cachedIsCrosshair = false
        cachedSpecialKind = .none
        cachedIsUnknownCustomCursor = false
    }

    func setOverlayIdlePaused(_ paused: Bool) {
        isOverlayIdlePaused = paused
        if paused && overlayActive && desiredHidden {
            lastRenderedFrameUptime = ProcessInfo.processInfo.systemUptime
        }
    }

    func ensureHiddenOnFrame(
        at uptime: TimeInterval,
        isOverDock: Bool = false,
        isScreenshotCapture: Bool = false,
        needsHoverTrackingVisible: Bool = false
    ) {
        isOverlayIdlePaused = false
        lastRenderedFrameUptime = uptime
        if evaluateShouldHide(at: uptime) {
            let currentSeed: Int32
            if let seedFn = bindings.slsCurrentCursorSeed {
                currentSeed = seedFn()
            } else {
                currentSeed = 0
            }
            let seedChanged = (currentSeed != 0 && currentSeed != lastHiddenCursorSeed)
            if needsHoverTrackingVisible && !isScreenshotCapture {
                // macOS NotificationCenter uses _CGSAddTrackingRegion (mouseEnteredTrackingRegion) to reveal
                // the close (x) button on hover, which WindowServer suppresses while SLSCursorIsVisible == false.
                // Keep the cursor image 1x1 transparent while logically visible so the x button appears immediately
                // without ever showing the native arrow.
                isTransparentVisibleHoverMode = true
                wasOverDock = false
                applyInvisibleDockCursorIfNeeded(currentSeed: currentSeed)
                restoreCursorVisibilityKeepingTransparentImage()
                return
            }
            if isTransparentVisibleHoverMode {
                isTransparentVisibleHoverMode = false
                if !isOverDock {
                    clearInvisibleDockCursorIfNeeded()
                }
            }
            let forceAggressiveHide = isOverDock || isScreenshotCapture
            let enteredAggressiveZone = forceAggressiveHide && !wasOverDock
            wasOverDock = forceAggressiveHide
            let dockNeedsRefresh = forceAggressiveHide && (uptime - lastDockRehideUptime) >= 0.05
            let cursorVisible = isSystemCursorCurrentlyVisible()
            if isOverDock {
                applyInvisibleDockCursorIfNeeded(currentSeed: currentSeed)
            } else if isInvisibleDockCursorApplied {
                clearInvisibleDockCursorIfNeeded()
            }
            if forceAggressiveHide {
                obscureCursorViaSkyLight()
            }
            if hideCallCount == 0 || cursorVisible || enteredAggressiveZone {
                hideSystemCursorUntilInvisible()
                if currentSeed != 0 {
                    lastHiddenCursorSeed = currentSeed
                }
                if forceAggressiveHide {
                    obscureCursorViaSkyLight()
                    lastDockRehideUptime = uptime
                }
                if seedChanged && !isOverDock {
                    refreshCursorClassificationIfNeeded()
                }
            } else if seedChanged {
                lastHiddenCursorSeed = currentSeed
                if !isOverDock {
                    refreshCursorClassificationIfNeeded()
                }
                configureBackgroundCursorProperty(logResult: false)
                if isSystemCursorCurrentlyVisible() {
                    hideSystemCursorUntilInvisible()
                }
            } else if dockNeedsRefresh {
                lastDockRehideUptime = uptime
                configureBackgroundCursorProperty(logResult: false)
                hideAcrossActiveDisplaysIfNeeded()
                obscureCursorViaSkyLight()
            }
        } else {
            wasOverDock = false
            isTransparentVisibleHoverMode = false
            releaseHidingForExternalApp()
        }
    }

    func handleDisplayConfigurationChanged() {
        configureBackgroundCursorProperty(logResult: false)
        for c in [NSCursor.arrow, NSCursor.pointingHand] {
            if let sig = Self.canonicalSignature(for: c) {
                cachedStandardPointerSigs.insert(sig)
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if evaluateShouldHide(at: now) {
            hideSystemCursorUntilInvisible()
        }
    }

    func isSystemCursorCurrentlyVisible() -> Bool {
        var visible = false
        if let slsVisible = bindings.slsCursorIsVisible,
           cachedMainConnectionID != 0 {
            visible = slsVisible(cachedMainConnectionID)
        }
        if let cgVisible = bindings.cgCursorIsVisible {
            visible = visible || (cgVisible() != 0)
        }
        return visible
    }

    func currentCursorSeed() -> Int32 {
        bindings.slsCurrentCursorSeed?() ?? 0
    }

    func currentResizeCursorKind() -> ResizeCursorKind {
        refreshCursorClassificationIfNeeded()
        return cachedResizeKind
    }

    func isSystemResizeCursorActive() -> Bool {
        refreshCursorClassificationIfNeeded()
        return cachedResizeKind != .none
    }

    func isSystemIBeamCursorActive() -> Bool {
        refreshCursorClassificationIfNeeded()
        return cachedIsIBeam
    }

    func isSystemCrosshairCursorActive() -> Bool {
        refreshCursorClassificationIfNeeded()
        return cachedIsCrosshair
    }

    func currentSpecialCursorKind() -> SpecialCursorKind {
        refreshCursorClassificationIfNeeded()
        return cachedSpecialKind
    }

    func isUnknownCustomAppCursorActive() -> Bool {
        refreshCursorClassificationIfNeeded()
        return cachedIsUnknownCustomCursor
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }
        return Array(ids.prefix(Int(count)))
    }

    /// Cleanly releases only ApplePointer's own cursor hide count and transparent dock cursor override,
    /// ensuring the cursor actually becomes visible once when ApplePointer was hiding it, without
    /// overwriting another app's custom cursor image (e.g. CleanShot X crosshair) or fighting on later frames.
    func releaseHidingForExternalApp() {
        restoreNativeCursorNow(forceGlobalShow: false, ensureVisibleOnceIfWasHiding: true)
    }

    func restoreNativeCursorNow(forceGlobalShow: Bool = true, ensureVisibleOnceIfWasHiding: Bool = false) {
        isTransparentVisibleHoverMode = false
        let hadOwnInvisibleCursor = isInvisibleDockCursorApplied
        if hadOwnInvisibleCursor {
            clearInvisibleDockCursorIfNeeded()
        } else if forceGlobalShow && Self.isCurrentSystemCursorInvisible() {
            configureBackgroundCursorProperty(logResult: false)
            NSCursor.arrow.set()
        }
        let wasHiding = (hideCallCount > 0 || slsHideCallCount > 0)
        guard wasHiding || hadOwnInvisibleCursor || (forceGlobalShow && (!desiredHidden || pausedForPermissionSetup)) else {
            return
        }
        configureBackgroundCursorProperty(logResult: false)
        let primaryDisplay = CGMainDisplayID()
        if cachedMainConnectionID != 0 {
            if let slsShow = bindings.slsShowCursor {
                while slsHideCallCount > 0 {
                    _ = slsShow(cachedMainConnectionID)
                    slsHideCallCount -= 1
                }
            }
            if wasHiding || forceGlobalShow {
                _ = bindings.slsRevealCursor?(cachedMainConnectionID)
            }
        }
        while hideCallCount > 0 {
            CGDisplayShowCursor(primaryDisplay)
            hideCallCount -= 1
        }
        if forceGlobalShow || (ensureVisibleOnceIfWasHiding && wasHiding) {
            var extraShows = 0
            while !isSystemCursorCurrentlyVisible() && extraShows < 8 {
                CGDisplayShowCursor(primaryDisplay)
                extraShows += 1
            }
            if !isSystemCursorCurrentlyVisible(),
               let forceShow = bindings.slsForceShowCursor,
               cachedMainConnectionID != 0 {
                _ = forceShow(cachedMainConnectionID)
            }
        }
    }

    private func hasPendingHideOrOverride() -> Bool {
        hideCallCount > 0 || slsHideCallCount > 0 || isInvisibleDockCursorApplied || isTransparentVisibleHoverMode
    }

    private func handleFrontmostApplicationChanged(_ bundleID: String?) {
        frontmostBundleID = bundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if CursorHideSafetyPolicy.isSensitiveSystemPrompt(bundleID: frontmostBundleID) {
            restoreNativeCursorNow(forceGlobalShow: true)
            return
        }
        if let bid = frontmostBundleID,
           CursorHideSafetyPolicy.screenshotCaptureBundleIDs.contains(bid) {
            releaseHidingForExternalApp()
            return
        }
        enforcePolicy(at: ProcessInfo.processInfo.systemUptime)
    }

    private func watchdogTick() {
        let now = ProcessInfo.processInfo.systemUptime
        var needsWake = false
        let currentMouseLoc = NSEvent.mouseLocation
        let mouseMovedSinceTick = hypot(
            currentMouseLoc.x - lastWatchdogMouseLocation.x,
            currentMouseLoc.y - lastWatchdogMouseLocation.y
        ) > 0.5
        lastWatchdogMouseLocation = currentMouseLoc

        if isOverlayIdlePaused && overlayActive && desiredHidden {
            // Keep heartbeat fresh while CADisplayLink is intentionally paused in zero-CPU idle
            // (main thread is still responsive; a real freeze still triggers dead-man's switch).
            lastRenderedFrameUptime = now
            if mouseMovedSinceTick {
                needsWake = true
            }
            if let seedFn = bindings.slsCurrentCursorSeed {
                let s = seedFn()
                if s != 0 && s != lastCursorSeed {
                    needsWake = true
                }
            }
            if isSystemCursorCurrentlyVisible() {
                needsWake = true
            }
            let keyAge = min(
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
                CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
            )
            if keyAge >= 0 && keyAge < 0.45 && (keyAge < lastWatchdogKeyAge - 0.01 || lastWatchdogKeyAge.isInfinite) {
                needsWake = true
            }
            lastWatchdogKeyAge = keyAge
        } else if customAppCursorActive && overlayActive && desiredHidden {
            if mouseMovedSinceTick {
                needsWake = true
            }
            if let seedFn = bindings.slsCurrentCursorSeed {
                let s = seedFn()
                if s != 0 && s != lastCursorSeed {
                    needsWake = true
                }
            }
        }
        if evaluateShouldHide(at: now) {
            if isTransparentVisibleHoverMode {
                let seed = bindings.slsCurrentCursorSeed?() ?? 0
                applyInvisibleDockCursorIfNeeded(currentSeed: seed)
                restoreCursorVisibilityKeepingTransparentImage()
            } else {
                if isInvisibleDockCursorApplied {
                    let seed = bindings.slsCurrentCursorSeed?() ?? 0
                    applyInvisibleDockCursorIfNeeded(currentSeed: seed)
                    obscureCursorViaSkyLight()
                    if isSystemCursorCurrentlyVisible() {
                        hideSystemCursorUntilInvisible()
                    }
                } else if isSystemCursorCurrentlyVisible() {
                    // Wake PointerController first so a newly opened screenshot/CleanShot overlay
                    // is detected before ApplePointer fights to re-hide its cursor.
                    needsWake = true
                }
            }
        } else if !desiredHidden || pausedForPermissionSetup {
            restoreNativeCursorNow(forceGlobalShow: true)
        } else if customAppCursorActive || nativeResizeActive {
            if hasPendingHideOrOverride() {
                releaseHidingForExternalApp()
            }
        } else if hasPendingHideOrOverride() || !isSystemCursorCurrentlyVisible() {
            restoreNativeCursorNow(forceGlobalShow: !isSystemCursorCurrentlyVisible())
        }
        if needsWake {
            let cb = onNeedsWake
            Task { @MainActor in
                cb?()
            }
        }
    }

    private func handleSpaceOrMissionControlTransition() {
        let now = ProcessInfo.processInfo.systemUptime
        if overlayActive && desiredHidden {
            lastRenderedFrameUptime = now
        }
        enforcePolicy(at: now)
        let cb = onNeedsWake
        Task { @MainActor in
            cb?()
        }
    }

    private func hideSystemCursorUntilInvisible() {
        configureBackgroundCursorProperty(logResult: false)
        let primaryDisplay = CGMainDisplayID()
        if hideCallCount >= 6 {
            // Refresh WindowServer hide state without growing hideCallCount unboundedly when Dock keeps revealing cursor.
            CGDisplayShowCursor(primaryDisplay)
            CGDisplayHideCursor(primaryDisplay)
            obscureCursorViaSkyLight()
            return
        }
        var attempts = 0
        repeat {
            CGDisplayHideCursor(primaryDisplay)
            hideCallCount += 1
            attempts += 1
        } while isSystemCursorCurrentlyVisible() && attempts < 2 && hideCallCount < 6
    }

    private func obscureCursorViaSkyLight() {
        guard cachedMainConnectionID != 0 else { return }
        _ = bindings.slsObscureCursor?(cachedMainConnectionID)
    }

    private static func isCurrentSystemCursorInvisible() -> Bool {
        guard let size = NSCursor.currentSystem?.image.size else { return false }
        return size.width <= 2.0 && size.height <= 2.0
    }

    private func applyInvisibleDockCursorIfNeeded(currentSeed: Int32) {
        let needsSet = !isInvisibleDockCursorApplied
            || (currentSeed != 0 && currentSeed != lastDockCursorSeed)
            || !Self.isCurrentSystemCursorInvisible()
        guard needsSet else { return }
        configureBackgroundCursorProperty(logResult: false)
        // Alternate between two distinct 1x1 transparent NSCursor instances so AppKit never
        // short-circuits NSCursor.set() when Dock resets the global system cursor to arrow.
        invisibleDockCursorToggle.toggle()
        (invisibleDockCursorToggle ? invisibleDockCursorA : invisibleDockCursorB).set()
        isInvisibleDockCursorApplied = true
        let afterSeed = bindings.slsCurrentCursorSeed?() ?? currentSeed
        if afterSeed != 0 {
            lastDockCursorSeed = afterSeed
            lastOwnInvisibleCursorSeed = afterSeed
            lastHiddenCursorSeed = afterSeed
            lastCursorSeed = afterSeed
        }
    }

    private func clearInvisibleDockCursorIfNeeded() {
        guard isInvisibleDockCursorApplied else { return }
        isInvisibleDockCursorApplied = false
        lastDockCursorSeed = 0
        lastClearedOwnInvisibleCursorUptime = ProcessInfo.processInfo.systemUptime
        configureBackgroundCursorProperty(logResult: false)
        NSCursor.arrow.set()
        cachedIsUnknownCustomCursor = false
        lastCursorSeed = 0
    }

    private func restoreCursorVisibilityKeepingTransparentImage() {
        configureBackgroundCursorProperty(logResult: false)
        let displays = activeDisplayIDs()
        let primaryDisplay = displays.first ?? CGMainDisplayID()
        if cachedMainConnectionID != 0 {
            if let slsShow = bindings.slsShowCursor {
                while slsHideCallCount > 0 {
                    _ = slsShow(cachedMainConnectionID)
                    slsHideCallCount -= 1
                }
            }
            _ = bindings.slsRevealCursor?(cachedMainConnectionID)
        }
        while hideCallCount > 0 {
            for displayID in displays {
                if hideCallCount <= 0 { break }
                CGDisplayShowCursor(displayID)
                hideCallCount -= 1
            }
        }
        var extraShows = 0
        while !isSystemCursorCurrentlyVisible() && extraShows < 6 {
            CGDisplayShowCursor(primaryDisplay)
            extraShows += 1
        }
        if !isSystemCursorCurrentlyVisible(),
           let forceShow = bindings.slsForceShowCursor,
           cachedMainConnectionID != 0 {
            _ = forceShow(cachedMainConnectionID)
        }
    }

    private func hideAcrossActiveDisplaysIfNeeded() {
        if isSystemCursorCurrentlyVisible() || hideCallCount == 0 {
            if hideCallCount >= 6 {
                CGDisplayShowCursor(CGMainDisplayID())
                CGDisplayHideCursor(CGMainDisplayID())
            } else {
                CGDisplayHideCursor(CGMainDisplayID())
                hideCallCount += 1
            }
        }
    }

    private func enforcePolicy(at uptime: TimeInterval) {
        if evaluateShouldHide(at: uptime) {
            if hideCallCount == 0 || isSystemCursorCurrentlyVisible() {
                hideSystemCursorUntilInvisible()
            }
        } else {
            restoreNativeCursorNow(forceGlobalShow: !desiredHidden || pausedForPermissionSetup)
        }
    }

    private func evaluateShouldHide(at uptime: TimeInterval) -> Bool {
        CursorHideSafetyPolicy.shouldHideSystemCursor(
            CursorHideSafetyPolicy.State(
                enabled: desiredHidden,
                overlayActive: overlayActive,
                nativeResizeCursorActive: nativeResizeActive,
                customAppCursorActive: customAppCursorActive,
                pausedForPermissionSetup: pausedForPermissionSetup,
                frontmostBundleID: frontmostBundleID,
                excludedBundleIDs: excludedBundleIDs,
                lastRenderedFrameUptime: lastRenderedFrameUptime,
                currentUptime: uptime,
                suppressHidingByEnvironment: suppressHidingByEnvironment
            )
        )
    }

    private func refreshCursorClassificationIfNeeded() {
        var currentSeed: Int32 = 0
        if let seedFn = bindings.slsCurrentCursorSeed {
            let seed = seedFn()
            if seed != 0 && seed == lastCursorSeed {
                return
            }
            currentSeed = seed
        }

        guard let current = NSCursor.currentSystem else {
            cachedResizeKind = .none
            cachedSpecialKind = .none
            cachedIsIBeam = false
            cachedIsCrosshair = false
            cachedIsUnknownCustomCursor = false
            return
        }
        if currentSeed != 0 {
            lastCursorSeed = currentSeed
        }

        let rawSize = current.image.size
        if rawSize.width <= 2.0 && rawSize.height <= 2.0 {
            cachedIsCrosshair = false
            cachedIsIBeam = false
            cachedResizeKind = .none
            cachedSpecialKind = .none
            // Never misclassify ApplePointer's own 1x1 transparent Dock/hover cursor (including
            // right after clearInvisibleDockCursorIfNeeded() before WindowServer flushes arrow)
            // as an external app cursor, which would otherwise unhide the native system arrow.
            let now = ProcessInfo.processInfo.systemUptime
            let isOwnTransparentCursor = isInvisibleDockCursorApplied
                || isTransparentVisibleHoverMode
                || (currentSeed != 0 && currentSeed == lastOwnInvisibleCursorSeed)
                || (now - lastClearedOwnInvisibleCursorUptime) < 0.60
            cachedIsUnknownCustomCursor = !isOwnTransparentCursor
            return
        }

        if cachedIBeamSigs.isEmpty {
            populateIBeamSignatures()
        }
        if cachedCrosshairSigs.isEmpty {
            populateCrosshairSignatures()
        }

        let sig = Self.canonicalSignature(for: current)

        if current == NSCursor.arrow || current == NSCursor.pointingHand
            || (sig != nil && matchesStandardPointerSignature(sig!)) {
            cachedIsCrosshair = false
            cachedIsIBeam = false
            cachedResizeKind = .none
            cachedSpecialKind = .none
            cachedIsUnknownCustomCursor = false
            return
        }

        if current == NSCursor.crosshair
            || (sig != nil && cachedCrosshairSigs.contains(sig!)) {
            cachedIsCrosshair = true
            cachedIsIBeam = false
            cachedResizeKind = .none
            cachedSpecialKind = .none
            cachedIsUnknownCustomCursor = false
            return
        }

        if current == NSCursor.iBeam
            || current == NSCursor.iBeamCursorForVerticalLayout
            || (sig != nil && cachedIBeamSigs.contains(sig!)) {
            cachedIsCrosshair = false
            cachedIsIBeam = true
            cachedResizeKind = .none
            cachedSpecialKind = .none
            cachedIsUnknownCustomCursor = false
            return
        }

        if let sig, let kind = matchesResizeCursorSignature(sig) {
            cachedIsCrosshair = false
            cachedIsIBeam = false
            cachedResizeKind = kind
            cachedSpecialKind = .none
            cachedIsUnknownCustomCursor = false
            return
        }

        if let sig, let special = cachedSpecialKindBySig[sig] {
            cachedIsCrosshair = false
            cachedIsIBeam = false
            cachedResizeKind = .none
            cachedSpecialKind = special
            cachedIsUnknownCustomCursor = false
            return
        }
        let directSpecials: [(NSCursor, SpecialCursorKind)] = [
            (.openHand, .openHand),
            (.closedHand, .closedHand),
            (.dragCopy, .dragCopy),
            (.dragLink, .dragLink),
            (.operationNotAllowed, .operationNotAllowed),
            (.contextualMenu, .contextualMenu),
            (.disappearingItem, .disappearingItem)
        ]
        for (cursorRef, specialKind) in directSpecials where current == cursorRef {
            if let sig { cachedSpecialKindBySig[sig] = specialKind }
            cachedIsCrosshair = false
            cachedIsIBeam = false
            cachedResizeKind = .none
            cachedSpecialKind = specialKind
            cachedIsUnknownCustomCursor = false
            return
        }

        let privateSelectors: [(String, ResizeCursorKind)] = [
            ("_windowResizeNorthWestSouthEastCursor", .diagonalNWSE),
            ("_windowResizeNorthEastSouthWestCursor", .diagonalNESW),
            ("_windowResizeNorthSouthCursor", .vertical),
            ("_windowResizeEastWestCursor", .horizontal),
            ("_windowResizeNorthCursor", .up),
            ("_windowResizeSouthCursor", .down),
            ("_windowResizeEastCursor", .right),
            ("_windowResizeWestCursor", .left)
        ]
        for (selName, kind) in privateSelectors {
            let sel = NSSelectorFromString(selName)
            if NSCursor.responds(to: sel),
               let obj = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
                if current == obj || (sig != nil && Self.canonicalSignature(for: obj) == sig) {
                    if let sig { cachedResizeKindBySig[sig] = kind }
                    cachedIsCrosshair = false
                    cachedIsIBeam = false
                    cachedResizeKind = kind
                    cachedSpecialKind = .none
                    cachedIsUnknownCustomCursor = false
                    return
                }
            }
        }

        // Heuristic fallback for custom screenshot / design tool crosshairs (cached per signature)
        if Self.looksLikeCustomCrosshair(cursor: current) {
            if let sig, cachedCrosshairSigs.count < 256 { cachedCrosshairSigs.insert(sig) }
            cachedIsCrosshair = true
            cachedIsIBeam = false
            cachedResizeKind = .none
            cachedSpecialKind = .none
            cachedIsUnknownCustomCursor = false
            return
        }

        // Heuristic fallback for custom Chromium / Electron / WebKit I-beam bitmaps (cached per signature)
        if Self.looksLikeCustomIBeam(cursor: current) {
            if let sig { cachedIBeamSigs.insert(sig) }
            cachedIsCrosshair = false
            cachedIsIBeam = true
            cachedResizeKind = .none
            cachedSpecialKind = .none
            cachedIsUnknownCustomCursor = false
            return
        }

        // Any other bespoke cursor drawn by a creative app (Figma, Photoshop, Blender, games, etc.)
        // Also treat oversized custom cursors (> 128pt, e.g. CleanShot X coordinate crosshairs) as custom pass-through.
        cachedIsCrosshair = false
        cachedIsIBeam = false
        cachedResizeKind = .none
        cachedSpecialKind = .none
        let cursorSize = current.image.size
        cachedIsUnknownCustomCursor = (sig != nil || cursorSize.width > 128 || cursorSize.height > 128)
    }

    private func populateIBeamSignatures() {
        for c in [NSCursor.iBeam, NSCursor.iBeamCursorForVerticalLayout] {
            if let sig = Self.canonicalSignature(for: c) {
                cachedIBeamSigs.insert(sig)
            }
        }
    }

    private func populateCrosshairSignatures() {
        if let sig = Self.canonicalSignature(for: NSCursor.crosshair) {
            cachedCrosshairSigs.insert(sig)
        }
    }

    /// Matches exact standard pointer signatures first, then allows up to 4% edge-pixel alpha variance
    /// for cursors with identical dimensions and hotspot (+/-1pt) so display-scale differences across
    /// Retina/external monitors or Dock never misclassify the macOS arrow as a custom tool cursor.
    private func matchesStandardPointerSignature(_ sig: Data) -> Bool {
        if cachedStandardPointerSigs.contains(sig) {
            return true
        }
        guard sig.count > 4 else { return false }
        let w = sig[0]
        let h = sig[1]
        let hx = Int(sig[2])
        let hy = Int(sig[3])
        let pixelCount = sig.count - 4
        let maxDiff = max(4, pixelCount / 25)
        for ref in cachedStandardPointerSigs where ref.count == sig.count {
            guard ref[0] == w, ref[1] == h,
                  abs(Int(ref[2]) - hx) <= 1,
                  abs(Int(ref[3]) - hy) <= 1 else {
                continue
            }
            var diff = 0
            for i in 4..<sig.count {
                let a = sig[i]
                let b = ref[i]
                if (a == 0) != (b == 0) || abs(Int(a) - Int(b)) > 64 {
                    diff += 1
                    if diff > maxDiff { break }
                }
            }
            if diff <= maxDiff {
                cachedStandardPointerSigs.insert(sig)
                return true
            }
        }
        return false
    }

    /// Matches exact resize cursor signatures first, then allows up to 4% edge-pixel alpha variance
    /// for cursors with identical dimensions and hotspot (+/-1pt) so Retina/external display scale
    /// differences never misclassify system window-edge resize cursors as crosshairs or custom cursors.
    private func matchesResizeCursorSignature(_ sig: Data) -> ResizeCursorKind? {
        if let exact = cachedResizeKindBySig[sig] {
            return exact
        }
        guard sig.count > 4 else { return nil }
        let w = sig[0]
        let h = sig[1]
        let hx = Int(sig[2])
        let hy = Int(sig[3])
        let pixelCount = sig.count - 4
        let maxDiff = max(4, pixelCount / 25)
        for (ref, kind) in cachedResizeKindBySig where ref.count == sig.count {
            guard ref[0] == w, ref[1] == h,
                  abs(Int(ref[2]) - hx) <= 1,
                  abs(Int(ref[3]) - hy) <= 1 else {
                continue
            }
            var diff = 0
            for i in 4..<sig.count {
                let a = sig[i]
                let b = ref[i]
                if (a == 0) != (b == 0) || abs(Int(a) - Int(b)) > 64 {
                    diff += 1
                    if diff > maxDiff { break }
                }
            }
            if diff <= maxDiff {
                cachedResizeKindBySig[sig] = kind
                return kind
            }
        }
        return nil
    }

    /// Fast, representation-independent 1x alpha fingerprint of a cursor image + rounded hotspot
    /// so single-rep WindowServer copies from NSCursor.currentSystem match multi-rep NSCursor constants.
    private static func canonicalSignature(for cursor: NSCursor) -> Data? {
        let size = cursor.image.size
        guard size.width > 0, size.height > 0, size.width <= 128, size.height <= 128 else {
            return nil
        }
        let w = max(1, min(48, Int(round(size.width))))
        let h = max(1, min(48, Int(round(size.height))))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: w * 4,
            bitsPerPixel: 32
        ) else {
            return nil
        }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            ctx.imageInterpolation = .low
            NSGraphicsContext.current = ctx
            cursor.image.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let ptr = rep.bitmapData else { return nil }
        var out = Data(capacity: 4 + w * h)
        out.append(UInt8(w))
        out.append(UInt8(h))
        out.append(UInt8(max(0, min(255, Int(round(cursor.hotSpot.x))))))
        out.append(UInt8(max(0, min(255, Int(round(cursor.hotSpot.y))))))
        let count = w * h
        for i in 0..<count {
            out.append(ptr[i * 4 + 3] & 0xC0)
        }
        return out
    }

    private static func looksLikeCustomCrosshair(cursor: NSCursor) -> Bool {
        let size = cursor.image.size
        // Support both compact crosshairs (24x24) and coordinate-readout screenshot crosshairs
        // (e.g. CleanShot X & macOS Cmd+Shift+4, up to 256x256 with off-center hotspot).
        guard size.width >= 14, size.height >= 14, size.width <= 256, size.height <= 256 else {
            return false
        }
        let hot = cursor.hotSpot
        guard hot.x >= 4.0, hot.y >= 4.0, hot.x <= size.width - 4.0, hot.y <= size.height - 4.0 else {
            return false
        }
        let w = max(14, min(256, Int(round(size.width))))
        let h = max(14, min(256, Int(round(size.height))))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: w * 4,
            bitsPerPixel: 32
        ) else {
            return false
        }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        cursor.image.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return false }
        let cx = max(2, min(w - 3, Int(round(hot.x * Double(w) / max(1.0, size.width)))))
        let cy = max(2, min(h - 3, Int(round(hot.y * Double(h) / max(1.0, size.height)))))

        let radius = 12
        var localOpaque = 0
        var leftArm = 0
        var rightArm = 0
        var topArm = 0
        var bottomArm = 0
        var tl = 0
        var tr = 0
        var bl = 0
        var br = 0
        for dy in -radius...radius {
            let y = cy + dy
            guard y >= 0 && y < h else { continue }
            for dx in -radius...radius {
                let x = cx + dx
                guard x >= 0 && x < w else { continue }
                if data[(y * w + x) * 4 + 3] > 80 {
                    localOpaque += 1
                    if abs(dy) <= 1 && dx <= -2 { leftArm += 1 }
                    if abs(dy) <= 1 && dx >= 2 { rightArm += 1 }
                    if abs(dx) <= 1 && dy <= -2 { topArm += 1 }
                    if abs(dx) <= 1 && dy >= 2 { bottomArm += 1 }
                    if dx <= -4 && dy <= -4 { tl += 1 }
                    if dx >= 4 && dy <= -4 { tr += 1 }
                    if dx <= -4 && dy >= 4 { bl += 1 }
                    if dx >= 4 && dy >= 4 { br += 1 }
                }
            }
        }
        // Require all 4 thin arms radiating symmetrically from hotspot, with at least 3 of 4 diagonal quadrants
        // empty (allowing the 4th quadrant to hold live coordinate numbers such as CleanShot X / Cmd+Shift+4).
        let cornerSumExceptMax = (tl + tr + bl + br) - max(max(tl, tr), max(bl, br))
        let emptyCornerCount = [tl, tr, bl, br].filter { $0 <= 12 }.count
        return leftArm >= 4 && rightArm >= 4 && topArm >= 4 && bottomArm >= 4
            && emptyCornerCount >= 3
            && cornerSumExceptMax <= 22
            && localOpaque < 260
    }

    private static func looksLikeCustomIBeam(cursor: NSCursor) -> Bool {
        let size = cursor.image.size
        guard size.width >= 8, size.height >= 8, size.width <= 64, size.height <= 64 else {
            return false
        }
        let hot = cursor.hotSpot
        let w = max(8, min(64, Int(round(size.width))))
        let h = max(8, min(64, Int(round(size.height))))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: w * 4,
            bitsPerPixel: 32
        ) else {
            return false
        }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        cursor.image.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return false }
        var minX = w, maxX = -1, minY = h, maxY = -1
        var totalOpaque = 0
        var rowMin = Array(repeating: w, count: h)
        var rowMax = Array(repeating: -1, count: h)
        for y in 0..<h {
            for x in 0..<w {
                if data[(y * w + x) * 4 + 3] > 80 {
                    totalOpaque += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    if x < rowMin[y] { rowMin[y] = x }
                    if x > rowMax[y] { rowMax[y] = x }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return false }
        let spanW = maxX - minX + 1
        let spanH = maxY - minY + 1
        let bboxCenterX = Double(minX + maxX) * 0.5
        let bboxCenterY = Double(minY + maxY) * 0.5
        let scaledHotX = Double(hot.x) * (Double(w) / Double(size.width))
        let scaledHotY = Double(hot.y) * (Double(h) / Double(size.height))

        let tolX = max(4.0, Double(spanW) * 0.45)
        let tolY = max(4.0, Double(spanH) * 0.35)
        guard abs(scaledHotX - bboxCenterX) <= tolX, abs(scaledHotY - bboxCenterY) <= tolY else {
            return false
        }

        let midStartY = minY + spanH / 3
        let midEndY = minY + (2 * spanH) / 3
        var middleRowOpaqueWidthSum = 0
        var middleRowsChecked = 0
        for y in midStartY...midEndY where y >= 0 && y < h {
            if rowMax[y] >= rowMin[y] {
                middleRowOpaqueWidthSum += (rowMax[y] - rowMin[y] + 1)
                middleRowsChecked += 1
            }
        }
        guard middleRowsChecked >= 3 else { return false }
        let avgMiddleW = Double(middleRowOpaqueWidthSum) / Double(middleRowsChecked)
        let fillRatio = Double(totalOpaque) / Double(max(1, spanW * spanH))
        let maxAllowedStemW = max(6.5, Double(spanH) * 0.36)
        let maxAllowedSpanW = max(16, Int(round(Double(spanH) * 0.80)))
        return spanH >= 12
            && spanW <= maxAllowedSpanW
            && avgMiddleW <= maxAllowedStemW
            && Double(spanH) >= Double(spanW) * 1.30
            && fillRatio < 0.72
    }

    private func configureBackgroundCursorProperty(logResult: Bool) {
        guard let setProp = bindings.setConnectionProperty else {
            return
        }
        let cid = cachedMainConnectionID != 0 ? cachedMainConnectionID : (bindings.mainConnection?() ?? 0)
        if cid != 0 {
            let err = setProp(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
            if (logResult && !hasLoggedConnectionProp) || err != .success {
                hasLoggedConnectionProp = true
                logDiag("CGSSetConnectionProperty(SetsCursorInBackground) cid=\(cid) err=\(err.rawValue)")
            }
        }
    }

    private func logDiag(_ message: String) {
        fputs("[ApplePointer] \(message)\n", stderr)
        fflush(stderr)
    }

    private func buildCursorSignatures() {
        populateIBeamSignatures()
        populateCrosshairSignatures()

        var resizeMappings: [(NSCursor, ResizeCursorKind)] = [
            (.resizeLeft, .left),
            (.resizeRight, .right),
            (.resizeLeftRight, .splitHorizontal),
            (.resizeUp, .up),
            (.resizeDown, .down),
            (.resizeUpDown, .splitVertical)
        ]
        if #available(macOS 15.0, *) {
            resizeMappings.append(contentsOf: [
                (.columnResize, .splitHorizontal),
                (.columnResize(directions: .left), .left),
                (.columnResize(directions: .right), .right),
                (.rowResize, .splitVertical),
                (.rowResize(directions: .up), .up),
                (.rowResize(directions: .down), .down),
                (.frameResize(position: .topLeft, directions: .all), .diagonalNWSE),
                (.frameResize(position: .bottomRight, directions: .all), .diagonalNWSE),
                (.frameResize(position: .topRight, directions: .all), .diagonalNESW),
                (.frameResize(position: .bottomLeft, directions: .all), .diagonalNESW),
                (.frameResize(position: .topLeft, directions: .inward), .cornerNW),
                (.frameResize(position: .topLeft, directions: .outward), .cornerNW),
                (.frameResize(position: .bottomRight, directions: .inward), .cornerSE),
                (.frameResize(position: .bottomRight, directions: .outward), .cornerSE),
                (.frameResize(position: .topRight, directions: .inward), .cornerNE),
                (.frameResize(position: .topRight, directions: .outward), .cornerNE),
                (.frameResize(position: .bottomLeft, directions: .inward), .cornerSW),
                (.frameResize(position: .bottomLeft, directions: .outward), .cornerSW),
                (.frameResize(position: .top, directions: .all), .vertical),
                (.frameResize(position: .bottom, directions: .all), .vertical),
                (.frameResize(position: .left, directions: .all), .horizontal),
                (.frameResize(position: .right, directions: .all), .horizontal)
            ])
        }
        for (c, kind) in resizeMappings {
            if let sig = Self.canonicalSignature(for: c) {
                cachedResizeKindBySig[sig] = kind
            }
        }
        let privateSelectors: [(String, ResizeCursorKind)] = [
            ("_windowResizeNorthWestSouthEastCursor", .diagonalNWSE),
            ("_windowResizeNorthEastSouthWestCursor", .diagonalNESW),
            ("_windowResizeNorthSouthCursor", .vertical),
            ("_windowResizeEastWestCursor", .horizontal),
            ("_windowResizeNorthCursor", .up),
            ("_windowResizeSouthCursor", .down),
            ("_windowResizeEastCursor", .right),
            ("_windowResizeWestCursor", .left)
        ]
        for (selName, kind) in privateSelectors {
            let sel = NSSelectorFromString(selName)
            if NSCursor.responds(to: sel),
               let obj = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor,
               let sig = Self.canonicalSignature(for: obj) {
                cachedResizeKindBySig[sig] = kind
            }
        }
        for c in [NSCursor.arrow, NSCursor.pointingHand] {
            if let sig = Self.canonicalSignature(for: c) {
                cachedStandardPointerSigs.insert(sig)
            }
        }
        let specialMappings: [(NSCursor, SpecialCursorKind)] = [
            (.openHand, .openHand),
            (.closedHand, .closedHand),
            (.dragCopy, .dragCopy),
            (.dragLink, .dragLink),
            (.operationNotAllowed, .operationNotAllowed),
            (.contextualMenu, .contextualMenu),
            (.disappearingItem, .disappearingItem)
        ]
        for (c, kind) in specialMappings {
            if let sig = Self.canonicalSignature(for: c) {
                cachedSpecialKindBySig[sig] = kind
            }
        }
        let privateSpecialSelectors: [(String, SpecialCursorKind)] = [
            ("_zoomInCursor", .zoomIn),
            ("_zoomOutCursor", .zoomOut),
            ("_helpCursor", .help)
        ]
        for (selName, kind) in privateSpecialSelectors {
            let sel = NSSelectorFromString(selName)
            if NSCursor.responds(to: sel),
               let obj = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor,
               let sig = Self.canonicalSignature(for: obj) {
                cachedSpecialKindBySig[sig] = kind
            }
        }
        populateHIServicesAndInstalledAppCursorSignatures()
    }

    /// Loads canonical signatures from macOS HIServices cursor resources (including macOS 27 variants)
    /// and installed creative-app tool cursors (such as Figma eyedropper & Keynote move) so they map
    /// seamlessly into our unified translucent iPadOS cursor glyphs.
    private func populateHIServicesAndInstalledAppCursorSignatures() {
        let hiBase = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors"
        let fm = FileManager.default

        func loadHIServicesCursor(folder: String) -> NSCursor? {
            let dir = (hiBase as NSString).appendingPathComponent(folder)
            let plistPath = (dir as NSString).appendingPathComponent("info.plist")
            guard let info = NSDictionary(contentsOfFile: plistPath) else { return nil }
            let hotX = (info["hotx"] as? NSNumber)?.doubleValue ?? 0
            let hotY = (info["hoty"] as? NSNumber)?.doubleValue ?? 0
            for candidate in ["cursor.pdf", "cursor_1only_.png"] {
                let imgPath = (dir as NSString).appendingPathComponent(candidate)
                if fm.fileExists(atPath: imgPath), let img = NSImage(contentsOfFile: imgPath) {
                    return NSCursor(image: img, hotSpot: NSPoint(x: hotX, y: hotY))
                }
            }
            return nil
        }

        for stdFolder in ["pointinghand", "macos27/pointinghand", "busybutclickable"] {
            if let cur = loadHIServicesCursor(folder: stdFolder),
               let sig = Self.canonicalSignature(for: cur) {
                cachedStandardPointerSigs.insert(sig)
            }
        }
        if let selCur = loadHIServicesCursor(folder: "screenshotselection"),
           let sig = Self.canonicalSignature(for: selCur) {
            cachedCrosshairSigs.insert(sig)
        }
        let hiResizeMappings: [(String, ResizeCursorKind)] = [
            ("resizedown", .down),
            ("resizeup", .up),
            ("resizeupdown", .splitVertical),
            ("resizeleft", .left),
            ("resizeright", .right),
            ("resizeleftright", .splitHorizontal),
            ("resizenorth", .up),
            ("resizesouth", .down),
            ("resizenorthsouth", .vertical),
            ("resizeeast", .right),
            ("resizewest", .left),
            ("resizeeastwest", .horizontal),
            ("resizenorthwestsoutheast", .diagonalNWSE),
            ("resizenortheastsouthwest", .diagonalNESW),
            ("resizenorthwest", .cornerNW),
            ("resizenortheast", .cornerNE),
            ("resizesouthwest", .cornerSW),
            ("resizesoutheast", .cornerSE)
        ]
        for (folder, kind) in hiResizeMappings {
            if let cur = loadHIServicesCursor(folder: folder),
               let sig = Self.canonicalSignature(for: cur) {
                cachedResizeKindBySig[sig] = kind
            }
        }
        let hiSpecials: [(String, SpecialCursorKind)] = [
            ("openhand", .openHand),
            ("macos27/openhand", .openHand),
            ("closedhand", .closedHand),
            ("macos27/closedhand", .closedHand),
            ("copy", .dragCopy),
            ("makealias", .dragLink),
            ("notallowed", .operationNotAllowed),
            ("contextualmenu", .contextualMenu),
            ("poof", .disappearingItem),
            ("zoomin", .zoomIn),
            ("zoomout", .zoomOut),
            ("move", .move),
            ("cell", .cell),
            ("help", .help),
            ("screenshotwindow", .screenshotWindow)
        ]
        for (folder, kind) in hiSpecials {
            if let cur = loadHIServicesCursor(folder: folder),
               let sig = Self.canonicalSignature(for: cur) {
                cachedSpecialKindBySig[sig] = kind
            }
        }

        // Known installed creative-app cursors (Figma eyedropper, Keynote move)
        let figmaDropper = "/Applications/Figma.app/Contents/Resources/app.asar.unpacked/assets/cursor-dropper-ui3.png"
        if fm.fileExists(atPath: figmaDropper), let img = NSImage(contentsOfFile: figmaDropper) {
            for hot in [NSPoint(x: 2, y: img.size.height - 2), NSPoint(x: 4, y: img.size.height - 4)] {
                let cur = NSCursor(image: img, hotSpot: hot)
                if let sig = Self.canonicalSignature(for: cur) {
                    cachedSpecialKindBySig[sig] = .eyedropper
                }
            }
        }
        let keynoteMove = "/Applications/Keynote Creator Studio.app/Contents/Resources/CRE_Cursor-Move.tiff"
        if fm.fileExists(atPath: keynoteMove), let img = NSImage(contentsOfFile: keynoteMove) {
            let cur = NSCursor(image: img, hotSpot: NSPoint(x: img.size.width * 0.5, y: img.size.height * 0.5))
            if let sig = Self.canonicalSignature(for: cur) {
                cachedSpecialKindBySig[sig] = .move
            }
        }
    }

    private func registerForCleanup() {
        Self.lock.lock()
        Self.activeHiders[ObjectIdentifier(self)] = self
        if !Self.installedExitHooks {
            Self.installedExitHooks = true
            atexit {
                SystemCursorHider.emergencyRestoreAll()
            }
            for sig in [SIGINT, SIGTERM] {
                signal(sig) { _ in
                    SystemCursorHider.emergencyRestoreAll()
                    _exit(0)
                }
            }
        }
        Self.lock.unlock()
    }

    private func unregisterForCleanup() {
        Self.lock.lock()
        Self.activeHiders.removeValue(forKey: ObjectIdentifier(self))
        Self.lock.unlock()
    }

    private static func emergencyRestoreAll() {
        for _ in 0..<8 {
            CGDisplayShowCursor(CGMainDisplayID())
        }
        let b = SkyLightBindings.shared
        if let cid = b.mainConnection?(), cid != 0 {
            if let slsShow = b.slsShowCursor {
                for _ in 0..<4 {
                    _ = slsShow(cid)
                }
            }
            _ = b.slsRevealCursor?(cid)
            _ = b.slsForceShowCursor?(cid)
        }
    }

    private func assertMainThread() {
        dispatchPrecondition(condition: .onQueue(.main))
    }
}
