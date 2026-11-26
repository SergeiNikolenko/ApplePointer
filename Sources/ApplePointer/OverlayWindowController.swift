import AppKit
import ApplePointerCore
import CoreGraphics
import Foundation
import QuartzCore

final class LumaBridge: NSObject, CALayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Double) -> Void)?
    private var protectedBackdrop: Bool = false

    var isProtectedBackdrop: Bool {
        lock.lock()
        let v = protectedBackdrop
        lock.unlock()
        return v
    }

    init(handler: (@Sendable (Double) -> Void)? = nil) {
        self.handler = handler
    }

    func setHandler(_ newHandler: (@Sendable (Double) -> Void)?) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    @objc(backdropLayer:didChangeLuma:)
    func backdropLayer(_ layer: AnyObject, didChangeLuma luma: Double) {
        lock.lock()
        protectedBackdrop = false
        let cb = handler
        lock.unlock()
        cb?(luma)
    }

    @objc(backdropLayer:didSampleProtectedLuma:)
    func backdropLayer(_ layer: AnyObject, didSampleProtectedLuma isProtected: Bool) {
        lock.lock()
        protectedBackdrop = isProtected
        lock.unlock()
    }
}

private struct SystemCursorAsset {
    let image: CGImage
    let size: CGSize
    let anchorPoint: CGPoint
}

@MainActor
private final class SystemCursorAssetLibrary {
    let arrowAsset: SystemCursorAsset?

    init() {
        self.arrowAsset = Self.rasterize(cursor: .arrow)
    }

    private static func rasterize(cursor: NSCursor) -> SystemCursorAsset? {
        let img = cursor.image
        let size = img.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale: CGFloat = 4.0
        let pxW = max(1, Int(ceil(size.width * scale)))
        let pxH = max(1, Int(ceil(size.height * scale)))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxW,
            pixelsHigh: pxH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            ctx.imageInterpolation = .high
            ctx.shouldAntialias = true
            NSGraphicsContext.current = ctx
            img.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = rep.cgImage else { return nil }
        let hot = cursor.hotSpot
        let anchor = CGPoint(
            x: max(0.0, min(1.0, hot.x / size.width)),
            y: max(0.0, min(1.0, 1.0 - (hot.y / size.height)))
        )
        return SystemCursorAsset(image: cgImage, size: size, anchorPoint: anchor)
    }
}

/// Authentic iPadOS resize pointer geometry (`UIPointerShape` + `UIPointerAccessory.arrowAccessoryWithPosition:`)
/// used when the user selects `Dot` mode so resize cursors match the translucent iPadOS material language.
@MainActor
final class OverlayWindowController {
    @MainActor
    private final class ScreenOverlay {
        let screen: NSScreen
        let panel: NSPanel
        let rootLayer: CALayer

        // 1. iPadOS Dot / Button Highlight / Dock Lift / Text I-beam material layer
        let pointerContainerLayer: CALayer
        let materialContainerLayer: CALayer
        let organicContourMaskLayer: CAShapeLayer
        let backdropLayer: CALayer?
        let lumaBackdropLayer: CALayer?
        let fallbackTintLayer: CALayer?
        let dotVividTintLayer: CALayer
        let beamContrastLayer: CALayer
        let colorMatrixFilter: NSObject?
        let gaussianBlurFilter: NSObject?
        let arrowBlurFilter: NSObject?
        let specularMaskLayer: CALayer
        let specularImageLayer: CALayer
        let axCenterDotLayer: CAShapeLayer
        let lumaBridge: LumaBridge

        // 7. VS Code-style Smooth Typing Caret layer
        let smoothCaretLayer: CALayer

        // 8. Inner pointer dot shown inside large snapped cards/widgets/Stage Manager tiles
        let innerPointerLayer: CALayer

        // 2. Official Apple Mouse Arrow (Retina 4x NSCursor.arrow, exact hotspot anchor)
        let arrowImageLayer: CALayer

        // 3. Authentic iPadOS Translucent Resize Cursor (CABackdropLayer + UIPointerAccessory) used in both Dot & Mouse modes
        let ipadResizeContainerLayer: CALayer
        let ipadResizeBackdropClipLayer: CALayer
        let ipadResizeBackdropLayer: CALayer?
        let ipadResizeMaskLayer: CAShapeLayer
        let ipadResizeRimLayer: CAShapeLayer

        // 4. Authentic iPadOS Translucent Screenshot Crosshair Reticle used in both Dot & Mouse modes
        let ipadCrosshairContainerLayer: CALayer
        let ipadCrosshairBackdropClipLayer: CALayer
        let ipadCrosshairBackdropLayer: CALayer?
        let ipadCrosshairContrastLayer: CALayer
        let ipadCrosshairRimLayer: CAShapeLayer

        // 5. Unified iPadOS Translucent Special Cursors (hand, dragCopy, dragLink, notAllowed, zoom, move, eyedropper, etc.)
        let ipadSpecialContainerLayer: CALayer
        let ipadSpecialBackdropClipLayer: CALayer
        let ipadSpecialBackdropLayer: CALayer?
        let ipadSpecialMaskLayer: CAShapeLayer
        let ipadSpecialRimLayer: CAShapeLayer

        // 6. Authentic Apple UIPointerAccessory directional arrows around snapped sliders & steppers
        let accessoryContainerLayer: CALayer
        let accessoryBackdropClipLayer: CALayer
        let accessoryBackdropLayer: CALayer?
        let accessoryMaskLayer: CAShapeLayer
        let accessoryRimLayer: CAShapeLayer

        private let cursorAssets: SystemCursorAssetLibrary
        private var lastAppliedMatrix: PointerColorMatrix?
        private var lastIPadResizeMatrix: PointerColorMatrix?
        private var lastIPadCrosshairMatrix: PointerColorMatrix?
        private var lastIPadSpecialMatrix: PointerColorMatrix?
        private var lastAccessoryMatrix: PointerColorMatrix?
        private var lastIPadResizeKind: ResizeCursorKind = .none
        private var lastIPadSpecialKind: SpecialCursorKind = .none
        private var lastAccessoryKind: PointerAccessoryKind = .none
        private var lastAccessoryTargetSize: CGSize = .zero
        private var isBlurFilterActive = false
        private var lastBlurRadius: CGFloat = 0
        private var isArrowBlurActive = false
        private var isOrganicMaskActive = false
        private var lastArrowBlurRadius: CGFloat = 0
        private var isLumaLayerEnabled = false
        private var lastRenderedState: PointerRenderState?
        private var lastRenderedLocalCenter: CGPoint = .zero
        private var lastRenderedProtectedBackdrop = false

        private static let disabledLayerActions: [String: CAAction] = [
            "position": NSNull(),
            "bounds": NSNull(),
            "frame": NSNull(),
            "transform": NSNull(),
            "opacity": NSNull(),
            "cornerRadius": NSNull(),
            "hidden": NSNull(),
            "path": NSNull(),
            "fillColor": NSNull(),
            "strokeColor": NSNull(),
            "backgroundColor": NSNull(),
            "borderColor": NSNull(),
            "borderWidth": NSNull()
        ]

        init(
            screen: NSScreen,
            specularCGImage: CGImage?,
            cursorAssets: SystemCursorAssetLibrary,
            onLumaChange: @escaping @Sendable (Double) -> Void
        ) {
            self.screen = screen
            self.cursorAssets = cursorAssets

            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.setFrame(screen.frame, display: false)
            // Use Apple's AssistiveTechHigh window level (1500): sits cleanly above fullscreen apps,
            // Dock, Notification Center, Menu Bar, context menus, popovers, Control Center, and ScreenSaver,
            // while staying below CGShieldingWindowLevel so macOS 26/27 fullscreen Spaces composite
            // and sample CABackdropLayer reliably.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.canHide = false
            // Keep .readOnly so screen recordings (Cmd+Shift+5 / CleanShot X video recording) capture
            // ApplePointer cleanly instead of the native cursor; still-screenshot selection overlays
            // suspend and orderOut these panels via setCaptureSuspended(true).
            panel.sharingType = .readOnly
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            contentView.wantsLayer = true
            let rootLayer = CALayer()
            rootLayer.frame = NSRect(origin: .zero, size: screen.frame.size)
            rootLayer.backgroundColor = NSColor.clear.cgColor
            contentView.layer = rootLayer
            panel.contentView = contentView

            let container = CALayer()
            container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            container.isHidden = true
            container.zPosition = 100
            container.actions = Self.disabledLayerActions

            let material = CALayer()
            material.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            material.masksToBounds = true
            material.cornerCurve = .continuous
            material.actions = Self.disabledLayerActions

            let organicMask = CAShapeLayer()
            organicMask.fillColor = NSColor.white.cgColor
            organicMask.contentsScale = screen.backingScaleFactor
            organicMask.actions = Self.disabledLayerActions

            let bridge = LumaBridge(handler: onLumaChange)
            self.lumaBridge = bridge

            let filterCls = NSClassFromString("CAFilter") as? NSObject.Type
            let filterSel = NSSelectorFromString("filterWithType:")

            let cmFilter = filterCls?.perform(filterSel, with: "colorMatrix")?.takeUnretainedValue() as? NSObject
            cmFilter?.setValue("colorMatrix", forKey: "name")
            self.colorMatrixFilter = cmFilter

            let gbFilter = filterCls?.perform(filterSel, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject
            gbFilter?.setValue("gaussianBlur", forKey: "name")
            gbFilter?.setValue(0.0, forKey: "inputRadius")
            self.gaussianBlurFilter = gbFilter

            let arrowGbFilter = filterCls?.perform(filterSel, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject
            arrowGbFilter?.setValue("gaussianBlur", forKey: "name")
            arrowGbFilter?.setValue(0.0, forKey: "inputRadius")
            self.arrowBlurFilter = arrowGbFilter

            var createdBackdrop: CALayer?
            var createdLumaBackdrop: CALayer?
            var createdFallback: CALayer?
            var createdIPadResizeBackdrop: CALayer?
            var createdIPadCrosshairBackdrop: CALayer?
            var createdIPadSpecialBackdrop: CALayer?
            var createdAccessoryBackdrop: CALayer?

            if let backdropCls = NSClassFromString("CABackdropLayer") as? CALayer.Type {
                let bLayer = backdropCls.init()
                bLayer.setValue(true, forKey: "windowServerAware")
                bLayer.setValue(true, forKey: "allowsInPlaceFiltering")
                bLayer.setValue(true, forKey: "disableFilterCache")
                bLayer.setValue(true, forKey: "enabled")
                bLayer.setValue(1.0, forKey: "scale")
                bLayer.setValue("ApplePointerMaterialBackdrop", forKey: "groupName")
                bLayer.setValue("hostingNamespacedContext", forKey: "groupNamespace")
                bLayer.setValue(false, forKey: "usesGlobalGroupNamespace")
                bLayer.setValue(false, forKey: "tracksLuma")
                bLayer.actions = Self.disabledLayerActions
                if let cmFilter {
                    bLayer.setValue([cmFilter], forKey: "filters")
                }
                bLayer.contentsScale = screen.backingScaleFactor
                material.addSublayer(bLayer)
                createdBackdrop = bLayer

                let lumaLayer = backdropCls.init()
                lumaLayer.setValue(true, forKey: "windowServerAware")
                lumaLayer.setValue(false, forKey: "allowsInPlaceFiltering")
                lumaLayer.setValue(false, forKey: "enabled")
                lumaLayer.setValue(true, forKey: "captureOnly")
                lumaLayer.setValue(1.0, forKey: "scale")
                lumaLayer.setValue("ApplePointerLumaBackdrop", forKey: "groupName")
                lumaLayer.setValue("hostingNamespacedContext", forKey: "groupNamespace")
                lumaLayer.setValue(false, forKey: "usesGlobalGroupNamespace")
                lumaLayer.setValue(true, forKey: "tracksLuma")
                lumaLayer.setValue(0.14, forKey: "lumaUpdateRate")
                lumaLayer.delegate = bridge
                lumaLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                lumaLayer.zPosition = 50
                lumaLayer.isHidden = true
                lumaLayer.contentsScale = screen.backingScaleFactor
                lumaLayer.actions = Self.disabledLayerActions
                rootLayer.addSublayer(lumaLayer)
                createdLumaBackdrop = lumaLayer

                let rbLayer = backdropCls.init()
                rbLayer.setValue(true, forKey: "windowServerAware")
                rbLayer.setValue(true, forKey: "allowsInPlaceFiltering")
                rbLayer.setValue(true, forKey: "disableFilterCache")
                rbLayer.setValue(true, forKey: "enabled")
                rbLayer.setValue(1.0, forKey: "scale")
                rbLayer.setValue("ApplePointerResizeBackdrop", forKey: "groupName")
                rbLayer.setValue("hostingNamespacedContext", forKey: "groupNamespace")
                rbLayer.setValue(false, forKey: "usesGlobalGroupNamespace")
                rbLayer.setValue(false, forKey: "tracksLuma")
                rbLayer.actions = Self.disabledLayerActions
                if let resizeCM = filterCls?.perform(filterSel, with: "colorMatrix")?.takeUnretainedValue() as? NSObject {
                    resizeCM.setValue("colorMatrix", forKey: "name")
                    rbLayer.setValue([resizeCM], forKey: "filters")
                }
                rbLayer.contentsScale = screen.backingScaleFactor
                createdIPadResizeBackdrop = rbLayer

                let cbLayer = backdropCls.init()
                cbLayer.setValue(true, forKey: "windowServerAware")
                cbLayer.setValue(true, forKey: "allowsInPlaceFiltering")
                cbLayer.setValue(true, forKey: "disableFilterCache")
                cbLayer.setValue(true, forKey: "enabled")
                cbLayer.setValue(1.0, forKey: "scale")
                cbLayer.setValue("ApplePointerCrosshairBackdrop", forKey: "groupName")
                cbLayer.setValue("hostingNamespacedContext", forKey: "groupNamespace")
                cbLayer.setValue(false, forKey: "usesGlobalGroupNamespace")
                cbLayer.setValue(false, forKey: "tracksLuma")
                cbLayer.actions = Self.disabledLayerActions
                if let crossCM = filterCls?.perform(filterSel, with: "colorMatrix")?.takeUnretainedValue() as? NSObject {
                    crossCM.setValue("colorMatrix", forKey: "name")
                    cbLayer.setValue([crossCM], forKey: "filters")
                }
                cbLayer.contentsScale = screen.backingScaleFactor
                createdIPadCrosshairBackdrop = cbLayer

                func makeGlyphBackdrop(groupName: String) -> CALayer {
                    let gl = backdropCls.init()
                    gl.setValue(true, forKey: "windowServerAware")
                    gl.setValue(true, forKey: "allowsInPlaceFiltering")
                    gl.setValue(true, forKey: "disableFilterCache")
                    gl.setValue(true, forKey: "enabled")
                    gl.setValue(1.0, forKey: "scale")
                    gl.setValue(groupName, forKey: "groupName")
                    gl.setValue("hostingNamespacedContext", forKey: "groupNamespace")
                    gl.setValue(false, forKey: "usesGlobalGroupNamespace")
                    gl.setValue(false, forKey: "tracksLuma")
                    gl.actions = Self.disabledLayerActions
                    if let cm = filterCls?.perform(filterSel, with: "colorMatrix")?.takeUnretainedValue() as? NSObject {
                        cm.setValue("colorMatrix", forKey: "name")
                        gl.setValue([cm], forKey: "filters")
                    }
                    gl.contentsScale = screen.backingScaleFactor
                    return gl
                }
                createdIPadSpecialBackdrop = makeGlyphBackdrop(groupName: "ApplePointerSpecialBackdrop")
                createdAccessoryBackdrop = makeGlyphBackdrop(groupName: "ApplePointerAccessoryBackdrop")

                fputs("[ApplePointer] Overlay screen=\(screen.frame) level=\(panel.level.rawValue) CABackdropLayer+CAFilter(colorMatrix=\(cmFilter != nil)) + lumaBackdrop initialized\n", stderr)
                fflush(stderr)
            } else {
                let fallback = CALayer()
                fallback.backgroundColor = NSColor(white: 0.45, alpha: 0.65).cgColor
                material.addSublayer(fallback)
                createdFallback = fallback
                fputs("[ApplePointer] Overlay screen=\(screen.frame) using fallbackTintLayer (CABackdropLayer unavailable)\n", stderr)
                fflush(stderr)
            }

            let dotVividTint = CALayer()
            dotVividTint.isHidden = true
            dotVividTint.actions = Self.disabledLayerActions
            material.addSublayer(dotVividTint)

            let beamContrast = CALayer()
            beamContrast.isHidden = true
            beamContrast.actions = Self.disabledLayerActions
            material.addSublayer(beamContrast)

            self.backdropLayer = createdBackdrop
            self.lumaBackdropLayer = createdLumaBackdrop
            self.fallbackTintLayer = createdFallback
            self.dotVividTintLayer = dotVividTint
            self.beamContrastLayer = beamContrast
            self.ipadResizeBackdropLayer = createdIPadResizeBackdrop
            self.ipadCrosshairBackdropLayer = createdIPadCrosshairBackdrop
            self.ipadSpecialBackdropLayer = createdIPadSpecialBackdrop
            self.accessoryBackdropLayer = createdAccessoryBackdrop

            let specMask = CALayer()
            specMask.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            specMask.masksToBounds = true
            specMask.cornerCurve = .continuous

            let specImg = CALayer()
            specImg.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            specImg.contents = specularCGImage
            specImg.contentsGravity = .resizeAspect
            specImg.bounds = CGRect(x: 0, y: 0, width: 150, height: 150)
            specImg.opacity = 0.0
            if let plusL = filterCls?.perform(filterSel, with: "plusL")?.takeUnretainedValue() {
                specImg.compositingFilter = plusL
            }
            specMask.addSublayer(specImg)

            let centerDot = CAShapeLayer()
            centerDot.strokeColor = nil
            centerDot.isHidden = true
            centerDot.actions = Self.disabledLayerActions

            container.addSublayer(material)
            container.addSublayer(specMask)
            container.addSublayer(centerDot)
            rootLayer.addSublayer(container)

            // 2. Official Apple Mouse Arrow layer (exact NSCursor.arrow 4x Retina)
            let arrowLayer = CALayer()
            arrowLayer.zPosition = 110
            arrowLayer.isHidden = true
            arrowLayer.contentsScale = 4.0
            arrowLayer.magnificationFilter = .trilinear
            arrowLayer.minificationFilter = .trilinear
            if let asset = cursorAssets.arrowAsset {
                arrowLayer.contents = asset.image
                arrowLayer.bounds = CGRect(origin: .zero, size: asset.size)
                arrowLayer.anchorPoint = asset.anchorPoint
            }
            rootLayer.addSublayer(arrowLayer)

            // 3. Authentic iPadOS Translucent Resize Cursor layer (CABackdropLayer + UIPointerAccessory)
            let ipadResizeSize = IPadResizePaths.canvasSize
            let ipadResizeContainer = CALayer()
            ipadResizeContainer.bounds = CGRect(origin: .zero, size: ipadResizeSize)
            ipadResizeContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ipadResizeContainer.zPosition = 115
            ipadResizeContainer.isHidden = true

            let ipadResizeClip = CALayer()
            ipadResizeClip.frame = CGRect(origin: .zero, size: ipadResizeSize)
            let ipadResizeMask = CAShapeLayer()
            ipadResizeMask.frame = CGRect(origin: .zero, size: ipadResizeSize)
            ipadResizeMask.fillColor = NSColor.white.cgColor
            ipadResizeMask.contentsScale = screen.backingScaleFactor
            ipadResizeClip.mask = ipadResizeMask
            if let createdIPadResizeBackdrop {
                createdIPadResizeBackdrop.frame = CGRect(origin: .zero, size: ipadResizeSize)
                ipadResizeClip.addSublayer(createdIPadResizeBackdrop)
            } else {
                ipadResizeClip.backgroundColor = NSColor(white: 0.5, alpha: 0.8).cgColor
            }
            ipadResizeContainer.addSublayer(ipadResizeClip)

            let ipadResizeRim = CAShapeLayer()
            ipadResizeRim.frame = CGRect(origin: .zero, size: ipadResizeSize)
            ipadResizeRim.fillColor = nil
            ipadResizeRim.lineWidth = 0.85
            ipadResizeRim.lineJoin = .round
            ipadResizeRim.contentsScale = screen.backingScaleFactor
            ipadResizeRim.shadowColor = NSColor.black.cgColor
            ipadResizeRim.shadowOpacity = 0.24
            ipadResizeRim.shadowRadius = 1.8
            ipadResizeRim.shadowOffset = CGSize(width: 0, height: -0.6)
            ipadResizeContainer.addSublayer(ipadResizeRim)

            rootLayer.addSublayer(ipadResizeContainer)

            // 4. Authentic iPadOS Translucent Screenshot Crosshair Reticle
            let crosshairPath = IPadResizePaths.makeCrosshairPath()
            let ipadCrosshairContainer = CALayer()
            ipadCrosshairContainer.bounds = CGRect(origin: .zero, size: ipadResizeSize)
            ipadCrosshairContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ipadCrosshairContainer.zPosition = 118
            ipadCrosshairContainer.isHidden = true

            let ipadCrosshairClip = CALayer()
            ipadCrosshairClip.frame = CGRect(origin: .zero, size: ipadResizeSize)
            let ipadCrosshairMask = CAShapeLayer()
            ipadCrosshairMask.frame = CGRect(origin: .zero, size: ipadResizeSize)
            ipadCrosshairMask.fillColor = NSColor.white.cgColor
            ipadCrosshairMask.path = crosshairPath
            ipadCrosshairMask.contentsScale = screen.backingScaleFactor
            ipadCrosshairClip.mask = ipadCrosshairMask
            let ipadCrosshairContrast = CALayer()
            ipadCrosshairContrast.frame = CGRect(origin: .zero, size: ipadResizeSize)
            ipadCrosshairContrast.actions = Self.disabledLayerActions
            if let createdIPadCrosshairBackdrop {
                createdIPadCrosshairBackdrop.frame = CGRect(origin: .zero, size: ipadResizeSize)
                ipadCrosshairClip.addSublayer(createdIPadCrosshairBackdrop)
            } else {
                ipadCrosshairClip.backgroundColor = NSColor(white: 0.5, alpha: 0.85).cgColor
            }
            ipadCrosshairClip.addSublayer(ipadCrosshairContrast)
            ipadCrosshairContainer.addSublayer(ipadCrosshairClip)

            let ipadCrosshairRim = CAShapeLayer()
            ipadCrosshairRim.frame = CGRect(origin: .zero, size: ipadResizeSize)
            ipadCrosshairRim.path = crosshairPath
            ipadCrosshairRim.fillColor = nil
            ipadCrosshairRim.lineWidth = 0.85
            ipadCrosshairRim.lineJoin = .round
            ipadCrosshairRim.contentsScale = screen.backingScaleFactor
            ipadCrosshairRim.shadowColor = NSColor.black.cgColor
            ipadCrosshairRim.shadowOpacity = 0.28
            ipadCrosshairRim.shadowRadius = 1.6
            ipadCrosshairRim.shadowOffset = .zero
            ipadCrosshairContainer.addSublayer(ipadCrosshairRim)
            rootLayer.addSublayer(ipadCrosshairContainer)

            // 5. Unified iPadOS Translucent Special Cursors layer
            let specialSize = IPadSpecialCursorPaths.canvasSize
            let ipadSpecialContainer = CALayer()
            ipadSpecialContainer.bounds = CGRect(origin: .zero, size: specialSize)
            ipadSpecialContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ipadSpecialContainer.zPosition = 117
            ipadSpecialContainer.isHidden = true
            ipadSpecialContainer.actions = Self.disabledLayerActions

            let ipadSpecialClip = CALayer()
            ipadSpecialClip.frame = CGRect(origin: .zero, size: specialSize)
            ipadSpecialClip.actions = Self.disabledLayerActions
            let ipadSpecialMask = CAShapeLayer()
            ipadSpecialMask.frame = CGRect(origin: .zero, size: specialSize)
            ipadSpecialMask.fillColor = NSColor.white.cgColor
            ipadSpecialMask.fillRule = .evenOdd
            ipadSpecialMask.contentsScale = screen.backingScaleFactor
            ipadSpecialMask.actions = Self.disabledLayerActions
            ipadSpecialClip.mask = ipadSpecialMask
            if let createdIPadSpecialBackdrop {
                createdIPadSpecialBackdrop.frame = CGRect(origin: .zero, size: specialSize)
                ipadSpecialClip.addSublayer(createdIPadSpecialBackdrop)
            } else {
                ipadSpecialClip.backgroundColor = NSColor(white: 0.5, alpha: 0.85).cgColor
            }
            ipadSpecialContainer.addSublayer(ipadSpecialClip)

            let ipadSpecialRim = CAShapeLayer()
            ipadSpecialRim.frame = CGRect(origin: .zero, size: specialSize)
            ipadSpecialRim.fillColor = nil
            ipadSpecialRim.lineWidth = 0.85
            ipadSpecialRim.lineJoin = .round
            ipadSpecialRim.lineCap = .round
            ipadSpecialRim.contentsScale = screen.backingScaleFactor
            ipadSpecialRim.shadowColor = NSColor.black.cgColor
            ipadSpecialRim.shadowOpacity = 0.25
            ipadSpecialRim.shadowRadius = 1.8
            ipadSpecialRim.shadowOffset = CGSize(width: 0, height: -0.6)
            ipadSpecialRim.actions = Self.disabledLayerActions
            ipadSpecialContainer.addSublayer(ipadSpecialRim)
            rootLayer.addSublayer(ipadSpecialContainer)

            // 6. Authentic Apple UIPointerAccessory directional arrows layer
            let accContainer = CALayer()
            accContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            accContainer.zPosition = 104
            accContainer.isHidden = true
            accContainer.actions = Self.disabledLayerActions

            let accClip = CALayer()
            accClip.actions = Self.disabledLayerActions
            let accMask = CAShapeLayer()
            accMask.fillColor = NSColor.white.cgColor
            accMask.contentsScale = screen.backingScaleFactor
            accMask.actions = Self.disabledLayerActions
            accClip.mask = accMask
            if let createdAccessoryBackdrop {
                accClip.addSublayer(createdAccessoryBackdrop)
            } else {
                accClip.backgroundColor = NSColor(white: 0.5, alpha: 0.8).cgColor
            }
            accContainer.addSublayer(accClip)

            let accRim = CAShapeLayer()
            accRim.fillColor = nil
            accRim.lineWidth = 0.75
            accRim.lineJoin = .round
            accRim.contentsScale = screen.backingScaleFactor
            accRim.actions = Self.disabledLayerActions
            accContainer.addSublayer(accRim)
            rootLayer.addSublayer(accContainer)

            // 7. VS Code-style Smooth Typing Caret
            let caretLayer = CALayer()
            caretLayer.zPosition = 108
            caretLayer.isHidden = true
            caretLayer.cornerRadius = 1.0
            caretLayer.cornerCurve = .continuous
            caretLayer.shadowOpacity = 0.0
            caretLayer.actions = Self.disabledLayerActions
            rootLayer.addSublayer(caretLayer)

            // 8. Translucent inner pointer dot when snapped to large cards/widgets/Stage Manager tiles
            let innerDot = CALayer()
            innerDot.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            innerDot.zPosition = 109
            innerDot.isHidden = true
            innerDot.borderWidth = 0.9
            innerDot.shadowColor = NSColor.black.cgColor
            innerDot.shadowRadius = 2.2
            innerDot.shadowOffset = CGSize(width: 0, height: -0.6)
            innerDot.actions = Self.disabledLayerActions
            rootLayer.addSublayer(innerDot)

            self.panel = panel
            self.rootLayer = rootLayer
            self.pointerContainerLayer = container
            self.materialContainerLayer = material
            self.organicContourMaskLayer = organicMask
            self.specularMaskLayer = specMask
            self.specularImageLayer = specImg
            self.axCenterDotLayer = centerDot
            self.smoothCaretLayer = caretLayer
            self.innerPointerLayer = innerDot
            self.arrowImageLayer = arrowLayer
            self.ipadResizeContainerLayer = ipadResizeContainer
            self.ipadResizeBackdropClipLayer = ipadResizeClip
            self.ipadResizeMaskLayer = ipadResizeMask
            self.ipadResizeRimLayer = ipadResizeRim
            self.ipadCrosshairContainerLayer = ipadCrosshairContainer
            self.ipadCrosshairBackdropClipLayer = ipadCrosshairClip
            self.ipadCrosshairContrastLayer = ipadCrosshairContrast
            self.ipadCrosshairRimLayer = ipadCrosshairRim
            self.ipadSpecialContainerLayer = ipadSpecialContainer
            self.ipadSpecialBackdropClipLayer = ipadSpecialClip
            self.ipadSpecialMaskLayer = ipadSpecialMask
            self.ipadSpecialRimLayer = ipadSpecialRim
            self.accessoryContainerLayer = accContainer
            self.accessoryBackdropClipLayer = accClip
            self.accessoryMaskLayer = accMask
            self.accessoryRimLayer = accRim

            panel.orderFrontRegardless()
        }

        func hide() {
            lastRenderedState = nil
            if !pointerContainerLayer.isHidden {
                pointerContainerLayer.isHidden = true
            }
            if !arrowImageLayer.isHidden {
                arrowImageLayer.isHidden = true
            }
            if !ipadResizeContainerLayer.isHidden {
                ipadResizeContainerLayer.isHidden = true
            }
            if !ipadCrosshairContainerLayer.isHidden {
                ipadCrosshairContainerLayer.isHidden = true
            }
            if !ipadSpecialContainerLayer.isHidden {
                ipadSpecialContainerLayer.isHidden = true
            }
            if !accessoryContainerLayer.isHidden {
                accessoryContainerLayer.isHidden = true
            }
            if !innerPointerLayer.isHidden {
                innerPointerLayer.isHidden = true
            }
            if let lumaBackdropLayer, !lumaBackdropLayer.isHidden {
                lumaBackdropLayer.isHidden = true
            }
            if let lumaBackdropLayer, isLumaLayerEnabled {
                lumaBackdropLayer.setValue(false, forKey: "enabled")
                isLumaLayerEnabled = false
            }
        }

        func renderSmoothCaret(_ caret: SmoothCaretRenderState, primaryHeight: CGFloat, visible: Bool) {
            guard visible && caret.isVisible && caret.opacity > 0.01 else {
                if !smoothCaretLayer.isHidden {
                    smoothCaretLayer.isHidden = true
                }
                return
            }
            let appKitCenter = CGPoint(x: caret.rect.midX, y: primaryHeight - caret.rect.midY)
            guard screen.frame.contains(appKitCenter) else {
                if !smoothCaretLayer.isHidden {
                    smoothCaretLayer.isHidden = true
                }
                return
            }
            let localCenter = CGPoint(
                x: appKitCenter.x - screen.frame.origin.x,
                y: appKitCenter.y - screen.frame.origin.y
            )
            if smoothCaretLayer.isHidden {
                smoothCaretLayer.isHidden = false
            }
            smoothCaretLayer.bounds = CGRect(origin: .zero, size: caret.rect.size)
            smoothCaretLayer.position = localCenter
            smoothCaretLayer.cornerRadius = caret.rect.width * 0.5
            // Use Apple's system accent caret color with a gentle luminous halo so the gliding typing caret
            // stays crisp on both light and dark editors regardless of where the mouse pointer is parked.
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
            let caretColor = accent.blended(withFraction: 0.18, of: .white) ?? accent
            smoothCaretLayer.backgroundColor = caretColor.cgColor
            smoothCaretLayer.shadowColor = accent.cgColor
            smoothCaretLayer.shadowRadius = 2.6
            smoothCaretLayer.shadowOffset = .zero
            smoothCaretLayer.shadowOpacity = 0.42
            smoothCaretLayer.opacity = Float(caret.opacity)
        }

        func render(
            state: PointerRenderState,
            localCenter: CGPoint,
            visible: Bool
        ) {
            guard visible else {
                hide()
                return
            }
            let isProtectedBackdrop = lumaBridge.isProtectedBackdrop
            if let prev = lastRenderedState,
               prev == state,
               isProtectedBackdrop == lastRenderedProtectedBackdrop,
               abs(localCenter.x - lastRenderedLocalCenter.x) < 0.01,
               abs(localCenter.y - lastRenderedLocalCenter.y) < 0.01 {
                return
            }
            lastRenderedState = state
            lastRenderedLocalCenter = localCenter
            lastRenderedProtectedBackdrop = isProtectedBackdrop

            let organicRadii = state.organicContourRadii
            let hasOrganicContour = (organicRadii?.count == OrganicContour.sampleCount)
            let bounds: CGRect
            if let organicRadii, hasOrganicContour {
                let maxR = max(organicRadii.max() ?? 10.0, 8.0)
                let side = ceil(maxR * 2.0 + 4.0)
                bounds = CGRect(x: 0.0, y: 0.0, width: side, height: side)
            } else {
                bounds = CGRect(origin: .zero, size: state.size)
            }
            let mid = CGPoint(x: bounds.midX, y: bounds.midY)
            let maxCornerRadius = min(bounds.width, bounds.height) * 0.5
            let clampedCornerRadius = max(0.0, min(state.cornerRadius, maxCornerRadius))

            // 1. Neutral captureOnly luma sensor positioned under the active pointer
            if let lumaBackdropLayer {
                let shouldTrackLuma = state.opacity > 0.02
                if shouldTrackLuma != isLumaLayerEnabled {
                    lumaBackdropLayer.setValue(shouldTrackLuma, forKey: "enabled")
                    isLumaLayerEnabled = shouldTrackLuma
                }
                if shouldTrackLuma {
                    if lumaBackdropLayer.isHidden {
                        lumaBackdropLayer.isHidden = false
                    }
                    if state.arrowBlend > 0.5 {
                        let probeSide = max(20.0, 22.0 * state.pointerSizeMultiplier)
                        lumaBackdropLayer.bounds = CGRect(x: 0, y: 0, width: probeSide, height: probeSide)
                        lumaBackdropLayer.position = CGPoint(
                            x: localCenter.x + 6.0 * state.pointerSizeMultiplier,
                            y: localCenter.y - 8.5 * state.pointerSizeMultiplier
                        )
                        lumaBackdropLayer.transform = CATransform3DIdentity
                    } else {
                        lumaBackdropLayer.bounds = bounds
                        lumaBackdropLayer.position = localCenter
                        lumaBackdropLayer.transform = CATransform3DMakeScale(state.totalScale, state.totalScale, 1.0)
                    }
                } else if !lumaBackdropLayer.isHidden {
                    lumaBackdropLayer.isHidden = true
                }
            }

            // 2. Material rounded-rect / Text I-beam / iPadOS Dot layer
            let isLiquidGlass = state.materialPreset == .liquidGlass
            let shapeMaskOpacity = max(0.0, 1.0 - max(state.arrowBlend, max(state.resizeBlend, max(state.crosshairBlend, state.specialCursorBlend))))
            let rectEffectiveOpacity = state.opacity * shapeMaskOpacity
            if rectEffectiveOpacity > 0.005 {
                if pointerContainerLayer.isHidden {
                    pointerContainerLayer.isHidden = false
                }
                pointerContainerLayer.bounds = bounds
                pointerContainerLayer.position = localCenter
                if abs(state.perspectiveTiltY) > 0.001 {
                    // True 3D perspective tilt matching macOS Stage Manager cards
                    var transform = CATransform3DIdentity
                    transform.m34 = -1.0 / 650.0
                    transform = CATransform3DRotate(transform, state.perspectiveTiltY, 0.0, 1.0, 0.0)
                    transform = CATransform3DScale(
                        transform,
                        state.totalScale * state.elasticScaleX,
                        state.totalScale * state.elasticScaleY,
                        1.0
                    )
                    pointerContainerLayer.transform = transform
                } else {
                    pointerContainerLayer.transform = CATransform3DMakeScale(
                        state.totalScale * state.elasticScaleX,
                        state.totalScale * state.elasticScaleY,
                        1.0
                    )
                }
                pointerContainerLayer.opacity = Float(rectEffectiveOpacity)

                // Exact 1-to-1 iPadOS 27 pointeruid (PUIDPointerShapeView) pipeline:
                // pure CABackdropLayer + CAFilter("colorMatrix") + Specular@2x.png ("plusL").
                // No synthetic drop shadows, fake flat sheen gradients, or hard border strokes.
                if state.isBeam {
                    pointerContainerLayer.shadowColor = (state.isDarkBackground ? NSColor.black : NSColor.white).cgColor
                    pointerContainerLayer.shadowOpacity = 0.45
                    pointerContainerLayer.shadowRadius = 1.4
                    pointerContainerLayer.shadowOffset = .zero
                    pointerContainerLayer.shadowPath = nil
                } else if pointerContainerLayer.shadowOpacity != 0 {
                    pointerContainerLayer.shadowOpacity = 0
                    pointerContainerLayer.shadowPath = nil
                }

                applyBlur(state.blurRadius, to: pointerContainerLayer, filter: gaussianBlurFilter, activeFlag: &isBlurFilterActive, lastRadius: &lastBlurRadius)

                materialContainerLayer.bounds = bounds
                materialContainerLayer.position = mid
                materialContainerLayer.opacity = Float(state.intensity)
                if materialContainerLayer.borderWidth != 0 {
                    materialContainerLayer.borderWidth = 0
                    materialContainerLayer.borderColor = nil
                }
                if let organicRadii, hasOrganicContour {
                    organicContourMaskLayer.frame = bounds
                    organicContourMaskLayer.path = Self.makeSmoothOrganicPath(radii: organicRadii, center: mid)
                    if !isOrganicMaskActive {
                        materialContainerLayer.cornerRadius = 0.0
                        materialContainerLayer.mask = organicContourMaskLayer
                        isOrganicMaskActive = true
                    }
                } else {
                    if isOrganicMaskActive {
                        materialContainerLayer.mask = nil
                        isOrganicMaskActive = false
                    }
                    materialContainerLayer.cornerRadius = clampedCornerRadius
                }

                if let backdropLayer {
                    backdropLayer.frame = bounds
                    if state.colorMatrix != lastAppliedMatrix {
                        backdropLayer.setValue(state.colorMatrix.asNSValue(), forKeyPath: "filters.colorMatrix.inputColorMatrix")
                        lastAppliedMatrix = state.colorMatrix
                    }
                } else if let fallbackTintLayer {
                    fallbackTintLayer.frame = bounds
                    let white: CGFloat = state.isDarkBackground ? 0.92 : 0.22
                    fallbackTintLayer.backgroundColor = NSColor(white: white, alpha: 0.72).cgColor
                }

                // Only apply non-backdrop fallback tint when WindowServer explicitly reports a protected
                // DRM/unsamplable fullscreen surface so the pointer never disappears; on all normal surfaces,
                // let Apple's pure CABackdropLayer + CAColorMatrix render cleanly with zero extra tint layers.
                if isProtectedBackdrop && !state.isBeam {
                    dotVividTintLayer.isHidden = false
                    dotVividTintLayer.frame = bounds
                    let t = state.lumaMix
                    let tintWhite: CGFloat = 0.16 + (0.94 - 0.16) * t
                    let tintAlpha: CGFloat = state.isSnapped ? 0.28 : 0.58
                    dotVividTintLayer.backgroundColor = NSColor(white: tintWhite, alpha: tintAlpha).cgColor
                } else if !dotVividTintLayer.isHidden {
                    dotVividTintLayer.isHidden = true
                }

                if state.isBeam {
                    beamContrastLayer.isHidden = false
                    beamContrastLayer.frame = bounds
                    let t = state.lumaMix
                    let coreWhite: CGFloat = 0.14 + (0.96 - 0.14) * t
                    let coreAlpha: CGFloat = state.highContrast ? 0.65 : 0.42
                    beamContrastLayer.backgroundColor = NSColor(white: coreWhite, alpha: coreAlpha).cgColor
                } else if !beamContrastLayer.isHidden {
                    beamContrastLayer.isHidden = true
                }

                specularMaskLayer.bounds = bounds
                specularMaskLayer.position = mid
                specularMaskLayer.cornerRadius = clampedCornerRadius
                specularImageLayer.position = CGPoint(
                    x: mid.x + state.specularOffset.x,
                    y: mid.y - state.specularOffset.y
                )
                specularImageLayer.transform = CATransform3DMakeScale(state.specularScale, state.specularScale, 1.0)
                // Exact Apple pointeruid Specular@2x.png ("plusL") highlight glide inside snapped controls
                let visualSpecular = state.isSnapped && !state.isBeam
                    ? min(0.24, state.specularAlpha * (isLiquidGlass ? 2.2 : 1.6))
                    : 0.0
                specularImageLayer.opacity = Float(visualSpecular)

                if state.showCenterDot {
                    axCenterDotLayer.isHidden = false
                    let dotR: CGFloat = max(1.8, min(3.8, min(bounds.width, bounds.height) * 0.19))
                    let dotRect = CGRect(x: mid.x - dotR, y: mid.y - dotR, width: dotR * 2, height: dotR * 2)
                    axCenterDotLayer.frame = bounds
                    axCenterDotLayer.path = CGPath(ellipseIn: dotRect, transform: nil)
                    axCenterDotLayer.fillColor = (state.isDarkBackground ? NSColor.white : NSColor.black).withAlphaComponent(0.85).cgColor
                } else {
                    axCenterDotLayer.isHidden = true
                }
            } else if !pointerContainerLayer.isHidden {
                pointerContainerLayer.isHidden = true
            }

            // 2b. Inner pointer dot inside large snapped cards, widgets, notifications & Stage Manager tiles
            let innerOpacity = state.opacity * state.innerPointerAlpha * shapeMaskOpacity
            if innerOpacity > 0.01 {
                if innerPointerLayer.isHidden {
                    innerPointerLayer.isHidden = false
                }
                let side = max(9.0, min(16.0, 11.5 * state.pointerSizeMultiplier))
                innerPointerLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                innerPointerLayer.cornerRadius = side * 0.5
                innerPointerLayer.position = CGPoint(
                    x: localCenter.x + state.innerPointerOffset.x,
                    y: localCenter.y - state.innerPointerOffset.y
                )
                innerPointerLayer.transform = CATransform3DMakeScale(state.totalScale, state.totalScale, 1.0)
                let t = state.lumaMix
                let fillWhite: CGFloat = 0.18 + (0.96 - 0.18) * t
                let fillAlpha: CGFloat = state.highContrast ? 0.86 : (0.58 + 0.12 * t)
                innerPointerLayer.backgroundColor = NSColor(white: fillWhite, alpha: fillAlpha).cgColor
                let rimWhite: CGFloat = state.isDarkBackground ? 1.0 : 0.96
                innerPointerLayer.borderColor = NSColor(white: rimWhite, alpha: state.isDarkBackground ? 0.52 : 0.44).cgColor
                innerPointerLayer.shadowOpacity = state.isDarkBackground ? 0.30 : 0.18
                innerPointerLayer.opacity = Float(innerOpacity)
            } else if !innerPointerLayer.isHidden {
                innerPointerLayer.isHidden = true
            }

            // 3. Official Apple Mouse Arrow (exact macOS 27 / iPadOS 26 NSCursor.arrow)
            let arrowOpacity = state.opacity * state.arrowBlend
            if arrowOpacity > 0.005, cursorAssets.arrowAsset != nil {
                if arrowImageLayer.isHidden {
                    arrowImageLayer.isHidden = false
                }
                let morphScale = 0.84 + 0.16 * state.arrowBlend
                let totalArrowScale = state.pointerSizeMultiplier * state.totalScale * morphScale
                arrowImageLayer.position = localCenter
                arrowImageLayer.transform = CATransform3DMakeScale(totalArrowScale, totalArrowScale, 1.0)
                arrowImageLayer.opacity = Float(arrowOpacity)

                applyBlur(state.blurRadius, to: arrowImageLayer, filter: arrowBlurFilter, activeFlag: &isArrowBlurActive, lastRadius: &lastArrowBlurRadius)
            } else if !arrowImageLayer.isHidden {
                arrowImageLayer.isHidden = true
            }

            // 4. Custom iPadOS Translucent Resize Cursor (used in both Dot and Mouse modes;
            // Mouse mode only swaps the free-floating dot for the Apple arrow).
            let resizeOpacity = state.opacity * state.resizeBlend
            if resizeOpacity > 0.005 && state.resizeKind != .none {
                let morphScale = 0.84 + 0.16 * state.resizeBlend
                let totalResizeScale = state.pointerSizeMultiplier * state.totalScale * morphScale

                if ipadResizeContainerLayer.isHidden {
                    ipadResizeContainerLayer.isHidden = false
                }
                if state.resizeKind != lastIPadResizeKind {
                    let path = IPadResizePaths.makeCenteredPath(kind: state.resizeKind)
                    ipadResizeMaskLayer.path = path
                    ipadResizeRimLayer.path = path
                    lastIPadResizeKind = state.resizeKind
                }
                ipadResizeContainerLayer.position = localCenter
                ipadResizeContainerLayer.transform = CATransform3DMakeScale(totalResizeScale, totalResizeScale, 1.0)
                ipadResizeContainerLayer.opacity = Float(resizeOpacity)

                let materialAlpha = state.highContrast ? 1.0 : ApplePointerConstants.Material.materialAlphaDot
                ipadResizeBackdropClipLayer.opacity = Float(materialAlpha)
                if let ipadResizeBackdropLayer, state.colorMatrix != lastIPadResizeMatrix {
                    ipadResizeBackdropLayer.setValue(state.colorMatrix.asNSValue(), forKeyPath: "filters.colorMatrix.inputColorMatrix")
                    lastIPadResizeMatrix = state.colorMatrix
                }

                let t = state.lumaMix
                let rimWhite: CGFloat = 0.15 + (0.95 - 0.15) * t
                ipadResizeRimLayer.strokeColor = NSColor(white: rimWhite, alpha: state.highContrast ? 0.55 : 0.30).cgColor
            } else if !ipadResizeContainerLayer.isHidden {
                ipadResizeContainerLayer.isHidden = true
            }

            // 5. Custom iPadOS Translucent Screenshot Crosshair Reticle (used in both Dot and Mouse modes)
            let crosshairOpacity = state.opacity * state.crosshairBlend
            if crosshairOpacity > 0.005 {
                let morphScale = 0.84 + 0.16 * state.crosshairBlend
                let totalCrossScale = state.pointerSizeMultiplier * state.totalScale * morphScale

                if ipadCrosshairContainerLayer.isHidden {
                    ipadCrosshairContainerLayer.isHidden = false
                }
                ipadCrosshairContainerLayer.position = localCenter
                ipadCrosshairContainerLayer.transform = CATransform3DMakeScale(totalCrossScale, totalCrossScale, 1.0)
                ipadCrosshairContainerLayer.opacity = Float(crosshairOpacity)

                let materialAlpha = state.highContrast ? 1.0 : ApplePointerConstants.Material.materialAlphaDot
                ipadCrosshairBackdropClipLayer.opacity = Float(materialAlpha)
                if let ipadCrosshairBackdropLayer, state.colorMatrix != lastIPadCrosshairMatrix {
                    ipadCrosshairBackdropLayer.setValue(state.colorMatrix.asNSValue(), forKeyPath: "filters.colorMatrix.inputColorMatrix")
                    lastIPadCrosshairMatrix = state.colorMatrix
                }

                let t = state.lumaMix
                let rimWhite: CGFloat = 0.12 + (0.96 - 0.12) * t
                let contrastWhite: CGFloat = 0.16 + (0.95 - 0.16) * t
                let contrastAlpha: CGFloat = isProtectedBackdrop ? 0.58 : (state.highContrast ? 0.46 : 0.32)
                ipadCrosshairContrastLayer.backgroundColor = NSColor(white: contrastWhite, alpha: contrastAlpha).cgColor
                ipadCrosshairRimLayer.strokeColor = NSColor(white: rimWhite, alpha: state.highContrast ? 0.78 : 0.52).cgColor
            } else if !ipadCrosshairContainerLayer.isHidden {
                ipadCrosshairContainerLayer.isHidden = true
            }

            // 6. Unified iPadOS Translucent Special Cursors
            let specialOpacity = state.opacity * state.specialCursorBlend
            if specialOpacity > 0.005 && state.specialCursorKind != .none {
                let morphScale = 0.84 + 0.16 * state.specialCursorBlend
                let totalSpecialScale = state.pointerSizeMultiplier * state.totalScale * morphScale

                if ipadSpecialContainerLayer.isHidden {
                    ipadSpecialContainerLayer.isHidden = false
                }
                if state.specialCursorKind != lastIPadSpecialKind {
                    let path = IPadSpecialCursorPaths.makePath(kind: state.specialCursorKind)
                    ipadSpecialMaskLayer.fillRule = IPadSpecialCursorPaths.usesEvenOddFill(for: state.specialCursorKind) ? .evenOdd : .nonZero
                    ipadSpecialMaskLayer.path = path
                    ipadSpecialRimLayer.path = path
                    ipadSpecialContainerLayer.anchorPoint = IPadSpecialCursorPaths.anchorPoint(for: state.specialCursorKind)
                    lastIPadSpecialKind = state.specialCursorKind
                }
                ipadSpecialContainerLayer.position = localCenter
                ipadSpecialContainerLayer.transform = CATransform3DMakeScale(totalSpecialScale, totalSpecialScale, 1.0)
                ipadSpecialContainerLayer.opacity = Float(specialOpacity)

                let materialAlpha = state.highContrast ? 1.0 : ApplePointerConstants.Material.materialAlphaDot
                ipadSpecialBackdropClipLayer.opacity = Float(materialAlpha)
                if let ipadSpecialBackdropLayer, state.colorMatrix != lastIPadSpecialMatrix {
                    ipadSpecialBackdropLayer.setValue(state.colorMatrix.asNSValue(), forKeyPath: "filters.colorMatrix.inputColorMatrix")
                    lastIPadSpecialMatrix = state.colorMatrix
                }

                let t = state.lumaMix
                let rimWhite: CGFloat = 0.14 + (0.96 - 0.14) * t
                ipadSpecialRimLayer.strokeColor = NSColor(white: rimWhite, alpha: state.highContrast ? 0.62 : 0.34).cgColor
            } else if !ipadSpecialContainerLayer.isHidden {
                ipadSpecialContainerLayer.isHidden = true
            }

            // 7. Authentic Apple UIPointerAccessory directional arrows around snapped sliders & steppers
            let accOpacity = state.opacity * state.accessoryBlend * shapeMaskOpacity
            if accOpacity > 0.005 && state.accessoryKind != .none {
                if accessoryContainerLayer.isHidden {
                    accessoryContainerLayer.isHidden = false
                }
                let sizeChanged = abs(state.size.width - lastAccessoryTargetSize.width) > 0.4
                    || abs(state.size.height - lastAccessoryTargetSize.height) > 0.4
                if state.accessoryKind != lastAccessoryKind || sizeChanged {
                    let built = IPadAccessoryPaths.makeAccessoriesPath(kind: state.accessoryKind, targetSize: state.size)
                    let accBounds = CGRect(origin: .zero, size: built.canvasSize)
                    accessoryContainerLayer.bounds = accBounds
                    accessoryBackdropClipLayer.frame = accBounds
                    accessoryBackdropLayer?.frame = accBounds
                    accessoryMaskLayer.frame = accBounds
                    accessoryMaskLayer.path = built.path
                    accessoryRimLayer.frame = accBounds
                    accessoryRimLayer.path = built.path
                    lastAccessoryKind = state.accessoryKind
                    lastAccessoryTargetSize = state.size
                }
                let accScale = state.totalScale * (0.86 + 0.14 * state.accessoryBlend)
                accessoryContainerLayer.position = localCenter
                accessoryContainerLayer.transform = CATransform3DMakeScale(accScale, accScale, 1.0)
                accessoryContainerLayer.opacity = Float(accOpacity)
                accessoryBackdropClipLayer.opacity = Float(state.highContrast ? 1.0 : ApplePointerConstants.Material.materialAlphaDot)
                if let accessoryBackdropLayer, state.colorMatrix != lastAccessoryMatrix {
                    accessoryBackdropLayer.setValue(state.colorMatrix.asNSValue(), forKeyPath: "filters.colorMatrix.inputColorMatrix")
                    lastAccessoryMatrix = state.colorMatrix
                }
                let t = state.lumaMix
                let rimWhite: CGFloat = 0.14 + (0.96 - 0.14) * t
                accessoryRimLayer.strokeColor = NSColor(white: rimWhite, alpha: state.highContrast ? 0.55 : 0.28).cgColor
            } else if !accessoryContainerLayer.isHidden {
                accessoryContainerLayer.isHidden = true
            }
        }

        private static func makeSmoothOrganicPath(radii: [CGFloat], center: CGPoint) -> CGPath {
            let n = radii.count
            guard n >= 3 else {
                return CGPath(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16), transform: nil)
            }
            var pts: [CGPoint] = []
            pts.reserveCapacity(n)
            for k in 0..<n {
                let angle = (CGFloat(k) / CGFloat(n)) * (.pi * 2.0)
                let r = radii[k]
                // Convert Quartz Y-down angle into AppKit Y-up layer coordinates
                pts.append(CGPoint(x: center.x + cos(angle) * r, y: center.y - sin(angle) * r))
            }
            let path = CGMutablePath()
            let lastMid = CGPoint(x: (pts[n - 1].x + pts[0].x) * 0.5, y: (pts[n - 1].y + pts[0].y) * 0.5)
            path.move(to: lastMid)
            for k in 0..<n {
                let next = pts[(k + 1) % n]
                let midPt = CGPoint(x: (pts[k].x + next.x) * 0.5, y: (pts[k].y + next.y) * 0.5)
                path.addQuadCurve(to: midPt, control: pts[k])
            }
            path.closeSubpath()
            return path
        }

        private func applyBlur(
            _ radius: CGFloat,
            to layer: CALayer,
            filter: NSObject?,
            activeFlag: inout Bool,
            lastRadius: inout CGFloat
        ) {
            if radius > 0.01, let gbFilter = filter {
                if !activeFlag {
                    gbFilter.setValue(radius, forKey: "inputRadius")
                    layer.filters = [gbFilter]
                    activeFlag = true
                    lastRadius = radius
                } else if abs(radius - lastRadius) > 0.01 {
                    layer.setValue(radius, forKeyPath: "filters.gaussianBlur.inputRadius")
                    lastRadius = radius
                }
            } else if activeFlag {
                layer.filters = nil
                activeFlag = false
                lastRadius = 0
            }
        }

    }

    private var overlays: [ScreenOverlay] = []
    private var displayLink: CADisplayLink?
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?
    private nonisolated(unsafe) var spaceObserver: NSObjectProtocol?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var isVisible = true
    private var isCaptureSuspended = false
    private var isElevatedAboveCaptureOverlays = false
    private var cachedPrimaryDisplayHeight: CGFloat = CGDisplayBounds(CGMainDisplayID()).height
    private let specularImage: CGImage?
    private var cursorAssets: SystemCursorAssetLibrary?

    var hasActiveOverlay: Bool {
        !overlays.isEmpty && displayLink != nil && isVisible
    }

    var isDisplayLinkPaused: Bool {
        displayLink?.isPaused ?? true
    }

    var onFrame: ((TimeInterval, TimeInterval) -> PointerRenderState?)?
    var onSmoothCaretFrame: ((TimeInterval, TimeInterval) -> SmoothCaretRenderState)?
    var onAfterFrame: ((TimeInterval) -> Void)?
    var onSpaceChanged: (() -> Void)?
    var onLumaChange: (@Sendable (Double) -> Void)?

    init() {
        self.specularImage = Self.makeSpecularCGImage()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
    }

    func start() {
        if cursorAssets == nil {
            cursorAssets = SystemCursorAssetLibrary()
        }
        rebuildScreens()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.rebuildScreens()
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
                    self?.bringOverlaysToFront()
                    self?.onSpaceChanged?()
                }
                for delay in [0.35, 0.75] as [TimeInterval] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.bringOverlaysToFront()
                    }
                }
            }
        }
    }

    func setElevatedAboveCaptureOverlays(_ elevated: Bool) {
        guard elevated != isElevatedAboveCaptureOverlays else { return }
        isElevatedAboveCaptureOverlays = elevated
        bringOverlaysToFront()
    }

    func bringOverlaysToFront() {
        guard isVisible && !isCaptureSuspended else { return }
        let targetKey: CGWindowLevelKey = isElevatedAboveCaptureOverlays
            ? .cursorWindow
            : .assistiveTechHighWindow
        let targetLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(targetKey)))
        for overlay in overlays {
            if overlay.panel.level != targetLevel {
                overlay.panel.level = targetLevel
            }
            overlay.panel.orderFrontRegardless()
        }
    }

    /// Temporarily orders overlay panels completely off-screen during active screenshot capture overlays
    /// (CleanShot X / macOS screencaptureui) so capture window-pickers and crosshairs never collide with them.
    func setCaptureSuspended(_ suspended: Bool) {
        guard suspended != isCaptureSuspended else { return }
        isCaptureSuspended = suspended
        if suspended {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for overlay in overlays {
                overlay.hide()
                overlay.panel.orderOut(nil)
            }
            CATransaction.commit()
        } else if isVisible {
            bringOverlaysToFront()
            wakeDisplayLink()
        }
    }

    func startDisplayLink() {
        guard displayLink == nil else { return }
        lastFrameTimestamp = CACurrentMediaTime()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let link = screen.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func setDisplayLinkPaused(_ paused: Bool) {
        guard let link = displayLink else { return }
        if link.isPaused != paused {
            if !paused {
                lastFrameTimestamp = CACurrentMediaTime()
            }
            link.isPaused = paused
        }
    }

    func wakeDisplayLink() {
        setDisplayLinkPaused(false)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        for overlay in overlays {
            overlay.panel.orderOut(nil)
            overlay.panel.close()
        }
        overlays.removeAll()
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for overlay in overlays {
                overlay.hide()
            }
            CATransaction.commit()
            setDisplayLinkPaused(true)
        } else {
            wakeDisplayLink()
        }
    }

    func setScreensLumaCallback(_ callback: @escaping @Sendable (Double) -> Void) {
        onLumaChange = callback
        for overlay in overlays {
            overlay.lumaBridge.setHandler(callback)
        }
    }

    func rebuildScreens() {
        displayLink?.invalidate()
        displayLink = nil
        cachedPrimaryDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        EventTapManager.updatePrimaryDisplayHeight(cachedPrimaryDisplayHeight)

        for overlay in overlays {
            overlay.panel.orderOut(nil)
            overlay.panel.close()
        }
        let assets = cursorAssets ?? SystemCursorAssetLibrary()
        cursorAssets = assets
        let currentCallback = onLumaChange
        overlays = NSScreen.screens.map { screen in
            ScreenOverlay(screen: screen, specularCGImage: specularImage, cursorAssets: assets) { luma in
                currentCallback?(luma)
            }
        }
        startDisplayLink()
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrameTimestamp > 0 ? max(1.0 / 240.0, min(0.05, now - lastFrameTimestamp)) : (1.0 / 120.0)
        lastFrameTimestamp = now
        let uptime = ProcessInfo.processInfo.systemUptime
        let primaryHeight = cachedPrimaryDisplayHeight

        guard isVisible, let state = onFrame?(dt, uptime) else {
            let caret = isVisible ? (onSmoothCaretFrame?(dt, uptime) ?? .hidden) : .hidden
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for overlay in overlays {
                overlay.hide()
                overlay.renderSmoothCaret(caret, primaryHeight: primaryHeight, visible: isVisible)
            }
            CATransaction.commit()
            onAfterFrame?(uptime)
            return
        }

        let caret = onSmoothCaretFrame?(dt, uptime) ?? .hidden
        let appKitCenter = CGPoint(x: state.center.x, y: primaryHeight - state.center.y)

        let matchedIndex = overlays.firstIndex { $0.screen.frame.contains(appKitCenter) }
            ?? overlays.indices.min { a, b in
                distanceSquared(from: appKitCenter, to: overlays[a].screen.frame) < distanceSquared(from: appKitCenter, to: overlays[b].screen.frame)
            }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (idx, overlay) in overlays.enumerated() {
            if idx == matchedIndex {
                let frame = overlay.screen.frame
                let local = CGPoint(x: appKitCenter.x - frame.origin.x, y: appKitCenter.y - frame.origin.y)
                overlay.render(state: state, localCenter: local, visible: true)
            } else {
                overlay.hide()
            }
            overlay.renderSmoothCaret(caret, primaryHeight: primaryHeight, visible: true)
        }
        CATransaction.commit()
        onAfterFrame?(uptime)
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let cx = max(rect.minX, min(point.x, rect.maxX))
        let cy = max(rect.minY, min(point.y, rect.maxY))
        let dx = point.x - cx
        let dy = point.y - cy
        return dx * dx + dy * dy
    }

    private static func makeSpecularCGImage() -> CGImage? {
        let size = 300
        let rgbaSpace = CGColorSpaceCreateDeviceRGB()
        guard let rgbaCtx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: rgbaSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let stops = ApplePointerConstants.Specular.radialStops
        let locations = stops.map { $0.location }
        let rgbaColors = stops.map {
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: $0.alpha)
        } as CFArray
        guard let rgbaGradient = CGGradient(colorsSpace: rgbaSpace, colors: rgbaColors, locations: locations) else {
            return nil
        }
        let center = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.5)
        rgbaCtx.drawRadialGradient(
            rgbaGradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: CGFloat(size) * 0.5,
            options: [.drawsBeforeStartLocation]
        )
        return rgbaCtx.makeImage()
    }
}
