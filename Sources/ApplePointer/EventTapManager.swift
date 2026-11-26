import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

@MainActor
final class EventTapManager {
    struct Callbacks: Sendable {
        var onMove: @MainActor @Sendable (CGPoint, TimeInterval, Bool?) -> Void
        var onButton: @MainActor @Sendable (Bool, CGPoint, TimeInterval) -> Void
        var onScroll: @MainActor @Sendable (TimeInterval, Bool) -> Void
        var onKeyDown: @MainActor @Sendable (TimeInterval, NSEvent.ModifierFlags, UInt16) -> Void
        var onSystemGesture: @MainActor @Sendable (TimeInterval) -> Void
        var onToggleShortcut: @Sendable () -> Void
    }

    private static let hotKeySignature = OSType(0x41505054) // 'APPT'
    private static let hotKeyIdentifier: UInt32 = 1
    private static var cachedPrimaryDisplayHeight: CGFloat = CGDisplayBounds(CGMainDisplayID()).height

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyGlobalMonitor: Any?
    private var keyLocalMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let callbacks: Callbacks

    init(callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    var isRunning: Bool {
        globalMonitor != nil
    }

    static func currentQuartzMouseLocation() -> CGPoint {
        let appKit = NSEvent.mouseLocation
        return CGPoint(x: appKit.x, y: cachedPrimaryDisplayHeight - appKit.y)
    }

    static func updatePrimaryDisplayHeight(_ height: CGFloat) {
        if height > 0 {
            cachedPrimaryDisplayHeight = height
        }
    }

    @discardableResult
    func start() -> Bool {
        if globalMonitor != nil {
            return true
        }

        let mouseMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp,
            .scrollWheel,
            .beginGesture,
            .endGesture,
            .swipe
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseOrScrollEvent(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseOrScrollEvent(event)
            }
            return event
        }

        keyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let flags = event.modifierFlags
            let keyCode = event.keyCode
            MainActor.assumeIsolated {
                self?.callbacks.onKeyDown(ProcessInfo.processInfo.systemUptime, flags, keyCode)
            }
        }

        keyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let flags = event.modifierFlags
            let keyCode = event.keyCode
            MainActor.assumeIsolated {
                self?.callbacks.onKeyDown(ProcessInfo.processInfo.systemUptime, flags, keyCode)
            }
            return event
        }

        let hotKeyStatus = installCarbonHotKey()
        fputs("[ApplePointer] Input monitors active (NSEvent mouse/scroll/key=\(keyGlobalMonitor != nil) + Carbon hotkey status=\(hotKeyStatus))\n", stderr)
        fflush(stderr)
        return globalMonitor != nil
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let keyGlobalMonitor {
            NSEvent.removeMonitor(keyGlobalMonitor)
            self.keyGlobalMonitor = nil
        }
        if let keyLocalMonitor {
            NSEvent.removeMonitor(keyLocalMonitor)
            self.keyLocalMonitor = nil
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleMouseOrScrollEvent(_ event: NSEvent) {
        let loc = Self.currentQuartzMouseLocation()
        let now = ProcessInfo.processInfo.systemUptime

        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let subtype = event.cgEvent?.getIntegerValueField(.mouseEventSubtype)
            let isTrackpad: Bool? = (subtype == 1) ? true : nil
            callbacks.onMove(loc, now, isTrackpad)

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            callbacks.onButton(true, loc, now)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            callbacks.onButton(false, loc, now)

        case .scrollWheel:
            callbacks.onScroll(now, event.hasPreciseScrollingDeltas)

        case .beginGesture, .endGesture, .swipe:
            callbacks.onSystemGesture(now)

        default:
            break
        }
    }

    private func installCarbonHotKey() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard paramStatus == noErr,
                      hotKeyID.signature == EventTapManager.hotKeySignature,
                      hotKeyID.id == EventTapManager.hotKeyIdentifier else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<EventTapManager>.fromOpaque(userData).takeUnretainedValue()
                let toggleCallback = manager.callbacks.onToggleShortcut
                DispatchQueue.main.async {
                    toggleCallback()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &installedHandler
        )
        guard handlerStatus == noErr, let installedHandler else {
            return handlerStatus
        }
        eventHandlerRef = installedHandler

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )
        var registeredRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(controlKey | optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredRef
        )
        if registerStatus == noErr {
            hotKeyRef = registeredRef
        } else {
            RemoveEventHandler(installedHandler)
            eventHandlerRef = nil
        }
        return registerStatus
    }
}
