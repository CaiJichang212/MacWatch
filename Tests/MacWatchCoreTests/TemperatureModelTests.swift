import XCTest
@testable import MacWatchCore

final class TemperatureModelTests: XCTestCase {
    func testTemperatureEnumRawValuesStayStable() {
        XCTAssertEqual(TemperatureDomain.allCases.map(\.rawValue), [
            "cpu",
            "gpu",
            "ssd",
            "battery",
            "system",
            "sensor",
        ])
        XCTAssertEqual(TemperatureSource.allCases.map(\.rawValue), [
            "HID Sensors",
            "SMC",
            "Battery IORegistry",
            "NVMe SMART",
            "IOReport Candidate",
        ])
        XCTAssertEqual(TemperatureQuality.allCases.map(\.rawValue), [
            "valid",
            "unsupported",
            "readFailed",
            "stale",
        ])
    }

    func testValidSamplesRequireTemperatureValue() {
        XCTAssertNoThrow(
            try TemperatureSample.makeValid(
                sessionID: UUID(),
                timestamp: Date(timeIntervalSince1970: 1),
                metricName: "cpu.temperature.hottest",
                domain: .cpu,
                deviceID: "die-0",
                displayName: "CPU Hottest",
                valueCelsius: 42.5,
                source: .hidSensors
            )
        )
        XCTAssertThrowsError(
            try TemperatureSample.makeInvalid(
                sessionID: UUID(),
                timestamp: Date(timeIntervalSince1970: 1),
                metricName: "cpu.temperature.hottest",
                domain: .cpu,
                deviceID: "die-0",
                displayName: "CPU Hottest",
                quality: .valid,
                valueCelsius: nil,
                source: .hidSensors
            )
        ) { error in
            XCTAssertEqual(error as? TemperatureModelError, .invalidSample)
        }
        XCTAssertThrowsError(
            try TemperatureSample.makeInvalid(
                sessionID: UUID(),
                timestamp: Date(timeIntervalSince1970: 1),
                metricName: "cpu.temperature.hottest",
                domain: .cpu,
                deviceID: "die-0",
                displayName: "CPU Hottest",
                quality: .unsupported,
                valueCelsius: 42.5,
                source: .hidSensors
            )
        ) { error in
            XCTAssertEqual(error as? TemperatureModelError, .invalidSample)
        }
    }

    func testValidSamplesRejectOutOfRangeAndNaNTemperatures() {
        for invalidValue in [-1.0, 110.0, Double.nan] {
            XCTAssertThrowsError(
                try TemperatureSample.makeValid(
                    sessionID: UUID(),
                    timestamp: Date(timeIntervalSince1970: 1),
                    metricName: "cpu.temperature.hottest",
                    domain: .cpu,
                    deviceID: "die-0",
                    displayName: "CPU Hottest",
                    valueCelsius: invalidValue,
                    source: .hidSensors
                ),
                "Expected \(invalidValue) to be rejected"
            ) { error in
                XCTAssertEqual(error as? TemperatureModelError, .invalidSample)
            }
        }
    }

    func testQueryRequiresChronologicalRangeAndPositiveMaxPoints() {
        XCTAssertNoThrow(
            try TemperatureQuery(
                sessionID: UUID(),
                domains: [.cpu],
                metricNames: ["cpu.temperature.hottest"],
                start: Date(timeIntervalSince1970: 10),
                end: Date(timeIntervalSince1970: 20),
                maxPoints: 120
            )
        )
        XCTAssertThrowsError(
            try TemperatureQuery(
                sessionID: UUID(),
                domains: [.cpu],
                metricNames: ["cpu.temperature.hottest"],
                start: Date(timeIntervalSince1970: 20),
                end: Date(timeIntervalSince1970: 10),
                maxPoints: 120
            )
        ) { error in
            XCTAssertEqual(error as? TemperatureModelError, .invalidQuery)
        }
        XCTAssertThrowsError(
            try TemperatureQuery(
                sessionID: UUID(),
                domains: [.cpu],
                metricNames: ["cpu.temperature.hottest"],
                start: Date(timeIntervalSince1970: 10),
                end: Date(timeIntervalSince1970: 20),
                maxPoints: 0
            )
        ) { error in
            XCTAssertEqual(error as? TemperatureModelError, .invalidQuery)
        }
    }

    func testTemperatureModelsSupportCodableRoundTrip() throws {
        let sessionID = UUID()
        let detectedAt = Date(timeIntervalSince1970: 30)
        let sample = try TemperatureSample.makeValid(
            id: UUID(),
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: 10),
            metricName: "cpu.temperature.hottest",
            domain: .cpu,
            deviceID: "die-0",
            displayName: "CPU Hottest",
            valueCelsius: 45.25,
            source: .hidSensors,
            rawKey: "Tp09",
            attributes: ["scope": "package"]
        )
        let capability = TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .cpu,
            source: .hidSensors,
            supported: true,
            readable: true,
            reasonCode: "ok",
            reasonMessage: "available",
            rawKey: "Tp09",
            detectedAt: detectedAt,
            updatedAt: detectedAt
        )
        let series = TemperatureSeries(
            metricName: sample.metricName,
            domain: sample.domain,
            samples: [sample],
            gaps: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertEqual(
            try decoder.decode(TemperatureSample.self, from: encoder.encode(sample)),
            sample
        )
        XCTAssertEqual(
            try decoder.decode(TemperatureCapability.self, from: encoder.encode(capability)),
            capability
        )
        XCTAssertEqual(
            try decoder.decode(TemperatureSeries.self, from: encoder.encode(series)),
            series
        )
    }

    func testDecodingRejectsInvalidQualityValueCombination() {
        let data = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "sessionID":"00000000-0000-0000-0000-000000000002",
          "timestamp":"1970-01-01T00:00:10Z",
          "metricName":"cpu.temperature.hottest",
          "domain":"cpu",
          "deviceID":"die-0",
          "displayName":"CPU Hottest",
          "valueCelsius":42.5,
          "source":"HID Sensors",
          "quality":"unsupported",
          "rawKey":"Tp09",
          "errorCode":null,
          "attributes":{"scope":"package"}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertThrowsError(try decoder.decode(TemperatureSample.self, from: data)) { error in
            XCTAssertEqual(error as? TemperatureModelError, .invalidSample)
        }
    }
}
