import Foundation
@testable import MacWatchApp
import StatsAdapter
import XCTest

final class AcceptanceCLITests: XCTestCase {
    func testProbeStatusAcceptanceScenarioEmitsStableJSONReport() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL = rootURL
            .appendingPathComponent(".build/arm64-apple-macosx/debug/MacWatchApp")
        let result = try runProcess(
            executable: executableURL.path,
            arguments: [
                "--acceptance-run",
                "probe-status",
            ],
            currentDirectoryURL: rootURL,
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)

        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["scenario"] as? String, "probe-status")
        XCTAssertEqual(json["passed"] as? Bool, true)
        XCTAssertNotNil(json["startedAt"] as? String)
        XCTAssertNotNil(json["durationMs"] as? NSNumber)
        XCTAssertNotNil(json["metrics"] as? [String: Any])
        XCTAssertNotNil(json["failures"] as? [Any])
    }

    func testProbeStatusValidationRejectsMemoryDomain() throws {
        let records = try makeDiagnosticRecords([
            diagnosticJSON(domain: "memory", metricName: "memory.temperature.proximity", quality: "readFailed")
        ] + requiredProbeStatusJSON())

        let result = AcceptanceImmediateRunner.validateProbeStatusRecords(records)

        XCTAssertFalse(result.failures.isEmpty)
        XCTAssertTrue(result.failures.contains("memory.unexpectedDomain"))
        XCTAssertEqual(result.metrics["memory.absent"], "false")
    }

    func testProbeStatusValidationRejectsCPUFromPMUOrSystemRawKey() throws {
        let records = try makeDiagnosticRecords([
            diagnosticJSON(
                domain: "cpu",
                metricName: "cpu.temperature.hottest",
                quality: "valid",
                valueCelsius: 78.0,
                rawKey: "PMU tdie8"
            ),
            diagnosticJSON(
                domain: "cpu",
                metricName: "cpu.temperature.average",
                quality: "valid",
                valueCelsius: 78.0
            ),
        ] + requiredProbeStatusJSON(excluding: ["cpu"]))

        let result = AcceptanceImmediateRunner.validateProbeStatusRecords(records)

        XCTAssertTrue(result.failures.contains("cpu.deniedRawKey.PMU tdie8"))
        XCTAssertEqual(result.metrics["cpu.rawKeyBoundary"], "failed")
    }

    func testProbeStatusValidationRequiresAverageWhenCPUGPUHottestIsValid() throws {
        let records = try makeDiagnosticRecords([
            diagnosticJSON(
                domain: "gpu",
                metricName: "gpu.temperature.hottest",
                quality: "valid",
                valueCelsius: 55.0,
                rawKey: "GPU MTR Temp Sensor0"
            ),
        ] + requiredProbeStatusJSON(excluding: ["gpu"]))

        let result = AcceptanceImmediateRunner.validateProbeStatusRecords(records)

        XCTAssertTrue(result.failures.contains("gpu.averageMissingForValidHottest"))
        XCTAssertEqual(result.metrics["gpu.averagePresentForValidHottest"], "false")
    }
}

private func requiredProbeStatusJSON(excluding excludedDomains: Set<String> = []) -> [String] {
    [
        diagnosticJSON(
            domain: "cpu",
            metricName: "cpu.temperature.hottest",
            quality: "valid",
            valueCelsius: 61.0,
            rawKey: "pACC MTR Temp Sensor0"
        ),
        diagnosticJSON(
            domain: "cpu",
            metricName: "cpu.temperature.average",
            quality: "valid",
            valueCelsius: 58.0
        ),
        diagnosticJSON(
            domain: "gpu",
            metricName: "gpu.temperature.hottest",
            quality: "valid",
            valueCelsius: 55.0,
            rawKey: "GPU MTR Temp Sensor0"
        ),
        diagnosticJSON(
            domain: "gpu",
            metricName: "gpu.temperature.average",
            quality: "valid",
            valueCelsius: 55.0
        ),
        diagnosticJSON(domain: "ssd", metricName: "ssd.temperature.internal", quality: "readFailed"),
        diagnosticJSON(domain: "battery", metricName: "battery.temperature", quality: "readFailed"),
        diagnosticJSON(domain: "system", metricName: "system.temperature.hottest", quality: "readFailed"),
        diagnosticJSON(domain: "sensor", metricName: "sensor.temperature.raw", quality: "readFailed"),
    ].filter { line in
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let domain = object["domain"] as? String else {
            return true
        }
        return excludedDomains.contains(domain) == false
    }
}

private func diagnosticJSON(
    domain: String,
    metricName: String,
    quality: String,
    valueCelsius: Double? = nil,
    rawKey: String? = nil
) -> String {
    var object: [String: Any] = [
        "domain": domain,
        "metricName": metricName,
        "quality": quality,
        "source": "HID Sensors",
        "attributes": [:] as [String: String],
    ]
    object["valueCelsius"] = valueCelsius
    object["rawKey"] = rawKey
    object["errorCode"] = quality == "valid" ? nil : "readFailed"
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}

private func makeDiagnosticRecords(_ lines: [String]) throws -> [TemperatureProbeDiagnosticRecord] {
    let decoder = JSONDecoder()
    return try lines.map { line in
        let data = try XCTUnwrap(line.data(using: .utf8))
        return try decoder.decode(TemperatureProbeDiagnosticRecord.self, from: data)
    }
}
