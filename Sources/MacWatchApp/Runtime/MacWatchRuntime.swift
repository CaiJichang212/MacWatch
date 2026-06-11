import Foundation
import MacWatchCore
import StatsAdapter

enum MacWatchSharedDependencies {
    static let sessionHistoryRepository: SessionHistoryRepository = makeSessionHistoryRepository()
    static let settingsStore: SettingsStore = UserDefaultsSettingsStore()

    private static func makeSessionHistoryRepository() -> SessionHistoryRepository {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let databaseURL = appSupport
                .appending(path: "MacWatch", directoryHint: .isDirectory)
                .appending(path: "session-history")
                .appendingPathExtension("sqlite")
            let store = SQLiteSessionHistoryStore(databaseURL: databaseURL)
            try store.initialize()
            return SQLiteSessionHistoryRepository(store: store)
        } catch {
            assertionFailure("Falling back to in-memory history repository: \(error)")
            return InMemorySessionHistoryRepository()
        }
    }
}

protocol MacWatchTemperatureProbeProviding {
    func makeFastProbes() -> [any TemperatureProbe]
    func makeSlowProbes() -> [any TemperatureProbe]
    func makeSystemProbes() -> [any TemperatureProbe]
    func makeSensorProbes() -> [any TemperatureProbe]
    func makeProbes() -> [any TemperatureProbe]
    func invalidateTemperatureSnapshots()
}

extension MacWatchTemperatureProbeProviding {
    func makeSystemProbes() -> [any TemperatureProbe] {
        []
    }

    func makeSensorProbes() -> [any TemperatureProbe] {
        []
    }

    func makeProbes() -> [any TemperatureProbe] {
        makeFastProbes() + makeSlowProbes() + makeSystemProbes() + makeSensorProbes()
    }

    func invalidateTemperatureSnapshots() {}
}

struct StatsAdapterTemperatureProbeProvider: MacWatchTemperatureProbeProviding {
    private let factory = StatsTemperatureProbeFactory()

    func makeFastProbes() -> [any TemperatureProbe] {
        factory.makeFastProbes()
    }

    func makeSlowProbes() -> [any TemperatureProbe] {
        factory.makeSlowProbes()
    }

    func makeSystemProbes() -> [any TemperatureProbe] {
        factory.makeSystemProbes()
    }

    func makeSensorProbes() -> [any TemperatureProbe] {
        factory.makeSensorProbes()
    }

    func invalidateTemperatureSnapshots() {
        factory.invalidateTemperatureSnapshots()
    }
}

@MainActor
final class MacWatchRuntime: ObservableObject {
    @Published private(set) var currentSession: MonitoringSession?
    @Published private(set) var liveState: LiveTemperatureState?
    @Published private(set) var settings: AppSettings
    @Published private(set) var shouldShowFirstRunGuide: Bool
    let firstRunGuideContext: FirstRunGuideContext
    @Published private(set) var historyRevision: Int = 0
    @Published private(set) var historyErrorMessage: String?

    var stateDidChange: ((LiveTemperatureState?) -> Void)?
    var settingsDidChange: ((AppSettings) -> Void)?

    private let repository: SessionHistoryRepository
    private let settingsStore: SettingsStore
    private let bus: SampleBus
    private let capabilityService: TemperatureCapabilityService
    private let liveTemperatureStore: LiveTemperatureStore
    private let schedulerBuilder: any TemperatureSchedulerBuilding
    private let seriesQueryExecutor: TemperatureSeriesQueryExecutor
    private var scheduler: any TemperatureScheduling
    private let clock: @Sendable () -> Date
    private let probes: [any TemperatureProbe]
    private let fastDomains: Set<TemperatureDomain>
    private let fastSampleIntervalOverride: TimeInterval?
    private let slowSampleIntervalOverride: TimeInterval?
    private let firstRunGuideStateStore: FirstRunGuideStateStore
    private let historyWriter: SessionHistoryWriter
    private let invalidateTemperatureSnapshots: () -> Void
    private var didSubscribe = false
    private var schedulerRestartGeneration = 0
    private var schedulerRestartTask: Task<Void, Never>?

    init(
        sessionHistoryRepository: SessionHistoryRepository = MacWatchSharedDependencies.sessionHistoryRepository,
        settingsStore: SettingsStore = MacWatchSharedDependencies.settingsStore,
        probeProvider: MacWatchTemperatureProbeProviding = StatsAdapterTemperatureProbeProvider(),
        schedulerBuilder: any TemperatureSchedulerBuilding = LiveTemperatureSchedulerBuilder(),
        initialSettings: AppSettings? = nil,
        forceShowFirstRunGuide: Bool? = nil,
        firstRunGuideStateStore: FirstRunGuideStateStore = FirstRunGuideStateStore(),
        fastSampleInterval: TimeInterval? = nil,
        slowSampleInterval: TimeInterval? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = sessionHistoryRepository
        self.settingsStore = settingsStore
        self.schedulerBuilder = schedulerBuilder
        self.seriesQueryExecutor = TemperatureSeriesQueryExecutor(repository: sessionHistoryRepository)
        self.clock = clock
        self.settings = initialSettings ?? settingsStore.load()
        self.fastSampleIntervalOverride = fastSampleInterval
        self.slowSampleIntervalOverride = slowSampleInterval
        self.firstRunGuideStateStore = firstRunGuideStateStore
        self.shouldShowFirstRunGuide = forceShowFirstRunGuide
            ?? firstRunGuideStateStore.shouldShowFirstRunGuide()
        self.firstRunGuideContext = FirstRunGuideContext.detect()
        self.historyWriter = SessionHistoryWriter(repository: sessionHistoryRepository)
        self.invalidateTemperatureSnapshots = probeProvider.invalidateTemperatureSnapshots

        let fastProbes = probeProvider.makeFastProbes()
        let probes = probeProvider.makeProbes()
        self.probes = probes
        self.fastDomains = Set(fastProbes.map(\.domain))
        self.bus = SampleBus()
        self.liveTemperatureStore = LiveTemperatureStore()
        self.capabilityService = TemperatureCapabilityService(
            probes: probes,
            repository: sessionHistoryRepository,
            clock: clock
        )
        self.scheduler = makeNoopTemperatureScheduler()
        self.scheduler = makeScheduler()
    }

    func dismissFirstRunGuide() {
        shouldShowFirstRunGuide = false
        firstRunGuideStateStore.markFirstRunGuideCompleted()
    }

    func completeFirstRunGuide(configuration: FirstRunGuideConfiguration) {
        updateSettings { settings in
            settings.temperatureUnit = configuration.temperatureUnit
            settings.menuBarDisplayMetric = configuration.menuBarDisplayMetric
            settings.refreshInterval = configuration.refreshInterval
        }
        dismissFirstRunGuide()
    }

    func start() {
        do {
            currentSession = try repository.currentSession()
        } catch {
            assertionFailure("Failed to load current session: \(error)")
            return
        }

        guard let session = currentSession else {
            return
        }

        scheduleSchedulerRestart(sessionID: session.id)
    }

    func handleLifecycleEvent(_ event: AppLifecycleEvent) {
        switch event {
        case .launched:
            return
        case .willSleep:
            Task {
                await scheduler.pause(reason: .systemSleep, at: clock())
            }
        case .didWake:
            invalidateTemperatureSnapshots()
            Task {
                await scheduler.resume(reason: .systemWake, at: clock())
            }
        case .willTerminate:
            Task {
                await scheduler.stop(at: clock())
            }
        }
    }

    func currentSample(metricName: String) -> TemperatureSample? {
        liveState?.samplesByMetricName[metricName]
    }

    func series(
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange = .oneHour,
        maxPoints: Int = 240
    ) -> TemperatureSeries? {
        guard let session = currentSession else {
            return nil
        }

        do {
            return try repository.query(
                sessionID: session.id,
                domain: domain,
                metricName: metricName,
                range: range,
                now: clock(),
                maxPoints: maxPoints
            )
        } catch {
            assertionFailure("Failed to load trend data: \(error)")
            return nil
        }
    }

    func loadSeries(
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange = .oneHour,
        maxPoints: Int = 240
    ) async -> TemperatureSeries? {
        guard let session = currentSession else {
            return nil
        }

        do {
            return try await seriesQueryExecutor.query(
                sessionID: session.id,
                domain: domain,
                metricName: metricName,
                range: range,
                now: clock(),
                maxPoints: maxPoints
            )
        } catch {
            assertionFailure("Failed to load trend data: \(error)")
            return nil
        }
    }

    func clearCurrentSessionHistory() {
        do {
            try repository.clearCurrentSessionHistory(at: clock())
            historyRevision += 1
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = error.localizedDescription
            assertionFailure("Failed to clear session history: \(error)")
        }
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        var updatedSettings = settings
        transform(&updatedSettings)

        guard updatedSettings != settings else {
            return
        }

        let previousRefreshInterval = settings.refreshInterval
        settings = updatedSettings
        settingsStore.save(updatedSettings)
        settingsDidChange?(updatedSettings)

        if updatedSettings.refreshInterval != previousRefreshInterval {
            applyRefreshInterval(updatedSettings.refreshInterval)
        }
    }

    func applyRefreshInterval(_ interval: RefreshInterval) {
        if settings.refreshInterval != interval {
            settings.refreshInterval = interval
            settingsStore.save(settings)
            settingsDidChange?(settings)
        }

        guard let session = currentSession else {
            return
        }

        scheduleSchedulerRestart(sessionID: session.id)
    }

    func effectiveRealtimeInterval(for domain: TemperatureDomain) -> TimeInterval {
        effectiveSamplingPolicy(for: domain).realtimeInterval
    }

    private func ensureBusSubscription() async {
        guard didSubscribe == false else {
            return
        }
        didSubscribe = true
        _ = await bus.subscribe { [weak self] event in
            await self?.handleBusEvent(event)
        }
    }

    private func handleBusEvent(_ event: TemperatureSampleEvent) async {
        let state = await liveTemperatureStore.apply(event)
        apply(state: state)

        switch event {
        case let .samples(samples, context) where context.shouldWriteHistory:
            apply(historyWriteResult: await historyWriter.writeSamples(samples, context: context))
        case .samples:
            return
        case let .gap(event):
            apply(historyWriteResult: await historyWriter.writeTimelineEvent(event))
        case .capabilities:
            return
        }
    }

    private func apply(historyWriteResult: SessionHistoryWriteResult) {
        if historyWriteResult.didWriteHistory {
            historyRevision += 1
            historyErrorMessage = nil
        } else if let errorMessage = historyWriteResult.errorMessage {
            historyErrorMessage = errorMessage
        }
    }

    private func apply(state: LiveTemperatureState) {
        liveState = state
        stateDidChange?(state)
    }

    private func makeScheduler() -> any TemperatureScheduling {
        let minimumTickInterval = max(
            0.005,
            probes.map { effectiveSamplingPolicy(for: $0.domain).realtimeInterval }.min().map { $0 / 2 } ?? 2.5
        )

        return schedulerBuilder.makeScheduler(
            probes: probes,
            capabilityService: capabilityService,
            bus: bus,
            clock: clock,
            minimumTickInterval: minimumTickInterval,
            policyForDomain: { [weak self] domain in
                self?.effectiveSamplingPolicy(for: domain) ?? TemperatureSamplingPolicy.default(for: domain)
            }
        )
    }

    private func effectiveSamplingPolicy(for domain: TemperatureDomain) -> TemperatureSamplingPolicy {
        TemperatureSamplingPolicy.default(
            for: domain,
            userRealtimeInterval: requestedRealtimeInterval(for: domain)
        )
    }

    private func requestedRealtimeInterval(for domain: TemperatureDomain) -> TimeInterval {
        if fastDomains.contains(domain) {
            return fastSampleIntervalOverride ?? settings.refreshInterval.rawValue
        }

        switch domain {
        case .memory, .ssd, .battery:
            return slowSampleIntervalOverride ?? max(settings.refreshInterval.rawValue, RefreshInterval.thirtySeconds.rawValue)
        case .system, .sensor:
            return slowSampleIntervalOverride ?? max(settings.refreshInterval.rawValue, RefreshInterval.tenSeconds.rawValue)
        case .cpu, .gpu:
            return fastSampleIntervalOverride ?? settings.refreshInterval.rawValue
        }
    }

    private func scheduleSchedulerRestart(sessionID: UUID) {
        schedulerRestartGeneration += 1
        let generation = schedulerRestartGeneration
        schedulerRestartTask?.cancel()
        schedulerRestartTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.restartScheduler(sessionID: sessionID, generation: generation)
        }
    }

    private func restartScheduler(sessionID: UUID, generation: Int) async {
        let previousScheduler = scheduler
        await previousScheduler.stop(at: clock())
        guard generation == schedulerRestartGeneration else {
            return
        }

        let newScheduler = makeScheduler()
        scheduler = newScheduler
        await ensureBusSubscription()
        guard generation == schedulerRestartGeneration else {
            await newScheduler.stop(at: clock())
            return
        }

        await newScheduler.start(sessionID: sessionID)
        guard generation == schedulerRestartGeneration else {
            await newScheduler.stop(at: clock())
            return
        }
    }

}
