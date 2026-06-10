import Foundation
import MacWatchCore
import StatsAdapter

enum MacWatchSharedDependencies {
    static let sessionHistoryRepository = InMemorySessionHistoryRepository()
}

protocol MacWatchTemperatureProbeProviding {
    func makeFastProbes() -> [any TemperatureProbe]
    func makeSlowProbes() -> [any TemperatureProbe]
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

    var stateDidChange: ((LiveTemperatureState?) -> Void)?

    private let repository: SessionHistoryRepository
    private let fastMonitorService: TemperatureMonitorService
    private let slowMonitorService: TemperatureMonitorService
    private let fastSampleInterval: TimeInterval
    private let slowSampleInterval: TimeInterval
    private let clock: @Sendable () -> Date
    private var fastTimer: Timer?
    private var slowTimer: Timer?

    init(
        sessionHistoryRepository: SessionHistoryRepository = MacWatchSharedDependencies.sessionHistoryRepository,
        probeProvider: MacWatchTemperatureProbeProviding = StatsAdapterTemperatureProbeProvider(),
        fastSampleInterval: TimeInterval = 5,
        slowSampleInterval: TimeInterval = 30,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = sessionHistoryRepository
        self.fastMonitorService = TemperatureMonitorService(
            probes: probeProvider.makeFastProbes(),
            repository: sessionHistoryRepository,
            clock: clock
        )
        self.slowMonitorService = TemperatureMonitorService(
            probes: probeProvider.makeSlowProbes(),
            repository: sessionHistoryRepository,
            clock: clock
        )
        self.fastSampleInterval = fastSampleInterval
        self.slowSampleInterval = slowSampleInterval
        self.clock = clock
    }

    deinit {
        fastTimer?.invalidate()
        slowTimer?.invalidate()
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
            let fastCapabilityState = await fastMonitorService.detectCapabilities(sessionID: session.id)
            applyMerging(state: fastCapabilityState)

            let slowCapabilityState = await slowMonitorService.detectCapabilities(sessionID: session.id)
            applyMerging(state: slowCapabilityState)

            let sampleState = await fastMonitorService.sampleOnce(sessionID: session.id)
            applyMerging(state: sampleState)

            let slowSampleState = await slowMonitorService.sampleOnce(sessionID: session.id)
            applyMerging(state: slowSampleState)
        }

        scheduleTimer(interval: fastSampleInterval, for: session.id) { [fastMonitorService] sessionID in
            await fastMonitorService.sampleOnce(sessionID: sessionID)
        } assign: { [weak self] timer in
            self?.fastTimer = timer
        }
        scheduleTimer(interval: slowSampleInterval, for: session.id) { [slowMonitorService] sessionID in
            await slowMonitorService.sampleOnce(sessionID: sessionID)
        } assign: { [weak self] timer in
            self?.slowTimer = timer
        }
    }

    func currentSample(metricName: String) -> TemperatureSample? {
        liveState?.samplesByMetricName[metricName]
    }

    func series(
        domain: TemperatureDomain,
        metricName: String,
        window: TimeInterval = 3600,
        maxPoints: Int = 240
    ) -> TemperatureSeries? {
        guard let session = currentSession else {
            return nil
        }

        let end = clock()
        let cutoff = end.addingTimeInterval(-window)
        let start = session.startedAt > cutoff ? session.startedAt : cutoff

        do {
            let query = try TemperatureQuery(
                sessionID: session.id,
                domains: [domain],
                metricNames: [metricName],
                start: start,
                end: end,
                maxPoints: maxPoints
            )
            return try repository.query(query).first
        } catch {
            assertionFailure("Failed to load trend data: \(error)")
            return nil
        }
    }

    private func scheduleTimer(
        interval: TimeInterval,
        for sessionID: UUID,
        sample: @escaping @Sendable (UUID) async -> LiveTemperatureState,
        assign: (Timer) -> Void
    ) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                let nextState = await sample(sessionID)
                self.applyMerging(state: nextState)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        assign(timer)
    }

    private func applyMerging(state: LiveTemperatureState) {
        guard let existing = liveState, existing.sessionID == state.sessionID else {
            apply(state: state)
            return
        }

        let samplesByMetricName = existing.samplesByMetricName.merging(state.samplesByMetricName) { _, new in new }
        let capabilitiesByDomain = existing.capabilitiesByDomain.merging(state.capabilitiesByDomain) { _, new in new }
        apply(
            state: LiveTemperatureState(
                sessionID: state.sessionID,
                updatedAt: state.updatedAt ?? existing.updatedAt,
                samplesByMetricName: samplesByMetricName,
                capabilitiesByDomain: capabilitiesByDomain,
                hottestValidSample: Self.hottestValidSample(from: Array(samplesByMetricName.values))
            )
        )
    }

    private func apply(state: LiveTemperatureState) {
        liveState = state
        stateDidChange?(state)
    }

    private static func hottestValidSample(from samples: [TemperatureSample]) -> TemperatureSample? {
        samples
            .filter { $0.quality == .valid && $0.valueCelsius != nil }
            .max { lhs, rhs in
                (lhs.valueCelsius ?? -.infinity) < (rhs.valueCelsius ?? -.infinity)
            }
    }
}
