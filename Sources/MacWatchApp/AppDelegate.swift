import AppKit
import MacWatchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionLifecycleService: SessionLifecycleService
    private let shouldSetupMenuBarOnLaunch: Bool
    private let shouldRegisterObserversOnLaunch: Bool
    private let windowCommandCenter: WindowCommandCenter
    private var menuBarController: MenuBarController?
    private var observers: [NSObjectProtocol] = []
    private lazy var lifecycleCoordinator = AppLifecycleCoordinator { [weak self] event in
        self?.handleLifecycleEvent(event)
    }

    init(
        sessionHistoryRepository: SessionHistoryRepository = InMemorySessionHistoryRepository(),
        shouldSetupMenuBarOnLaunch: Bool = true,
        shouldRegisterObserversOnLaunch: Bool = true,
        windowCommandCenter: WindowCommandCenter = .shared
    ) {
        self.sessionLifecycleService = SessionLifecycleService(repository: sessionHistoryRepository)
        self.shouldSetupMenuBarOnLaunch = shouldSetupMenuBarOnLaunch
        self.shouldRegisterObserversOnLaunch = shouldRegisterObserversOnLaunch
        self.windowCommandCenter = windowCommandCenter
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.record(.launched)
        if shouldSetupMenuBarOnLaunch {
            menuBarController = MenuBarController(
                openMainWindow: { [weak self] in self?.openMainWindow() },
                openSettings: { [weak self] in self?.openSettings() },
                quitApplication: { [weak self] in self?.quitApplication() }
            )
        }
        if shouldRegisterObserversOnLaunch {
            registerObservers()
        }
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

    private func handleLifecycleEvent(_ event: AppLifecycleEvent) {
        do {
            try sessionLifecycleService.handle(event)
        } catch {
            assertionFailure("Failed to handle lifecycle event: \(error)")
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        windowCommandCenter.openMainWindow()
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
