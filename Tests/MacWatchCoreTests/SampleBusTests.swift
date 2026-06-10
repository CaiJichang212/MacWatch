import XCTest
@testable import MacWatchCore

final class SampleBusTests: XCTestCase {
    func testMultipleSubscribersReceiveEventsInOrder() async {
        let bus = SampleBus()
        let collector = SampleBusCollector()

        _ = await bus.subscribe { event in
            await collector.record(kind: kind(of: event))
        }

        _ = await bus.subscribe { event in
            await collector.record(kind: kind(of: event))
        }

        let sample = try! TemperatureSample.makeValid(
            sessionID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1),
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            valueCelsius: 62,
            source: .hidSensors
        )

        await bus.publish(
            .samples(
                [sample],
                context: SampleContext(
                    sessionID: sample.sessionID,
                    probeID: "cpu",
                    sampledAt: sample.timestamp,
                    shouldWriteHistory: true
                )
            )
        )

        await bus.publish(
            .gap(
                TimelineEvent(
                    id: UUID(),
                    sessionID: sample.sessionID,
                    eventType: .probeReadFailed,
                    startedAt: sample.timestamp,
                    endedAt: sample.timestamp,
                    domain: .cpu,
                    metricName: sample.metricName,
                    reasonCode: "readFailed",
                    message: "test"
                )
            )
        )

        let kinds = await collector.kinds()
        XCTAssertEqual(kinds, ["samples", "samples", "gap", "gap"])
    }

    func testFailedSubscriberDoesNotBlockOthers() async {
        let bus = SampleBus()
        let collector = SampleBusCollector()

        _ = await bus.subscribe { _ in
            throw TestBusError.failed
        }

        _ = await bus.subscribe { event in
            await collector.record(kind: kind(of: event))
        }

        let sample = try! TemperatureSample.makeValid(
            sessionID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1),
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            valueCelsius: 62,
            source: .hidSensors
        )

        await bus.publish(
            .samples(
                [sample],
                context: SampleContext(
                    sessionID: sample.sessionID,
                    probeID: "cpu",
                    sampledAt: sample.timestamp,
                    shouldWriteHistory: false
                )
            )
        )

        let kinds = await collector.kinds()
        XCTAssertEqual(kinds, ["samples"])
    }
}

private enum TestBusError: Error {
    case failed
}

private func kind(of event: TemperatureSampleEvent) -> String {
    switch event {
    case .samples:
        return "samples"
    case .capabilities:
        return "capabilities"
    case .gap:
        return "gap"
    }
}

private actor SampleBusCollector {
    private var recordedKinds: [String] = []

    func record(kind: String) {
        recordedKinds.append(kind)
    }

    func kinds() -> [String] {
        recordedKinds
    }
}
