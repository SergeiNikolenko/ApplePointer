import AppKit
import ApplePointerCore
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var controller: PointerController
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("ApplePointer")
                        .font(.system(size: 14, weight: .semibold))
                    Text(controller.configuration.enabled ? "Active" : "Paused")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(controller.configuration.enabled ? Color.green : Color.secondary)
                }
                Spacer()
                Toggle("", isOn: $controller.configuration.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Toggle pointer (⌃⌥⌘P)")
            }

            if !controller.accessibilityGranted || controller.pausedForPermissionSetup {
                HStack(spacing: 8) {
                    if !controller.accessibilityGranted {
                        Button("Grant Accessibility") {
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

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(isMouseStyle ? "Arrow Size" : "Dot Size")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(activeSizeLabel)
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: activeSizeBinding, in: activeSizeRange, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Highlight Contrast")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(round(controller.configuration.highlightContrast * 100.0)))%")
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $controller.configuration.highlightContrast,
                    in: PointerConfiguration.highlightContrastRange,
                    step: 0.05
                )
            }

            Divider()

            VStack(spacing: 10) {
                quickToggleRow(
                    title: "Liquid Glass",
                    symbol: "sparkles",
                    isOn: $controller.configuration.liquidGlassEnabled
                )
                if !isMouseStyle {
                    quickToggleRow(
                        title: "Glass Dot",
                        symbol: "circle.lefthalf.filled",
                        isOn: $controller.configuration.dotLiquidGlassEnabled
                    )
                }
                quickToggleRow(
                    title: "Magnetic Snap",
                    symbol: "scope",
                    isOn: $controller.configuration.magnetismEnabled
                )
                quickToggleRow(
                    title: "Hide While Typing",
                    symbol: "keyboard",
                    isOn: $controller.configuration.hideWhileTyping
                )
            }

            Divider()

            HStack {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button("Quit", action: onQuit)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 304)
    }

    private func quickToggleRow(title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let pointerController: PointerController
    private let settingsWindowController: SettingsWindowController

    init(pointerController: PointerController, settingsWindowController: SettingsWindowController) {
        self.pointerController = pointerController
        self.settingsWindowController = settingsWindowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "ApplePointer")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                controller: pointerController,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: { [weak self] in
                    self?.quitApp()
                }
            )
        )
    }

    private func openSettings() {
        if popover.isShown {
            popover.performClose(nil)
        }
        settingsWindowController.showSettings()
    }

    private func quitApp() {
        if popover.isShown {
            popover.performClose(nil)
        }
        pointerController.shutdown()
        NSApp.terminate(nil)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            pointerController.syncOwnWindowRects()
        } else {
            pointerController.suspendAXForOwnWindow()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            pointerController.syncOwnWindowRects()
        }
    }
}
