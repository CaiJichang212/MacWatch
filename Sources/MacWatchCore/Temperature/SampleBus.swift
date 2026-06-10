import Foundation

public struct SampleContext: Sendable, Equatable {
    public let sessionID: UUID
    public let probeID: String
    public let sampledAt: Date
    public let shouldWriteHistory: Bool
}

public enum TemperatureSampleEvent: Sendable, Equatable {
    case samples([TemperatureSample], context: SampleContext)
    case capabilities([TemperatureDomain: TemperatureCapability], reason: CapabilityDetectionReason)
    case gap(TimelineEvent)
}

public final actor SampleBus {
    public typealias Handler = @Sendable (TemperatureSampleEvent) async throws -> Void

    private var subscribers: [(UUID, Handler)] = []

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        subscribers.append((id, handler))
        return id
    }

    public func unsubscribe(_ id: UUID) {
        subscribers.removeAll { current in
            current.0 == id
        }
    }

    public func publish(_ event: TemperatureSampleEvent) async {
        for ( _, handler) in subscribers {
            do {
                try await handler(event)
            } catch {
                continue
            }
        }
    }
}
