import Foundation
import MacWatchCore
import XCTest
@testable import MacWatchApp

final class MacWatchRuntimeSettingsTests: XCTestCase {
    @MainActor
    func testRuntimeLoadsSettingsAndPublishesUpdates() {
        let store = InMemorySettingsStore(
            initialSettings: AppSettings(
                launchMainWindowOnStart: false,
                temperatureUnit: .fahrenheit,
                refreshInterval: .tenSeconds,
                defaultTrendRange: .sixHours,
                menuBarDisplayMetric: .battery
            )
        )
        let runtime = MacWatchRuntime(
            sessionHistoryRepository: InMemorySessionHistoryRepository(),
            settingsStore: store,
            probeProvider: EmptyRuntimeProbeProvider()
        )

        XCTAssertEqual(runtime.settings.temperatureUnit, .fahrenheit)
        XCTAssertEqual(runtime.settings.refreshInterval, .tenSeconds)
        XCTAssertEqual(runtime.settings.defaultTrendRange, .sixHours)
        XCTAssertEqual(runtime.settings.menuBarDisplayMetric, .battery)

        runtime.updateSettings { settings in
            settings.temperatureUnit = .celsius
            settings.menuBarDisplayMetric = .cpu
        }

        XCTAssertEqual(runtime.settings.temperatureUnit, .celsius)
        XCTAssertEqual(runtime.settings.menuBarDisplayMetric, .cpu)
        XCTAssertEqual(store.savedSettings?.temperatureUnit, .celsius)
        XCTAssertEqual(store.savedSettings?.menuBarDisplayMetric, .cpu)
    }

    @MainActor
    func testCompletingFirstRunGuidePersistsSelectedBaselineSettings() {
        let suiteName = "MacWatchRuntimeSettingsTests.firstRun.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = InMemorySettingsStore(initialSettings: .default)
        let guideStore = FirstRunGuideStateStore(defaults: defaults)
        let runtime = MacWatchRuntime(
            sessionHistoryRepository: InMemorySessionHistoryRepository(),
            settingsStore: store,
            probeProvider: EmptyRuntimeProbeProvider(),
            forceShowFirstRunGuide: true,
            firstRunGuideStateStore: guideStore
        )

        runtime.completeFirstRunGuide(
            configuration: FirstRunGuideConfiguration(
                temperatureUnit: .fahrenheit,
                menuBarDisplayMetric: .battery,
                refreshInterval: .tenSeconds
            )
        )

        XCTAssertFalse(runtime.shouldShowFirstRunGuide)
        XCTAssertFalse(guideStore.shouldShowFirstRunGuide())
        XCTAssertEqual(runtime.settings.temperatureUnit, .fahrenheit)
        XCTAssertEqual(runtime.settings.menuBarDisplayMetric, .battery)
        XCTAssertEqual(runtime.settings.refreshInterval, .tenSeconds)
        XCTAssertEqual(store.savedSettings?.temperatureUnit, .fahrenheit)
        XCTAssertEqual(store.savedSettings?.menuBarDisplayMetric, .battery)
        XCTAssertEqual(store.savedSettings?.refreshInterval, .tenSeconds)
    }

    @MainActor
    func testEffectiveRealtimeIntervalClampsSlowDomains() {
        let runtime = MacWatchRuntime(
            sessionHistoryRepository: InMemorySessionHistoryRepository(),
            settingsStore: InMemorySettingsStore(initialSettings: .default),
            probeProvider: EmptyRuntimeProbeProvider()
        )

        XCTAssertEqual(runtime.effectiveRealtimeInterval(for: .cpu), 5)
        XCTAssertEqual(runtime.effectiveRealtimeInterval(for: .memory), 30)

        runtime.applyRefreshInterval(.tenSeconds)

        XCTAssertEqual(runtime.effectiveRealtimeInterval(for: .cpu), 10)
        XCTAssertEqual(runtime.effectiveRealtimeInterval(for: .gpu), 10)
        XCTAssertEqual(runtime.effectiveRealtimeInterval(for: .memory), 30)
        XCTAssertEqual(runtime.effectiveRealtimeInterval(for: .battery), 30)

        runtime.applyRefreshInterval(.thirtySeconds)

        XCTAssertEqual(runtime.effectiveRealtimeInterval(for: .cpu), 30)
        XCTAssertEqual(runtime.effectiveRealtimeInterval(for: .memory), 30)
    }

    @MainActor
    func testApplyRefreshIntervalKeepsOnlyLatestSchedulerRunning() async throws {
        let repository = InMemorySessionHistoryRepository()
        let sessionID = UUID()
        try repository.beginSession(
            MonitoringSession(id: sessionID, startedAt: Date(timeIntervalSince1970: 10)),
            clearingPreviousHistory: true
        )

        let builder = RecordingSchedulerBuilder()
        let runtime = MacWatchRuntime(
            sessionHistoryRepository: repository,
            settingsStore: InMemorySettingsStore(initialSettings: .default),
            probeProvider: EmptyRuntimeProbeProvider(),
            schedulerBuilder: builder
        )

        runtime.start()
        runtime.applyRefreshInterval(.tenSeconds)
        runtime.applyRefreshInterval(.thirtySeconds)
        runtime.applyRefreshInterval(.fiveSeconds)

        try await Task.sleep(nanoseconds: 300_000_000)

        let schedulers = builder.createdSchedulers()
        let runningSchedulerIDs = await builder.runningSchedulerIDs()
        let lastSchedulerID = schedulers.last?.id

        XCTAssertGreaterThanOrEqual(schedulers.count, 2)
        XCTAssertEqual(runningSchedulerIDs.count, 1)
        XCTAssertEqual(runningSchedulerIDs.first, lastSchedulerID)
    }
}

private final class InMemorySettingsStore: SettingsStore {
    private let initialSettings: AppSettings
    private(set) var savedSettings: AppSettings?

    init(initialSettings: AppSettings) {
        self.initialSettings = initialSettings
    }

    func load() -> AppSettings {
        savedSettings ?? initialSettings
    }

    func save(_ settings: AppSettings) {
        savedSettings = settings
    }
}

private struct EmptyRuntimeProbeProvider: MacWatchTemperatureProbeProviding {
    func makeFastProbes() -> [any TemperatureProbe] { [] }
    func makeSlowProbes() -> [any TemperatureProbe] { [] }
}

private final class RecordingSchedulerBuilder: TemperatureSchedulerBuilding {
    private let lock = NSLock()
    private var schedulers: [RecordingScheduler] = []

    func makeScheduler(
        probes _: [any TemperatureProbe],
        capabilityService _: TemperatureCapabilityService,
        bus _: SampleBus,
        clock _: @escaping @Sendable () -> Date,
        minimumTickInterval _: TimeInterval,
        policyForDomain _: @escaping (TemperatureDomain) -> TemperatureSamplingPolicy
    ) -> any TemperatureScheduling {
        let scheduler = RecordingScheduler()
        lock.withLock {
            schedulers.append(scheduler)
        }
        return scheduler
    }

    func createdSchedulers() -> [RecordingScheduler] {
        lock.withLock { schedulers }
    }

    func runningSchedulerIDs() async -> [UUID] {
        var ids: [UUID] = []
        for scheduler in createdSchedulers() {
            if await scheduler.isRunning {
                ids.append(scheduler.id)
            }
        }
        return ids
    }
}

private actor RecordingScheduler: TemperatureScheduling {
    let id = UUID()
    private(set) var isRunning = false

    func start(sessionID _: UUID) async {
        try? await Task.sleep(nanoseconds: 60_000_000)
        isRunning = true
    }

    func pause(reason _: SchedulerPauseReason, at _: Date) async {}

    func resume(reason _: SchedulerResumeReason, at _: Date) async {}

    func stop(at _: Date) async {
        try? await Task.sleep(nanoseconds: 60_000_000)
        isRunning = false
    }
}
