import AppKit
import MacWatchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionLifecycleService: SessionLifecycleService
    private let shouldSetupMenuBarOnLaunch: Bool
    private let shouldRegisterObserversOnLaunch: Bool
    private let shouldStartRuntimeOnLaunch: Bool
    private let windowCommandCenter: WindowCommandCenter
    private var menuBarController: MenuBarController?
    private var observers: [NSObjectProtocol] = []
    let runtime: MacWatchRuntime
    private lazy var lifecycleCoordinator = AppLifecycleCoordinator { [weak self] event in
        self?.handleLifecycleEvent(event)
    }

    override init() {
        self.sessionLifecycleService = SessionLifecycleService(
            repository: MacWatchSharedDependencies.sessionHistoryRepository
        )
        self.shouldSetupMenuBarOnLaunch = true
        self.shouldRegisterObserversOnLaunch = true
        self.shouldStartRuntimeOnLaunch = true
        self.windowCommandCenter = .shared
        self.runtime = MacWatchRuntime(
            sessionHistoryRepository: MacWatchSharedDependencies.sessionHistoryRepository,
            settingsStore: MacWatchSharedDependencies.settingsStore
        )
        super.init()
    }

    init(
        sessionHistoryRepository: SessionHistoryRepository = MacWatchSharedDependencies.sessionHistoryRepository,
        shouldSetupMenuBarOnLaunch: Bool = true,
        shouldRegisterObserversOnLaunch: Bool = true,
        shouldStartRuntimeOnLaunch: Bool = true,
        windowCommandCenter: WindowCommandCenter = .shared
    ) {
        self.sessionLifecycleService = SessionLifecycleService(repository: sessionHistoryRepository)
        self.shouldSetupMenuBarOnLaunch = shouldSetupMenuBarOnLaunch
        self.shouldRegisterObserversOnLaunch = shouldRegisterObserversOnLaunch
        self.shouldStartRuntimeOnLaunch = shouldStartRuntimeOnLaunch
        self.windowCommandCenter = windowCommandCenter
        self.runtime = MacWatchRuntime(sessionHistoryRepository: sessionHistoryRepository)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.record(.launched)
        if shouldSetupMenuBarOnLaunch {
            menuBarController = MenuBarController(
                runtime: runtime,
                openDashboard: { [weak self] in self?.openDashboard() },
                openCompatibility: { [weak self] in self?.openCompatibility() },
                openSettings: { [weak self] in self?.openSettings() },
                quitApplication: { [weak self] in self?.quitApplication() }
            )
            runtime.stateDidChange = { [weak self] state in
                guard let self else {
                    return
                }
                self.menuBarController?.update(liveState: state, settings: self.runtime.settings)
            }
            runtime.settingsDidChange = { [weak self] settings in
                guard let self else {
                    return
                }
                self.menuBarController?.update(liveState: self.runtime.liveState, settings: settings)
            }
            menuBarController?.update(liveState: runtime.liveState, settings: runtime.settings)
        }
        if shouldRegisterObserversOnLaunch {
            registerObservers()
        }
        if shouldStartRuntimeOnLaunch {
            runtime.start()
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
                Task { @MainActor in
                    self?.lifecycleCoordinator.record(.willTerminate)
                }
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.lifecycleCoordinator.record(.willSleep)
                }
            }
        )
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.lifecycleCoordinator.record(.didWake)
                }
            }
        )
    }

    private func handleLifecycleEvent(_ event: AppLifecycleEvent) {
        do {
            try sessionLifecycleService.handle(event)
        } catch {
            assertionFailure("Failed to handle lifecycle event: \(error)")
        }
        runtime.handleLifecycleEvent(event)
    }

    private func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        windowCommandCenter.openMainWindow(route: .dashboard)
    }

    private func openCompatibility() {
        NSApp.activate(ignoringOtherApps: true)
        windowCommandCenter.openMainWindow(route: .compatibility)
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
