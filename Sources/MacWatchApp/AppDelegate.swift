import AppKit
import MacWatchCore
import StatsAdapter

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionLifecycleService: SessionLifecycleService
    private let platformDetector: ApplePlatformDetector
    private let shouldSetupMenuBarOnLaunch: Bool
    private let shouldRegisterObserversOnLaunch: Bool
    private let shouldStartRuntimeOnLaunch: Bool
    private let shouldOpenMainWindowOnLaunch: Bool
    private let windowCommandCenter: WindowCommandCenter
    private var menuBarController: MenuBarController?
    private var observers: [NSObjectProtocol] = []
    let runtime: MacWatchRuntime
    private lazy var lifecycleCoordinator = AppLifecycleCoordinator { [weak self] event in
        self?.handleLifecycleEvent(event)
    }

    override init() {
        let detector = ApplePlatformDetector()
        let parsedScenario = (try? MacWatchCLIArguments(arguments: CommandLine.arguments))?.acceptanceScenario
        let (initialSettings, forceShowFirstRunGuide) = Self.makeAcceptanceAdjustedSettings(scenario: parsedScenario)
        self.platformDetector = detector
        self.sessionLifecycleService = SessionLifecycleService(
            repository: MacWatchSharedDependencies.sessionHistoryRepository,
            appVersion: Self.currentAppVersion,
            model: detector.currentModelIdentifier(),
            chip: detector.currentChipName(),
            osVersion: Self.currentOperatingSystemVersion
        )
        self.shouldSetupMenuBarOnLaunch = true
        self.shouldRegisterObserversOnLaunch = true
        self.shouldStartRuntimeOnLaunch = true
        self.shouldOpenMainWindowOnLaunch = true
        self.windowCommandCenter = .shared
        self.runtime = MacWatchRuntime(
            sessionHistoryRepository: MacWatchSharedDependencies.sessionHistoryRepository,
            settingsStore: MacWatchSharedDependencies.settingsStore,
            initialSettings: initialSettings,
            forceShowFirstRunGuide: forceShowFirstRunGuide
        )
        AcceptanceCoordinator.shared.configure(firstRunGuideContext: runtime.firstRunGuideContext)
        super.init()
    }

    init(
        sessionHistoryRepository: SessionHistoryRepository = MacWatchSharedDependencies.sessionHistoryRepository,
        shouldSetupMenuBarOnLaunch: Bool = true,
        shouldRegisterObserversOnLaunch: Bool = true,
        shouldStartRuntimeOnLaunch: Bool = true,
        shouldOpenMainWindowOnLaunch: Bool = true,
        windowCommandCenter: WindowCommandCenter = .shared,
        platformDetector: ApplePlatformDetector = ApplePlatformDetector()
    ) {
        let parsedScenario = (try? MacWatchCLIArguments(arguments: CommandLine.arguments))?.acceptanceScenario
        let (initialSettings, forceShowFirstRunGuide) = Self.makeAcceptanceAdjustedSettings(scenario: parsedScenario)
        self.platformDetector = platformDetector
        self.sessionLifecycleService = SessionLifecycleService(
            repository: sessionHistoryRepository,
            appVersion: Self.currentAppVersion,
            model: platformDetector.currentModelIdentifier(),
            chip: platformDetector.currentChipName(),
            osVersion: Self.currentOperatingSystemVersion
        )
        self.shouldSetupMenuBarOnLaunch = shouldSetupMenuBarOnLaunch
        self.shouldRegisterObserversOnLaunch = shouldRegisterObserversOnLaunch
        self.shouldStartRuntimeOnLaunch = shouldStartRuntimeOnLaunch
        self.shouldOpenMainWindowOnLaunch = shouldOpenMainWindowOnLaunch
        self.windowCommandCenter = windowCommandCenter
        self.runtime = MacWatchRuntime(
            sessionHistoryRepository: sessionHistoryRepository,
            initialSettings: initialSettings,
            forceShowFirstRunGuide: forceShowFirstRunGuide
        )
        AcceptanceCoordinator.shared.configure(firstRunGuideContext: runtime.firstRunGuideContext)
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
        if shouldStartRuntimeOnLaunch && AcceptanceCoordinator.shared.shouldDeferRuntimeStartForActiveScenario == false {
            runtime.start()
        }
        if shouldOpenMainWindowOnLaunch && (runtime.shouldShowFirstRunGuide || runtime.settings.launchMainWindowOnStart) {
            openDashboard()
        }
        AcceptanceCoordinator.shared.applicationDidFinishLaunching(appDelegate: self)
    }

    private static var currentAppVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private static var currentOperatingSystemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private static func makeAcceptanceAdjustedSettings(
        scenario: AcceptanceScenario?
    ) -> (AppSettings, Bool?) {
        let settingsStore = MacWatchSharedDependencies.settingsStore
        var initialSettings = settingsStore.load()
        var forceShowFirstRunGuide: Bool?

        switch scenario {
        case .firstRunGuide:
            initialSettings.launchMainWindowOnStart = true
            forceShowFirstRunGuide = true
        case .launchMainWindowOnStartEnabled:
            initialSettings.launchMainWindowOnStart = true
            forceShowFirstRunGuide = false
        case .launchMainWindowOnStartDisabled:
            initialSettings.launchMainWindowOnStart = false
            forceShowFirstRunGuide = false
        case .dashboardOpen, .popupOpen:
            forceShowFirstRunGuide = false
        default:
            break
        }

        return (initialSettings, forceShowFirstRunGuide)
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

    func showAcceptancePopup() {
        menuBarController?.showPopoverForAcceptance()
    }
}
