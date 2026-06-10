import XCTest
@testable import MacWatchCore

final class SQLiteSchemaTests: XCTestCase {
    func testSchemaVersionIsLocked() {
        XCTAssertEqual(SQLiteSchema.version, 1)
    }

    func testSchemaDefinesExpectedTablesAndColumns() {
        let tables = Dictionary(uniqueKeysWithValues: SQLiteSchema.allCreateTableStatements.map {
            ($0.tableName, $0.columns)
        })

        XCTAssertEqual(Set(tables.keys), [
            "monitoring_session",
            "temperature_sample",
            "temperature_capability",
            "timeline_event",
        ])
        XCTAssertEqual(tables["monitoring_session"], [
            "id",
            "started_at_ms",
            "ended_at_ms",
            "app_version",
            "model",
            "chip",
            "os_version",
            "created_at_ms",
        ])
        XCTAssertEqual(tables["temperature_sample"], [
            "id",
            "session_id",
            "timestamp_ms",
            "metric_name",
            "domain",
            "device_id",
            "display_name",
            "value_celsius",
            "source",
            "quality",
            "raw_key",
            "error_code",
            "attributes_json",
            "created_at_ms",
        ])
        XCTAssertEqual(tables["temperature_capability"], [
            "id",
            "session_id",
            "domain",
            "source",
            "supported",
            "readable",
            "reason_code",
            "reason_message",
            "raw_key",
            "detected_at_ms",
            "updated_at_ms",
        ])
        XCTAssertEqual(tables["timeline_event"], [
            "id",
            "session_id",
            "event_type",
            "started_at_ms",
            "ended_at_ms",
            "domain",
            "metric_name",
            "reason_code",
            "message",
            "created_at_ms",
        ])
    }

    func testSchemaDefinesExpectedIndexes() {
        let indexNames = Set(SQLiteSchema.allCreateIndexStatements.map(\.indexName))

        XCTAssertEqual(indexNames, [
            "idx_temperature_sample_session_metric_time",
            "idx_temperature_sample_session_domain_time",
            "idx_temperature_capability_session_domain",
            "idx_timeline_event_session_time",
        ])
        XCTAssertEqual(SQLiteSchema.createStatements.count, 8)
    }

    func testSchemaSQLBuildsExpectedSQLiteStructure() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")

        try runSQLite(arguments: [databaseURL.path(percentEncoded: false)] + SQLiteSchema.createStatements)

        XCTAssertEqual(
            try pragmaRows(name: "table_info", target: "temperature_sample", databaseURL: databaseURL)
                .map { $0[1] },
            [
                "id",
                "session_id",
                "timestamp_ms",
                "metric_name",
                "domain",
                "device_id",
                "display_name",
                "value_celsius",
                "source",
                "quality",
                "raw_key",
                "error_code",
                "attributes_json",
                "created_at_ms",
            ]
        )
        XCTAssertEqual(
            Set(try pragmaRows(name: "index_list", target: "temperature_sample", databaseURL: databaseURL).map { $0[1] }),
            [
                "idx_temperature_sample_session_metric_time",
                "idx_temperature_sample_session_domain_time",
                "sqlite_autoindex_temperature_sample_1",
            ]
        )
    }

    private func pragmaRows(
        name: String,
        target: String,
        databaseURL: URL
    ) throws -> [[String]] {
        let output = try runSQLite(
            arguments: [
                "-csv",
                databaseURL.path(percentEncoded: false),
                "PRAGMA \(name)(\(target));",
            ]
        )

        return output
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            }
    }

    @discardableResult
    private func runSQLite(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
        return output
    }
}
