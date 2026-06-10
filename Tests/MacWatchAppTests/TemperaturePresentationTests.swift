import XCTest
import MacWatchCore
@testable import MacWatchApp

final class TemperaturePresentationTests: XCTestCase {
    func testMenuBarTemperatureFormatterFormatsRoundedCelsius() {
        XCTAssertEqual(MenuBarTemperatureFormatter.title(forCelsius: 72.4), "72°C")
        XCTAssertEqual(MenuBarTemperatureFormatter.title(forCelsius: 72.6), "73°C")
    }

    func testMenuBarTemperatureFormatterUsesUnavailablePlaceholder() {
        XCTAssertEqual(MenuBarTemperatureFormatter.title(forUnavailableMetric: .cpu), "--°C")
    }

    func testDashboardSnapshotShowsAllSupportedDomainsAndOnlyUsesValidHottest() throws {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 120)
        let state = LiveTemperatureState(
            sessionID: sessionID,
            updatedAt: timestamp,
            samplesByMetricName: [
                TemperatureMetricName.cpuHottest: try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU Hottest",
                    valueCelsius: 68.0,
                    source: .hidSensors,
                    rawKey: "pACC MTR Temp Sensor0"
                ),
                TemperatureMetricName.gpuHottest: try TemperatureSample.makeInvalid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.gpuHottest,
                    domain: .gpu,
                    deviceID: "gpu",
                    displayName: "GPU Hottest",
                    quality: .readFailed,
                    source: .smc,
                    errorCode: "temperatureUnavailable"
                ),
                TemperatureMetricName.ssdInternal: try TemperatureSample.makeInvalid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.ssdInternal,
                    domain: .ssd,
                    deviceID: "ssd",
                    displayName: "Internal SSD",
                    quality: .unsupported,
                    source: .nvmeSMART,
                    errorCode: "unsupported"
                ),
                TemperatureMetricName.battery: try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.battery,
                    domain: .battery,
                    deviceID: "battery",
                    displayName: "Battery",
                    valueCelsius: 32.0,
                    source: .batteryIORegistry
                ),
            ],
            capabilitiesByDomain: [
                .cpu: capability(sessionID: sessionID, domain: .cpu, source: .hidSensors, supported: true, readable: true, reasonCode: "ok", timestamp: timestamp),
                .gpu: capability(sessionID: sessionID, domain: .gpu, source: .smc, supported: false, readable: false, reasonCode: "readFailed", timestamp: timestamp),
                .memory: capability(sessionID: sessionID, domain: .memory, source: .smc, supported: false, readable: false, reasonCode: "unsupported", timestamp: timestamp),
                .ssd: capability(sessionID: sessionID, domain: .ssd, source: .nvmeSMART, supported: false, readable: false, reasonCode: "unsupported", timestamp: timestamp),
                .battery: capability(sessionID: sessionID, domain: .battery, source: .batteryIORegistry, supported: true, readable: true, reasonCode: "ok", timestamp: timestamp),
            ],
            hottestValidSample: try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU Hottest",
                valueCelsius: 68.0,
                source: .hidSensors,
                rawKey: "pACC MTR Temp Sensor0"
            )
        )

        let snapshot = TemperatureDashboardSnapshot(liveState: state)

        XCTAssertEqual(snapshot.hottestTitle, "68°C")
        XCTAssertEqual(snapshot.rows.map(\.domain), [.cpu, .gpu, .memory, .ssd, .battery])
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .gpu })?.statusText, "Read failed")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .memory })?.statusText, "Unsupported")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .battery })?.statusText, "32°C")
    }

    func testMenuBarTemperatureFormatterReturnsUnavailableForNonValidSamples() throws {
        let invalid = try TemperatureSample.makeInvalid(
            sessionID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1),
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            quality: .stale,
            source: .hidSensors,
            errorCode: "stale"
        )
        XCTAssertEqual(MenuBarTemperatureFormatter.title(for: invalid), "--°C")
    }

    func testDashboardSnapshotMarksStaleAndUnavailableStates() {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 200)
        let state = LiveTemperatureState(
            sessionID: sessionID,
            updatedAt: timestamp,
            samplesByMetricName: [
                TemperatureMetricName.cpuHottest: staleSample(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.cpuHottest
                ),
                TemperatureMetricName.memoryProximity: unsupportedSample(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.memoryProximity
                )
            ],
            capabilitiesByDomain: [
                .cpu: capability(sessionID: sessionID, domain: .cpu, source: .hidSensors, supported: true, readable: true, reasonCode: "ok", timestamp: timestamp),
                .memory: capability(sessionID: sessionID, domain: .memory, source: .smc, supported: false, readable: false, reasonCode: "unsupported", timestamp: timestamp),
                .ssd: capability(sessionID: sessionID, domain: .ssd, source: .nvmeSMART, supported: false, readable: false, reasonCode: "readFailed", timestamp: timestamp),
            ],
            hottestValidSample: nil
        )

        let snapshot = TemperatureDashboardSnapshot(liveState: state)

        XCTAssertEqual(snapshot.hottestTitle, "--°C")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .cpu })?.statusText, "Stale")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .memory })?.statusText, "Unsupported")
    }
}

private func capability(
    sessionID: UUID,
    domain: TemperatureDomain,
    source: TemperatureSource,
    supported: Bool,
    readable: Bool,
    reasonCode: String,
    timestamp: Date
    ) -> TemperatureCapability {
    TemperatureCapability(
        id: UUID(),
        sessionID: sessionID,
        domain: domain,
        source: source,
        supported: supported,
        readable: readable,
        reasonCode: reasonCode,
        reasonMessage: reasonCode,
        rawKey: nil,
        detectedAt: timestamp,
        updatedAt: timestamp
    )
}

private func staleSample(
    sessionID: UUID,
    timestamp: Date,
    metricName: String
) -> TemperatureSample {
    try! TemperatureSample.makeInvalid(
        sessionID: sessionID,
        timestamp: timestamp,
        metricName: metricName,
        domain: .cpu,
        deviceID: "cpu",
        displayName: "CPU",
        quality: .stale,
        source: .hidSensors,
        errorCode: "stale"
    )
}

private func unsupportedSample(
    sessionID: UUID,
    timestamp: Date,
    metricName: String
) -> TemperatureSample {
    try! TemperatureSample.makeInvalid(
        sessionID: sessionID,
        timestamp: timestamp,
        metricName: metricName,
        domain: .memory,
        deviceID: "memory",
        displayName: "Memory",
        quality: .unsupported,
        source: .smc,
        errorCode: "unsupported"
    )
}
