import XCTest
@testable import MacWatchCore

final class LiveTemperatureStoreTests: XCTestCase {
    func testValidSamplesUpdateLiveStateAndHottest() async throws {
        let store = LiveTemperatureStore(policyForDomain: { _ in
            TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
        })

        let baseTime = Date(timeIntervalSince1970: 10)

        let state = await store.apply(
            .samples(
                [
                    sample(
                        metricName: TemperatureMetricName.cpuHottest,
                        domain: .cpu,
                        value: 62,
                        source: .hidSensors,
                        at: baseTime,
                    ),
                    sample(
                        metricName: TemperatureMetricName.gpuHottest,
                        domain: .gpu,
                        value: 55,
                        source: .smc,
                        at: baseTime,
                    ),
                ],
                context: context(at: baseTime)
            )
        )

        XCTAssertEqual(state.samplesByMetricName.count, 2)
        XCTAssertEqual(state.hottestValidSample?.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(state.hottestValidSample?.valueCelsius, 62)
        XCTAssertNil(state.samplesByMetricName[TemperatureMetricName.cpuHottest]?.errorCode)
    }

    func testUnsupportedAndReadFailedDoNotParticipateInHottestTemperature() async {
        let store = LiveTemperatureStore(policyForDomain: { _ in
            TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
        })

        let baseTime = Date(timeIntervalSince1970: 20)

        _ = await store.apply(
            .samples(
                [
                    sample(
                        metricName: TemperatureMetricName.cpuHottest,
                        domain: .cpu,
                        value: 64,
                        source: .hidSensors,
                        at: baseTime,
                    ),
                ],
                context: context(at: baseTime)
            )
        )

        let laterState = await store.apply(
            .samples(
                [
                    invalidSample(
                        metricName: TemperatureMetricName.gpuHottest,
                        domain: .gpu,
                        quality: .unsupported,
                        source: .smc,
                        at: baseTime.addingTimeInterval(1)
                    ),
                    invalidSample(
                        metricName: TemperatureMetricName.ssdInternal,
                        domain: .ssd,
                        quality: .readFailed,
                        source: .nvmeSMART,
                        at: baseTime.addingTimeInterval(1)
                    ),
                ],
                context: context(at: baseTime.addingTimeInterval(1))
            )
        )

        XCTAssertEqual(laterState.hottestValidSample?.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(laterState.samplesByMetricName[TemperatureMetricName.cpuHottest]?.quality, .valid)
        XCTAssertEqual(laterState.samplesByMetricName[TemperatureMetricName.gpuHottest]?.quality, .unsupported)
        XCTAssertEqual(laterState.samplesByMetricName[TemperatureMetricName.ssdInternal]?.quality, .readFailed)
        XCTAssertEqual(laterState.lastValidSamplesByMetricName.count, 1)
        XCTAssertEqual(laterState.lastValidSamplesByMetricName[TemperatureMetricName.cpuHottest]?.metricName, TemperatureMetricName.cpuHottest)
    }

    func testAverageSamplesDoNotParticipateInGlobalHottestTemperature() async {
        let store = LiveTemperatureStore(policyForDomain: { _ in
            TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
        })
        let baseTime = Date(timeIntervalSince1970: 25)

        let state = await store.apply(
            .samples(
                [
                    sample(
                        metricName: TemperatureMetricName.cpuHottest,
                        domain: .cpu,
                        value: 62,
                        source: .hidSensors,
                        at: baseTime
                    ),
                    sample(
                        metricName: TemperatureMetricName.gpuAverage,
                        domain: .gpu,
                        value: 90,
                        source: .hidSensors,
                        at: baseTime
                    ),
                ],
                context: context(at: baseTime)
            )
        )

        XCTAssertEqual(state.hottestValidSample?.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(state.hottestValidSample?.valueCelsius, 62)
    }

    func testMarkStaleAfterThresholdKeepsLastValidReferenceAndClearsCurrentHottest() async {
        let store = LiveTemperatureStore(policyForDomain: { _ in
            TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
        })

        let baseTime = Date(timeIntervalSince1970: 30)

        _ = await store.apply(
            .samples(
                [
                    sample(
                        metricName: TemperatureMetricName.cpuHottest,
                        domain: .cpu,
                        value: 68,
                        source: .hidSensors,
                        at: baseTime
                    )
                ],
                context: context(at: baseTime)
            )
        )

        let staleState = await store.markStale(now: baseTime.addingTimeInterval(13))

        XCTAssertEqual(staleState.samplesByMetricName[TemperatureMetricName.cpuHottest]?.quality, .stale)
        XCTAssertEqual(staleState.lastValidSamplesByMetricName[TemperatureMetricName.cpuHottest]?.quality, .valid)
        XCTAssertNil(staleState.hottestValidSample)
    }
}

private func sample(
    metricName: String,
    domain: TemperatureDomain,
    value: Double,
    source: TemperatureSource,
    at timestamp: Date
) -> TemperatureSample {
    try! TemperatureSample.makeValid(
        sessionID: UUID(),
        timestamp: timestamp,
        metricName: metricName,
        domain: domain,
        deviceID: domain.rawValue,
        displayName: "\(domain.rawValue) Temperature",
        valueCelsius: value,
        source: source
    )
}

private func invalidSample(
    metricName: String,
    domain: TemperatureDomain,
    quality: TemperatureQuality,
    source: TemperatureSource,
    at timestamp: Date
) -> TemperatureSample {
    try! TemperatureSample.makeInvalid(
        sessionID: UUID(),
        timestamp: timestamp,
        metricName: metricName,
        domain: domain,
        deviceID: domain.rawValue,
        displayName: "\(domain.rawValue) Temperature",
        quality: quality,
        source: source,
        errorCode: quality.rawValue
    )
}

private func context(at timestamp: Date) -> SampleContext {
    SampleContext(sessionID: UUID(), probeID: "probe", sampledAt: timestamp, shouldWriteHistory: true)
}
