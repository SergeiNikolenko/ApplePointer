import AppKit
import ApplePointerCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case pointer = "Pointer"
    case behavior = "Behavior"
    case apps = "Apps"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .pointer: return "cursorarrow.click.2"
        case .behavior: return "sparkles"
        case .apps: return "app.badge.checkmark"
        }
    }
}

struct PointerStyleCard: View {
    let style: PointerShapeStyle
    let liquidGlass: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.08 : 0.04))
                        .frame(height: 48)

                    if style == .ipadDot {
                        ZStack {
                            if liquidGlass {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [Color.primary.opacity(0.28), Color.primary.opacity(0.12)],
                                            center: .topLeading,
                                            startRadius: 2,
                                            endRadius: 16
                                        )
                                    )
                                    .frame(width: 22, height: 22)
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.85), Color.primary.opacity(0.18), Color.white.opacity(0.45)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                                    .frame(width: 22, height: 22)
                            } else {
                                Circle()
                                    .fill(Color.primary.opacity(0.24))
                                    .frame(width: 22, height: 22)
                            }
                        }
                    } else {
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }

                Text(style == .appleMouse ? "Arrow" : "Dot")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 1.0
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsRootView: View {
    @ObservedObject var controller: PointerController
    @State private var selectedSection: SettingsSection = .pointer

    private var isMouseStyle: Bool {
        controller.configuration.pointerShapeStyle == .appleMouse
    }

    private var activeSizeBinding: Binding<CGFloat> {
        isMouseStyle ? $controller.configuration.mouseSizeMultiplier : $controller.configuration.dotSizeMultiplier
    }

    private var activeSizeRange: ClosedRange<CGFloat> {
        isMouseStyle ? PointerConfiguration.mouseSizeRange : PointerConfiguration.dotSizeRange
    }

    private var activeSizeLabel: String {
        if isMouseStyle {
            return String(format: "%.2f×", controller.configuration.activeSizeMultiplier)
        }
        let ptSize = Int(round(ApplePointerConstants.Geometry.systemPointerSize * controller.configuration.activeSizeMultiplier))
        return "\(ptSize) pt"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            Group {
                switch selectedSection {
                case .pointer:
                    pointerForm
                case .behavior:
                    behaviorForm
                case .apps:
                    appsForm
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 536)
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("ApplePointer")
                        .font(.system(size: 15, weight: .semibold))
                    Text(controller.configuration.enabled ? "Active" : "Paused")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(controller.configuration.enabled ? Color.green : Color.secondary)
                }
            }

            Spacer()

            Picker("", selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 244)

            Toggle("", isOn: $controller.configuration.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Toggle ApplePointer (⌃⌥⌘P)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var pointerForm: some View {
        Form {
            if !controller.accessibilityGranted || controller.pausedForPermissionSetup {
                Section {
                    HStack {
                        Label("Accessibility Permission", systemImage: "hand.raised")
                        Spacer()
                        if !controller.accessibilityGranted {
                            Button("Grant Access") {
                                controller.requestPermissions()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if controller.pausedForPermissionSetup {
                            Button("Resume") {
                                controller.resumeFromPermissionPause()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Section("Style") {
                HStack(spacing: 10) {
                    PointerStyleCard(
                        style: .ipadDot,
                        liquidGlass: controller.configuration.dotLiquidGlassEnabled,
                        isSelected: controller.configuration.pointerShapeStyle == .ipadDot
                    ) {
                        controller.configuration.pointerShapeStyle = .ipadDot
                    }
                    PointerStyleCard(
                        style: .appleMouse,
                        liquidGlass: controller.configuration.liquidGlassEnabled,
                        isSelected: controller.configuration.pointerShapeStyle == .appleMouse
                    ) {
                        controller.configuration.pointerShapeStyle = .appleMouse
                    }
                }
                .padding(.vertical, 4)

                LabeledContent(isMouseStyle ? "Arrow Size" : "Dot Size") {
                    HStack(spacing: 10) {
                        Slider(value: activeSizeBinding, in: activeSizeRange, step: 0.05)
                            .frame(width: 180)
                        Text(activeSizeLabel)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }

            Section("Appearance") {
                Toggle("Liquid Glass", isOn: $controller.configuration.liquidGlassEnabled)
                if !isMouseStyle {
                    Toggle("Glass Dot", isOn: $controller.configuration.dotLiquidGlassEnabled)
                }
                Toggle(
                    (controller.configuration.liquidGlassEnabled || (!isMouseStyle && controller.configuration.dotLiquidGlassEnabled)) ? "Glass Sheen & Rim" : "Highlight Specular",
                    isOn: $controller.configuration.specularEnabled
                )
                LabeledContent("Highlight Contrast") {
                    HStack(spacing: 10) {
                        Slider(
                            value: $controller.configuration.highlightContrast,
                            in: PointerConfiguration.highlightContrastRange,
                            step: 0.05
                        )
                        .frame(width: 180)
                        Text("\(Int(round(controller.configuration.highlightContrast * 100.0)))%")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                if !isMouseStyle {
                    LabeledContent("Dot Opacity") {
                        HStack(spacing: 10) {
                            Slider(
                                value: $controller.configuration.dotIntensity,
                                in: PointerConfiguration.dotIntensityRange,
                                step: 0.05
                            )
                            .frame(width: 180)
                            Text("\(Int(round(controller.configuration.dotIntensity * 100.0)))%")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    Toggle("Center Dot", isOn: $controller.configuration.showCenterDot)
                }
                Toggle("Increase Contrast", isOn: $controller.configuration.highContrast)
            }

            Section("Visibility") {
                Toggle("Shake to Find", isOn: $controller.configuration.shakeToFindEnabled)
                Toggle("Scale with Accessibility Zoom", isOn: $controller.configuration.scaleWithZoomEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var behaviorForm: some View {
        Form {
            Section("Magnetism") {
                Toggle("Magnetic Snap", isOn: $controller.configuration.magnetismEnabled)
                if controller.configuration.magnetismEnabled {
                    Toggle("Fast-Flight Inertia", isOn: $controller.configuration.inertiaEnabled)
                        .help("Skip snapping over intermediate buttons when moving quickly across toolbars")
                }
            }

            Section("Typing") {
                Toggle("Smooth Typing Caret", isOn: $controller.configuration.smoothTypingCaretEnabled)
                    .help("VS Code-style smooth gliding and breathing text cursor while typing")
                Toggle("Hide Pointer While Typing", isOn: $controller.configuration.hideWhileTyping)
            }

            Section("Idle & Cursors") {
                Toggle("Auto-Hide When Idle", isOn: $controller.configuration.autohideEnabled)
                if controller.configuration.autohideEnabled {
                    LabeledContent("Idle Delay") {
                        HStack(spacing: 10) {
                            Slider(
                                value: $controller.configuration.autohideDuration,
                                in: PointerConfiguration.autohideDurationRange,
                                step: 0.5
                            )
                            .frame(width: 180)
                            Text(String(format: "%.1fs", controller.configuration.autohideDuration))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                Toggle("System Resize Cursors", isOn: $controller.configuration.showNativeResizeCursors)
                Toggle("Preserve App Tool Cursors", isOn: $controller.configuration.passThroughUnknownCustomCursors)
                    .help("Temporarily yield to bespoke creative tool cursors in apps like Photoshop or Blender")
            }
        }
        .formStyle(.grouped)
    }

    private var appsForm: some View {
        Form {
            Section("System") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { controller.launchAtLoginEnabled },
                        set: { controller.setLaunchAtLogin($0) }
                    )
                )
            }

            Section {
                HStack(spacing: 8) {
                    if let activeID = controller.frontmostAppBundleID {
                        let isExcluded = controller.configuration.excludedBundleIDs.contains(activeID)
                        Button(isExcluded ? "Include \(controller.frontmostAppName ?? activeID)" : "Exclude \(controller.frontmostAppName ?? activeID)") {
                            controller.toggleExcludedApp(bundleID: activeID)
                        }
                    }
                    Spacer()
                    Button {
                        controller.addExcludedAppViaPanel()
                    } label: {
                        Label("Add App…", systemImage: "plus")
                    }
                }

                ForEach(controller.resolvedExcludedApps()) { app in
                    HStack(spacing: 10) {
                        if let url = app.appURL {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                        }
                        Text(app.displayName)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            controller.toggleExcludedApp(bundleID: app.bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(app.displayName)")
                    }
                }
            } header: {
                HStack {
                    Text("Excluded Apps")
                    Spacer()
                    Text("\(controller.configuration.excludedBundleIDs.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let pointerController: PointerController
    private var window: NSWindow?

    init(pointerController: PointerController) {
        self.pointerController = pointerController
        super.init()
    }

    func showSettings() {
        if let existing = window {
            pointerController.suspendAXForOwnWindow()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            pointerController.syncOwnWindowRects()
            return
        }

        let host = NSHostingController(rootView: SettingsRootView(controller: pointerController))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 536),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ApplePointer"
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false
        win.center()
        win.contentViewController = host
        win.delegate = self
        self.window = win

        pointerController.suspendAXForOwnWindow()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pointerController.syncOwnWindowRects()
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.pointerController.syncOwnWindowRects()
        }
    }

    func windowDidMove(_ notification: Notification) {
        pointerController.syncOwnWindowRects()
    }
}
