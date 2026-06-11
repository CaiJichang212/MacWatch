import XCTest
import MacWatchCore
@testable import MacWatchApp

final class TemperaturePresentationTests: XCTestCase {
    func testTemperatureFormatterFormatsRoundedCelsiusAndFahrenheit() {
        XCTAssertEqual(TemperatureFormatter.text(celsius: 72.4, unit: .celsius), "72°C")
        XCTAssertEqual(TemperatureFormatter.text(celsius: 72.6, unit: .celsius), "73°C")
        XCTAssertEqual(TemperatureFormatter.text(celsius: 72.4, unit: .fahrenheit), "162°F")
    }

    func testTemperatureMetricCatalogIncludesExpectedOverviewMetrics() {
        XCTAssertEqual(
            TemperatureMetricCatalog.overviewMetrics.map(\.domain),
            [.cpu, .gpu, .ssd, .battery, .system, .sensor]
        )
        XCTAssertEqual(
            TemperatureMetricCatalog.compatibilityMetrics.map(\.domain),
            [.cpu, .gpu, .ssd, .battery, .system, .sensor]
        )
        XCTAssertEqual(TemperatureMetricCatalog.menuBarMetric(for: .hottest), nil)
        XCTAssertEqual(TemperatureMetricCatalog.menuBarMetric(for: .cpu)?.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(TemperatureMetricCatalog.menuBarMetric(for: .cpu)?.averageMetricName, TemperatureMetricName.cpuAverage)
        XCTAssertEqual(TemperatureMetricCatalog.menuBarMetric(for: .gpu)?.averageMetricName, TemperatureMetricName.gpuAverage)
    }

    func testMetricDescriptorFallsBackWhenDetailSelectionBelongsToPreviousDomain() {
        let gpu = TemperatureMetricCatalog.requiredMetric(for: .gpu)
        let ssd = TemperatureMetricCatalog.requiredMetric(for: .ssd)

        XCTAssertEqual(
            gpu.resolvedDetailMetricName(TemperatureMetricName.cpuHottest),
            TemperatureMetricName.gpuHottest
        )
        XCTAssertEqual(
            ssd.resolvedDetailMetricName(TemperatureMetricName.gpuAverage),
            TemperatureMetricName.ssdInternal
        )
        XCTAssertEqual(
            gpu.resolvedDetailMetricName(TemperatureMetricName.gpuAverage),
            TemperatureMetricName.gpuAverage
        )
    }

    func testOverviewSnapshotShowsAllSupportedDomainsAndOnlyUsesValidHottest() throws {
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
                TemperatureMetricName.cpuAverage: try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.cpuAverage,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU Average",
                    valueCelsius: 62.0,
                    source: .hidSensors
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

        let snapshot = TemperatureOverviewSnapshot(liveState: state, settings: .default)

        XCTAssertEqual(snapshot.hottestValueText, "68°C")
        XCTAssertEqual(snapshot.rows.map(\.domain), [.cpu, .gpu, .ssd, .battery, .system, .sensor])
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .cpu })?.averageValueText, "62°C")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .gpu })?.statusText, "Read failed")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .battery })?.valueText, "32°C")
        XCTAssertEqual(snapshot.availableMetricCount, 2)
    }

    func testOverviewSnapshotMarksStaleAndUnavailableStates() {
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
                )
            ],
            capabilitiesByDomain: [
                .cpu: capability(sessionID: sessionID, domain: .cpu, source: .hidSensors, supported: true, readable: true, reasonCode: "ok", timestamp: timestamp),
                .ssd: capability(sessionID: sessionID, domain: .ssd, source: .nvmeSMART, supported: false, readable: false, reasonCode: "readFailed", timestamp: timestamp),
            ],
            hottestValidSample: nil
        )

        let snapshot = TemperatureOverviewSnapshot(liveState: state, settings: .default)

        XCTAssertEqual(snapshot.hottestValueText, "--°C")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .cpu })?.statusText, "Stale")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .cpu })?.isStale, true)
    }

    func testCompatibilitySnapshotIncludesUnavailableReasons() {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 300)
        let state = LiveTemperatureState(
            sessionID: sessionID,
            updatedAt: timestamp,
            samplesByMetricName: [:],
            capabilitiesByDomain: [
                .gpu: capability(sessionID: sessionID, domain: .gpu, source: .smc, supported: false, readable: false, reasonCode: "unsupported", timestamp: timestamp),
            ],
            hottestValidSample: nil
        )

        let snapshot = CompatibilitySnapshot(liveState: state)

        XCTAssertEqual(snapshot.rows.map(\.domain), [.cpu, .gpu, .ssd, .battery, .system, .sensor])
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .gpu })?.statusText, "Unsupported")
        XCTAssertEqual(snapshot.rows.first(where: { $0.domain == .gpu })?.reasonText, "unsupported")
    }

    func testMenuBarTitleFormatterUsesConfiguredMetricAndKeepsTitleShort() throws {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 400)
        let cpu = try TemperatureSample.makeValid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            valueCelsius: 72.4,
            source: .hidSensors
        )
        let state = LiveTemperatureState(
            sessionID: sessionID,
            updatedAt: timestamp,
            samplesByMetricName: [TemperatureMetricName.cpuHottest: cpu],
            capabilitiesByDomain: [.cpu: capability(sessionID: sessionID, domain: .cpu, source: .hidSensors, supported: true, readable: true, reasonCode: "ok", timestamp: timestamp)],
            hottestValidSample: cpu
        )

        let title = MenuBarTitleFormatter.title(
            liveState: state,
            settings: AppSettings.default
        )

        XCTAssertEqual(title.text, "72°C")
        XCTAssertLessThanOrEqual(title.fullText.count, 30)
    }

    func testMenuBarTitleFormatterUsesLastHottestValueWhenAllMetricsAreStale() throws {
        let sessionID = UUID()
        let staleAt = Date(timeIntervalSince1970: 420)
        let staleCPU = try TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: staleAt,
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            quality: .stale,
            source: .hidSensors,
            errorCode: "stale"
        )
        let staleGPU = try TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: staleAt,
            metricName: TemperatureMetricName.gpuHottest,
            domain: .gpu,
            deviceID: "gpu",
            displayName: "GPU",
            quality: .stale,
            source: .smc,
            errorCode: "stale"
        )
        let lastCPU = try TemperatureSample.makeValid(
            sessionID: sessionID,
            timestamp: staleAt.addingTimeInterval(-10),
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            valueCelsius: 72,
            source: .hidSensors
        )
        let lastGPU = try TemperatureSample.makeValid(
            sessionID: sessionID,
            timestamp: staleAt.addingTimeInterval(-12),
            metricName: TemperatureMetricName.gpuHottest,
            domain: .gpu,
            deviceID: "gpu",
            displayName: "GPU",
            valueCelsius: 68,
            source: .smc
        )
        let state = LiveTemperatureState(
            sessionID: sessionID,
            updatedAt: staleAt,
            samplesByMetricName: [
                TemperatureMetricName.cpuHottest: staleCPU,
                TemperatureMetricName.gpuHottest: staleGPU,
            ],
            capabilitiesByDomain: [:],
            hottestValidSample: nil,
            lastValidSamplesByMetricName: [
                TemperatureMetricName.cpuHottest: lastCPU,
                TemperatureMetricName.gpuHottest: lastGPU,
            ]
        )

        let title = MenuBarTitleFormatter.title(
            liveState: state,
            settings: .default
        )

        XCTAssertEqual(title.text, "72°C")
        XCTAssertEqual(title.statusSuffix, "stale")
        XCTAssertEqual(title.isStale, true)
    }

    func testTemperatureFormatterFallsBackToRawAttributeKeysWhenRawKeyMissing() {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1000)
        let sample = try! TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: TemperatureMetricName.systemHottest,
            domain: .system,
            deviceID: "system",
            displayName: "System Hottest",
            quality: .readFailed,
            source: .smc,
            errorCode: "readFailed",
            attributes: ["rawKeys": "A, B, C"]
        )

        let row = TemperatureOverviewSnapshot.Row(
            domain: .system,
            metricName: TemperatureMetricName.systemHottest,
            title: "System",
            valueText: TemperatureFormatter.placeholder(unit: .celsius),
            averageValueText: nil,
            statusText: TemperatureFormatter.statusText(sample: sample, capability: nil),
            sourceText: TemperatureFormatter.sourceText(sample: sample, capability: nil),
            reasonText: TemperatureFormatter.reasonText(sample: sample, capability: nil),
            updatedAt: timestamp,
            rawKey: TemperatureFormatter.rawKeyText(sample: sample, capability: nil),
            isStale: false
        )

        XCTAssertEqual(row.rawKey, "A, B, C")
        XCTAssertEqual(row.reasonText, "readFailed")
        XCTAssertEqual(row.statusText, "Read failed")
    }

    func testDetailSnapshotFormatsStatisticsAndDoesNotFabricateZeroValues() throws {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 100)
        let first = try TemperatureSample.makeValid(
            sessionID: sessionID,
            timestamp: base,
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            valueCelsius: 60,
            source: .hidSensors
        )
        let latest = try TemperatureSample.makeValid(
            sessionID: sessionID,
            timestamp: base.addingTimeInterval(5),
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            valueCelsius: 72,
            source: .hidSensors
        )
        let series = TemperatureSeries(
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            samples: [first, latest],
            gaps: [],
            statistics: TemperatureSeriesStatistics.compute(samples: [first, latest])
        )

        let snapshot = TemperatureDetailSnapshot(
            descriptor: TemperatureMetricCatalog.requiredMetric(for: .cpu),
            series: series,
            currentSample: latest,
            currentCapability: capability(
                sessionID: sessionID,
                domain: .cpu,
                source: .hidSensors,
                supported: true,
                readable: true,
                reasonCode: "ok",
                timestamp: latest.timestamp
            ),
            lastValidSample: latest,
            fallbackText: "Read failed",
            settings: .default
        )

        XCTAssertEqual(snapshot.currentValueText, "72°C")
        XCTAssertEqual(snapshot.maximumText, "72°C")
        XCTAssertEqual(snapshot.minimumText, "60°C")
        XCTAssertEqual(snapshot.averageText, "66°C")
        XCTAssertEqual(snapshot.statusText, "Valid")
        XCTAssertEqual(snapshot.sampleSummaryText, "2 samples")
    }

    func testDetailSnapshotShowsFallbackWhenNoValidSamplesExist() throws {
        let sessionID = UUID()
        let series = TemperatureSeries(
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            samples: [
                try TemperatureSample.makeInvalid(
                    sessionID: sessionID,
                    timestamp: Date(timeIntervalSince1970: 100),
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    quality: .readFailed,
                    source: .hidSensors,
                    errorCode: "readFailed"
                ),
            ],
            gaps: [],
            statistics: .empty
        )

        let snapshot = TemperatureDetailSnapshot(
            descriptor: TemperatureMetricCatalog.requiredMetric(for: .cpu),
            series: series,
            currentSample: nil,
            currentCapability: nil,
            lastValidSample: nil,
            fallbackText: "Read failed",
            settings: .default
        )

        XCTAssertEqual(snapshot.currentValueText, "--°C")
        XCTAssertEqual(snapshot.statusText, "Read failed")
        XCTAssertEqual(snapshot.sampleSummaryText, "0 samples")
        XCTAssertEqual(snapshot.trendFallbackText, "No samples in selected range")
        XCTAssertEqual(snapshot.maximumText, "--")
        XCTAssertEqual(snapshot.averageText, "--")
    }

    func testDetailSnapshotUsesCurrentLiveStateForStatusAndSource() throws {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 800)
        let lastValid = try TemperatureSample.makeValid(
            sessionID: sessionID,
            timestamp: base,
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            valueCelsius: 74,
            source: .hidSensors
        )
        let stale = try TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: base.addingTimeInterval(30),
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            quality: .stale,
            source: .hidSensors,
            errorCode: "stale"
        )
        let series = TemperatureSeries(
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            samples: [lastValid],
            gaps: [],
            statistics: TemperatureSeriesStatistics.compute(samples: [lastValid])
        )

        let snapshot = TemperatureDetailSnapshot(
            descriptor: TemperatureMetricCatalog.requiredMetric(for: .cpu),
            series: series,
            currentSample: stale,
            currentCapability: capability(
                sessionID: sessionID,
                domain: .cpu,
                source: .hidSensors,
                supported: true,
                readable: true,
                reasonCode: "ok",
                timestamp: stale.timestamp
            ),
            lastValidSample: lastValid,
            fallbackText: "Waiting",
            settings: .default
        )

        XCTAssertEqual(snapshot.currentValueText, "74°C")
        XCTAssertEqual(snapshot.statusText, "Stale")
        XCTAssertEqual(snapshot.sourceText, "HID Sensors")
        XCTAssertEqual(snapshot.sampleSummaryText, "1 sample")
    }

    func testPopupRowModelIncludesUpdatedAtText() throws {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 900)
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
                    displayName: "CPU",
                    valueCelsius: 67,
                    source: .hidSensors
                ),
            ],
            capabilitiesByDomain: [:],
            hottestValidSample: try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 67,
                source: .hidSensors
            )
        )

        let snapshot = TemperatureOverviewSnapshot(liveState: state, settings: .default)
        let row = try XCTUnwrap(snapshot.rows.first(where: { $0.domain == .cpu }))
        let model = MenuBarPopupRowModel(row: row)

        XCTAssertEqual(model.updatedAtText, "Updated: \(row.updatedAtText)")
        XCTAssertNotEqual(model.updatedAtText, "Updated: --")
    }

    func testTrendSegmentsBreakAtGapBoundaries() throws {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 100)
        let series = TemperatureSeries(
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            samples: [
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base,
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 60,
                    source: .hidSensors
                ),
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base.addingTimeInterval(5),
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 62,
                    source: .hidSensors
                ),
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base.addingTimeInterval(20),
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 68,
                    source: .hidSensors
                ),
            ],
            gaps: [
                TimelineEvent(
                    id: UUID(),
                    sessionID: sessionID,
                    eventType: .systemSleepStarted,
                    startedAt: base.addingTimeInterval(8),
                    endedAt: base.addingTimeInterval(18),
                    domain: .cpu,
                    metricName: TemperatureMetricName.cpuHottest,
                    reasonCode: "sleep",
                    message: "sleep"
                )
            ]
        )

        let segments = TemperatureTrendSegments.segments(for: series)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 2)
        XCTAssertEqual(segments[1].count, 1)
    }

    func testTrendSegmentsSplitAtGapEndBoundary() throws {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 100)
        let series = TemperatureSeries(
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            samples: [
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base,
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 60,
                    source: .hidSensors
                ),
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base.addingTimeInterval(18),
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 62,
                    source: .hidSensors
                ),
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base.addingTimeInterval(20),
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 68,
                    source: .hidSensors
                ),
            ],
            gaps: [
                TimelineEvent(
                    id: UUID(),
                    sessionID: sessionID,
                    eventType: .systemSleepStarted,
                    startedAt: base.addingTimeInterval(8),
                    endedAt: base.addingTimeInterval(18),
                    domain: .cpu,
                    metricName: TemperatureMetricName.cpuHottest,
                    reasonCode: "sleep",
                    message: "sleep"
                )
            ]
        )

        let segments = TemperatureTrendSegments.segments(for: series)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].map(\.timestamp), [base])
        XCTAssertEqual(segments[1].map(\.timestamp), [base.addingTimeInterval(18), base.addingTimeInterval(20)])
    }

    func testTrendRenderSegmentsExposeStableSeriesIDs() throws {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 200)
        let series = TemperatureSeries(
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            samples: [
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base,
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 60,
                    source: .hidSensors
                ),
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base.addingTimeInterval(5),
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 62,
                    source: .hidSensors
                ),
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base.addingTimeInterval(20),
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: 68,
                    source: .hidSensors
                ),
            ],
            gaps: [
                TimelineEvent(
                    id: UUID(),
                    sessionID: sessionID,
                    eventType: .systemSleepStarted,
                    startedAt: base.addingTimeInterval(8),
                    endedAt: base.addingTimeInterval(18),
                    domain: .cpu,
                    metricName: TemperatureMetricName.cpuHottest,
                    reasonCode: "sleep",
                    message: "sleep"
                )
            ]
        )

        let renderSegments = TemperatureTrendSegments.renderSegments(for: series)

        XCTAssertEqual(renderSegments.map(\.id), ["cpu.temperature.hottest-segment-0", "cpu.temperature.hottest-segment-1"])
        XCTAssertEqual(renderSegments.map(\.samples.count), [2, 1])
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
