import Foundation
import MacWatchCore
import StatsAdapter

enum MacWatchSharedDependencies {
    static let sessionHistoryRepository: SessionHistoryRepository = makeSessionHistoryRepository()

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
}

struct StatsAdapterTemperatureProbeProvider: MacWatchTemperatureProbeProviding {
    private let factory = StatsTemperatureProbeFactory()

    func makeFastProbes() -> [any TemperatureProbe] {
        factory.makeFastProbes()
    }

    func makeSlowProbes() -> [any TemperatureProbe] {
        factory.makeSlowProbes()
    }
}

@MainActor
final class MacWatchRuntime: ObservableObject {
    @Published private(set) var currentSession: MonitoringSession?
    @Published private(set) var liveState: LiveTemperatureState?
    @Published private(set) var historyRevision: Int = 0
    @Published private(set) var historyErrorMessage: String?

    var stateDidChange: ((LiveTemperatureState?) -> Void)?

    private let repository: SessionHistoryRepository
    private let bus: SampleBus
    private let capabilityService: TemperatureCapabilityService
    private let liveTemperatureStore: LiveTemperatureStore
    private let scheduler: TemperatureScheduler
    private let clock: @Sendable () -> Date
    private var didSubscribe = false

    init(
        sessionHistoryRepository: SessionHistoryRepository = MacWatchSharedDependencies.sessionHistoryRepository,
        probeProvider: MacWatchTemperatureProbeProviding = StatsAdapterTemperatureProbeProvider(),
        fastSampleInterval: TimeInterval = 5,
        slowSampleInterval: TimeInterval = 30,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = sessionHistoryRepository
        self.clock = clock

        let fastProbes = probeProvider.makeFastProbes()
        let probes = probeProvider.makeProbes()
        self.bus = SampleBus()
        self.liveTemperatureStore = LiveTemperatureStore()
        self.capabilityService = TemperatureCapabilityService(
            probes: probes,
            repository: sessionHistoryRepository,
            clock: clock
        )

        let fastDomains = Set(fastProbes.map(\.domain))
        let policyByDomain = Dictionary(uniqueKeysWithValues: probes.map { probe in
            let requestedInterval = fastDomains.contains(probe.domain)
                ? fastSampleInterval
                : slowSampleInterval

            let policy = TemperatureSamplingPolicy.default(
                for: probe.domain,
                userRealtimeInterval: requestedInterval
            )
            return (probe.domain, policy)
        })

        let minRealtime = policyByDomain.values.map(\.realtimeInterval).min() ?? 5
        let minimumTickInterval = max(0.005, minRealtime / 2)
        let policyForDomain: (TemperatureDomain) -> TemperatureSamplingPolicy = { domain in
            policyByDomain[domain] ?? TemperatureSamplingPolicy.default(for: domain)
        }

        self.scheduler = TemperatureScheduler(
            probes: probes,
            capabilityService: capabilityService,
            bus: bus,
            clock: clock,
            minimumTickInterval: minimumTickInterval,
            policyForDomain: policyForDomain
        )
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

        Task {
            await ensureBusSubscription()
            await scheduler.start(sessionID: session.id)
        }
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
            for sample in samples {
                do {
                    try repository.insertSample(sample)
                } catch {
                    await recordHistoryWriteFailure(
                        sessionID: context.sessionID,
                        timestamp: context.sampledAt,
                        domain: sample.domain,
                        metricName: sample.metricName,
                        message: error.localizedDescription
                    )
                }
            }
        case .samples:
            return
        case let .gap(event):
            do {
                try repository.insertTimelineEvent(event)
            } catch {
                await recordHistoryWriteFailure(
                    sessionID: event.sessionID,
                    timestamp: event.startedAt,
                    domain: event.domain,
                    metricName: event.metricName,
                    message: error.localizedDescription
                )
            }
        case .capabilities:
            return
        }
    }

    private func recordHistoryWriteFailure(
        sessionID: UUID,
        timestamp: Date,
        domain: TemperatureDomain?,
        metricName: String?,
        message: String
    ) async {
        do {
            try repository.insertTimelineEvent(
                TimelineEvent(
                    id: UUID(),
                    sessionID: sessionID,
                    eventType: .historyWriteFailed,
                    startedAt: timestamp,
                    endedAt: nil,
                    domain: domain,
                    metricName: metricName,
                    reasonCode: "historyWriteFailed",
                    message: message
                )
            )
        } catch {
            return
        }
    }

    private func apply(state: LiveTemperatureState) {
        liveState = state
        stateDidChange?(state)
    }

}
