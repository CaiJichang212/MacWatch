import Foundation
import MacWatchCore

protocol TemperatureScheduling: AnyObject {
    func start(sessionID: UUID) async
    func pause(reason: SchedulerPauseReason, at timestamp: Date) async
    func resume(reason: SchedulerResumeReason, at timestamp: Date) async
    func stop(at timestamp: Date) async
}

protocol TemperatureSchedulerBuilding {
    func makeScheduler(
        probes: [any TemperatureProbe],
        capabilityService: TemperatureCapabilityService,
        bus: SampleBus,
        clock: @escaping @Sendable () -> Date,
        minimumTickInterval: TimeInterval,
        policyForDomain: @escaping (TemperatureDomain) -> TemperatureSamplingPolicy
    ) -> any TemperatureScheduling
}

struct LiveTemperatureSchedulerBuilder: TemperatureSchedulerBuilding {
    func makeScheduler(
        probes: [any TemperatureProbe],
        capabilityService: TemperatureCapabilityService,
        bus: SampleBus,
        clock: @escaping @Sendable () -> Date,
        minimumTickInterval: TimeInterval,
        policyForDomain: @escaping (TemperatureDomain) -> TemperatureSamplingPolicy
    ) -> any TemperatureScheduling {
        TemperatureScheduler(
            probes: probes,
            capabilityService: capabilityService,
            bus: bus,
            clock: clock,
            minimumTickInterval: minimumTickInterval,
            policyForDomain: policyForDomain
        )
    }
}

extension TemperatureScheduler: TemperatureScheduling {}

private final actor NoopTemperatureScheduler: TemperatureScheduling {
    func start(sessionID _: UUID) async {}
    func pause(reason _: SchedulerPauseReason, at _: Date) async {}
    func resume(reason _: SchedulerResumeReason, at _: Date) async {}
    func stop(at _: Date) async {}
}

func makeNoopTemperatureScheduler() -> any TemperatureScheduling {
    NoopTemperatureScheduler()
}
