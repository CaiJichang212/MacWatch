import AppKit
import MacWatchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lifecycleCoordinator = AppLifecycleCoordinator()
    private var menuBarController: MenuBarController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.record(.launched)
        menuBarController = MenuBarController(
            openMainWindow: { [weak self] in self?.openMainWindow() },
            openSettings: { [weak self] in self?.openSettings() },
            quitApplication: { [weak self] in self?.quitApplication() }
        )
        registerObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func registerObservers() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.lifecycleCoordinator.record(.willTerminate)
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.lifecycleCoordinator.record(.willSleep)
            }
        )
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.lifecycleCoordinator.record(.didWake)
            }
        )
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func quitApplication() {
        NSApp.terminate(nil)
    }
}
