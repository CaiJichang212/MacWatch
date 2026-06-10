import AppKit
import MacWatchCore
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let runtime: MacWatchRuntime
    private let popover = NSPopover()

    init(
        runtime: MacWatchRuntime,
        openDashboard: @escaping () -> Void,
        openCompatibility: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quitApplication: @escaping () -> Void
    ) {
        self.runtime = runtime
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let popupView = MenuBarPopupView(
            openDashboard: { [weak self] in
                self?.closePopover()
                openDashboard()
            },
            openCompatibility: { [weak self] in
                self?.closePopover()
                openCompatibility()
            },
            openSettings: { [weak self] in
                self?.closePopover()
                openSettings()
            },
            quitApplication: { [weak self] in
                self?.closePopover()
                quitApplication()
            }
        )
        .environmentObject(runtime)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = NSHostingController(rootView: popupView)

        configureStatusItem()
    }

    func update(liveState: LiveTemperatureState?, settings: AppSettings) {
        let title = MenuBarTitleFormatter.title(liveState: liveState, settings: settings)
        apply(title: title)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    func showPopoverForAcceptance() {
        guard let button = statusItem.button else {
            return
        }
        showPopover(relativeTo: button)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        apply(title: MenuBarTitleFormatter.title(liveState: runtime.liveState, settings: runtime.settings))
    }

    private func apply(title: TemperatureDisplayText) {
        guard let button = statusItem.button else {
            return
        }

        button.attributedTitle = NSAttributedString(
            string: title.fullText,
            attributes: [
                .foregroundColor: title.isStale ? NSColor.secondaryLabelColor : NSColor.labelColor
            ]
        )
        button.alphaValue = title.isStale ? 0.72 : 1.0
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
