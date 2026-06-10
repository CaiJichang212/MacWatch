import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteSessionHistoryStore: SessionHistoryStore {
    private let databaseURL: URL
    private let lock = NSLock()
    private var database: OpaquePointer?

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public func initialize() throws {
        try withDatabase { database in
            try exec("PRAGMA foreign_keys = ON;", database: database)
            for statement in SQLiteSchema.createStatements {
                try exec(statement, database: database)
            }
        }
    }

    public func replaceWithNewSession(_ session: MonitoringSession) throws {
        try withTransaction { database in
            try exec("DELETE FROM temperature_sample;", database: database)
            try exec("DELETE FROM temperature_capability;", database: database)
            try exec("DELETE FROM timeline_event;", database: database)
            try exec("DELETE FROM monitoring_session;", database: database)

            let sql = """
            INSERT INTO monitoring_session (
                id, started_at_ms, ended_at_ms, app_version, model, chip, os_version, created_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            try prepareAndStep(sql, database: database) { statement in
                bindText(session.id.uuidString, at: 1, statement: statement)
                bindInt64(milliseconds(session.startedAt), at: 2, statement: statement)
                bindNullableInt64(session.endedAt.map(milliseconds), at: 3, statement: statement)
                bindNullableText(session.appVersion, at: 4, statement: statement)
                bindNullableText(session.model, at: 5, statement: statement)
                bindNullableText(session.chip, at: 6, statement: statement)
                bindNullableText(session.osVersion, at: 7, statement: statement)
                bindInt64(milliseconds(session.startedAt), at: 8, statement: statement)
            }
        }
    }

    public func currentSession() throws -> MonitoringSession? {
        try withDatabase { database in
            let sql = """
            SELECT id, started_at_ms, ended_at_ms, app_version, model, chip, os_version
            FROM monitoring_session
            ORDER BY created_at_ms DESC
            LIMIT 1;
            """
            var statement: OpaquePointer?
            try prepare(sql, database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            return try decodeSession(statement: statement)
        }
    }

    public func endSession(id: UUID, endedAt: Date) throws {
        try withDatabase { database in
            let sql = "UPDATE monitoring_session SET ended_at_ms = ? WHERE id = ?;"
            try prepareAndStep(sql, database: database) { statement in
                bindInt64(milliseconds(endedAt), at: 1, statement: statement)
                bindText(id.uuidString, at: 2, statement: statement)
            }
        }
    }

    public func insertSample(_ sample: TemperatureSample) throws {
        try withDatabase { database in
            let sql = """
            INSERT INTO temperature_sample (
                id, session_id, timestamp_ms, metric_name, domain, device_id, display_name,
                value_celsius, source, quality, raw_key, error_code, attributes_json, created_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            try prepareAndStep(sql, database: database) { statement in
                bindText(sample.id.uuidString, at: 1, statement: statement)
                bindText(sample.sessionID.uuidString, at: 2, statement: statement)
                bindInt64(milliseconds(sample.timestamp), at: 3, statement: statement)
                bindText(sample.metricName, at: 4, statement: statement)
                bindText(sample.domain.rawValue, at: 5, statement: statement)
                bindText(sample.deviceID, at: 6, statement: statement)
                bindText(sample.displayName, at: 7, statement: statement)
                bindNullableDouble(sample.valueCelsius, at: 8, statement: statement)
                bindText(sample.source.rawValue, at: 9, statement: statement)
                bindText(sample.quality.rawValue, at: 10, statement: statement)
                bindNullableText(sample.rawKey, at: 11, statement: statement)
                bindNullableText(sample.errorCode, at: 12, statement: statement)
                bindText(encodeAttributes(sample.attributes), at: 13, statement: statement)
                bindInt64(milliseconds(sample.timestamp), at: 14, statement: statement)
            }
        }
    }

    public func insertCapability(_ capability: TemperatureCapability) throws {
        try withDatabase { database in
            let sql = """
            INSERT INTO temperature_capability (
                id, session_id, domain, source, supported, readable, reason_code,
                reason_message, raw_key, detected_at_ms, updated_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            try prepareAndStep(sql, database: database) { statement in
                bindText(capability.id.uuidString, at: 1, statement: statement)
                bindText(capability.sessionID.uuidString, at: 2, statement: statement)
                bindText(capability.domain.rawValue, at: 3, statement: statement)
                bindText(capability.source.rawValue, at: 4, statement: statement)
                bindInt64(capability.supported ? 1 : 0, at: 5, statement: statement)
                bindInt64(capability.readable ? 1 : 0, at: 6, statement: statement)
                bindText(capability.reasonCode, at: 7, statement: statement)
                bindText(capability.reasonMessage, at: 8, statement: statement)
                bindNullableText(capability.rawKey, at: 9, statement: statement)
                bindInt64(milliseconds(capability.detectedAt), at: 10, statement: statement)
                bindInt64(milliseconds(capability.updatedAt), at: 11, statement: statement)
            }
        }
    }

    public func insertTimelineEvent(_ event: TimelineEvent) throws {
        try withDatabase { database in
            let sql = """
            INSERT INTO timeline_event (
                id, session_id, event_type, started_at_ms, ended_at_ms, domain,
                metric_name, reason_code, message, created_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            try prepareAndStep(sql, database: database) { statement in
                bindText(event.id.uuidString, at: 1, statement: statement)
                bindText(event.sessionID.uuidString, at: 2, statement: statement)
                bindText(event.eventType.rawValue, at: 3, statement: statement)
                bindInt64(milliseconds(event.startedAt), at: 4, statement: statement)
                bindNullableInt64(event.endedAt.map(milliseconds), at: 5, statement: statement)
                bindNullableText(event.domain?.rawValue, at: 6, statement: statement)
                bindNullableText(event.metricName, at: 7, statement: statement)
                bindNullableText(event.reasonCode, at: 8, statement: statement)
                bindNullableText(event.message, at: 9, statement: statement)
                bindInt64(milliseconds(event.startedAt), at: 10, statement: statement)
            }
        }
    }

    public func updateTimelineEvent(id: UUID, endedAt: Date) throws {
        try withDatabase { database in
            let sql = "UPDATE timeline_event SET ended_at_ms = ? WHERE id = ?;"
            try prepareAndStep(sql, database: database) { statement in
                bindInt64(milliseconds(endedAt), at: 1, statement: statement)
                bindText(id.uuidString, at: 2, statement: statement)
            }
        }
    }

    public func samples(matching query: TemperatureQuery) throws -> [TemperatureSample] {
        try withDatabase { database in
            var arguments: [BindableValue] = [
                .text(query.sessionID.uuidString),
                .int(milliseconds(query.start)),
                .int(milliseconds(query.end)),
            ]
            var sql = """
            SELECT id, session_id, timestamp_ms, metric_name, domain, device_id, display_name,
                   value_celsius, source, quality, raw_key, error_code, attributes_json
            FROM temperature_sample
            WHERE session_id = ?
              AND timestamp_ms >= ?
              AND timestamp_ms <= ?
            """

            sql += " AND domain IN (\(placeholders(count: query.domains.count)))"
            arguments.append(contentsOf: query.domains.map { .text($0.rawValue) })

            if let metricNames = query.metricNames, metricNames.isEmpty == false {
                sql += " AND metric_name IN (\(placeholders(count: metricNames.count)))"
                arguments.append(contentsOf: metricNames.map(BindableValue.text))
            }

            sql += " ORDER BY timestamp_ms ASC, id ASC;"

            var statement: OpaquePointer?
            try prepare(sql, database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }
            try bind(arguments, to: statement)

            var rows: [TemperatureSample] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(try decodeSample(statement: statement))
            }
            try ensureDone(statement: statement, database: database)
            return rows
        }
    }

    public func timelineEvents(sessionID: UUID, start: Date, end: Date) throws -> [TimelineEvent] {
        try withDatabase { database in
            let sql = """
            SELECT id, session_id, event_type, started_at_ms, ended_at_ms, domain,
                   metric_name, reason_code, message
            FROM timeline_event
            WHERE session_id = ?
              AND started_at_ms <= ?
              AND COALESCE(ended_at_ms, started_at_ms) >= ?
            ORDER BY started_at_ms ASC, id ASC;
            """
            var statement: OpaquePointer?
            try prepare(sql, database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }
            try bind([
                .text(sessionID.uuidString),
                .int(milliseconds(end)),
                .int(milliseconds(start)),
            ], to: statement)

            var events: [TimelineEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                events.append(try decodeTimelineEvent(statement: statement))
            }
            try ensureDone(statement: statement, database: database)
            return events
        }
    }

    public func clearHistory(sessionID: UUID, clearedAt: Date) throws {
        try withTransaction { database in
            let sessionIDText = sessionID.uuidString
            try prepareAndStep("DELETE FROM temperature_sample WHERE session_id = ?;", database: database) { statement in
                bindText(sessionIDText, at: 1, statement: statement)
            }
            try prepareAndStep("DELETE FROM temperature_capability WHERE session_id = ?;", database: database) { statement in
                bindText(sessionIDText, at: 1, statement: statement)
            }
            try prepareAndStep("DELETE FROM timeline_event WHERE session_id = ?;", database: database) { statement in
                bindText(sessionIDText, at: 1, statement: statement)
            }

            try prepareAndStep(
                """
                INSERT INTO timeline_event (
                    id, session_id, event_type, started_at_ms, ended_at_ms, domain,
                    metric_name, reason_code, message, created_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                database: database
            ) { statement in
                bindText(UUID().uuidString, at: 1, statement: statement)
                bindText(sessionIDText, at: 2, statement: statement)
                bindText(TimelineEventType.historyCleared.rawValue, at: 3, statement: statement)
                bindInt64(milliseconds(clearedAt), at: 4, statement: statement)
                bindInt64(milliseconds(clearedAt), at: 5, statement: statement)
                bindNull(at: 6, statement: statement)
                bindNull(at: 7, statement: statement)
                bindText("historyCleared", at: 8, statement: statement)
                bindText("history cleared", at: 9, statement: statement)
                bindInt64(milliseconds(clearedAt), at: 10, statement: statement)
            }
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try lock.withLock {
            let database = try openIfNeeded()
            return try body(database)
        }
    }

    private func withTransaction(_ body: (OpaquePointer) throws -> Void) throws {
        try withDatabase { database in
            try exec("BEGIN IMMEDIATE;", database: database)
            do {
                try body(database)
                try exec("COMMIT;", database: database)
            } catch {
                try? exec("ROLLBACK;", database: database)
                throw error
            }
        }
    }

    private func openIfNeeded() throws -> OpaquePointer {
        if let database {
            return database
        }

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let handle else {
            defer { if let handle { sqlite3_close(handle) } }
            throw makeError(database: handle, fallback: "Failed to open SQLite database.")
        }

        database = handle
        return handle
    }

    private func exec(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw makeError(database: database, fallback: "SQLite exec failed.")
        }
    }

    private func prepare(
        _ sql: String,
        database: OpaquePointer,
        statement: inout OpaquePointer?
    ) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw makeError(database: database, fallback: "SQLite prepare failed.")
        }
    }

    private func prepareAndStep(
        _ sql: String,
        database: OpaquePointer,
        bind: (OpaquePointer) throws -> Void
    ) throws {
        var statement: OpaquePointer?
        try prepare(sql, database: database, statement: &statement)
        defer { sqlite3_finalize(statement) }
        guard let statement else {
            throw makeError(database: database, fallback: "SQLite statement missing.")
        }
        try bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw makeError(database: database, fallback: "SQLite step failed.")
        }
    }

    private func ensureDone(statement: OpaquePointer?, database: OpaquePointer) throws {
        let code = sqlite3_errcode(database)
        if code != SQLITE_OK && code != SQLITE_DONE && code != SQLITE_ROW {
            throw makeError(database: database, fallback: "SQLite read failed.")
        }
        _ = statement
    }

    private func decodeSession(statement: OpaquePointer?) throws -> MonitoringSession {
        MonitoringSession(
            id: try uuid(column: 0, statement: statement),
            startedAt: date(column: 1, statement: statement),
            endedAt: nullableDate(column: 2, statement: statement),
            appVersion: nullableText(column: 3, statement: statement),
            model: nullableText(column: 4, statement: statement),
            chip: nullableText(column: 5, statement: statement),
            osVersion: nullableText(column: 6, statement: statement)
        )
    }

    private func decodeSample(statement: OpaquePointer?) throws -> TemperatureSample {
        let quality = try enumValue(
            rawValue: text(column: 9, statement: statement),
            type: TemperatureQuality.self
        )
        let source = try enumValue(
            rawValue: text(column: 8, statement: statement),
            type: TemperatureSource.self
        )
        let domain = try enumValue(
            rawValue: text(column: 4, statement: statement),
            type: TemperatureDomain.self
        )

        return try TemperatureSample(
            id: uuid(column: 0, statement: statement),
            sessionID: uuid(column: 1, statement: statement),
            timestamp: date(column: 2, statement: statement),
            metricName: text(column: 3, statement: statement),
            domain: domain,
            deviceID: text(column: 5, statement: statement),
            displayName: text(column: 6, statement: statement),
            valueCelsius: nullableDouble(column: 7, statement: statement),
            source: source,
            quality: quality,
            rawKey: nullableText(column: 10, statement: statement),
            errorCode: nullableText(column: 11, statement: statement),
            attributes: decodeAttributes(nullableText(column: 12, statement: statement))
        )
    }

    private func decodeTimelineEvent(statement: OpaquePointer?) throws -> TimelineEvent {
        TimelineEvent(
            id: try uuid(column: 0, statement: statement),
            sessionID: try uuid(column: 1, statement: statement),
            eventType: try enumValue(
                rawValue: text(column: 2, statement: statement),
                type: TimelineEventType.self
            ),
            startedAt: date(column: 3, statement: statement),
            endedAt: nullableDate(column: 4, statement: statement),
            domain: try nullableEnumValue(
                rawValue: nullableText(column: 5, statement: statement),
                type: TemperatureDomain.self
            ),
            metricName: nullableText(column: 6, statement: statement),
            reasonCode: nullableText(column: 7, statement: statement),
            message: nullableText(column: 8, statement: statement)
        )
    }

    private func bind(_ values: [BindableValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let .text(text):
                bindText(text, at: position, statement: statement)
            case let .int(value):
                bindInt64(value, at: position, statement: statement)
            }
        }
    }

    private func bindText(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bindNullableText(_ value: String?, at index: Int32, statement: OpaquePointer?) {
        if let value {
            bindText(value, at: index, statement: statement)
        } else {
            bindNull(at: index, statement: statement)
        }
    }

    private func bindInt64(_ value: Int64, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_int64(statement, index, value)
    }

    private func bindNullableInt64(_ value: Int64?, at index: Int32, statement: OpaquePointer?) {
        if let value {
            bindInt64(value, at: index, statement: statement)
        } else {
            bindNull(at: index, statement: statement)
        }
    }

    private func bindNullableDouble(_ value: Double?, at index: Int32, statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            bindNull(at: index, statement: statement)
        }
    }

    private func bindNull(at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_null(statement, index)
    }

    private func text(column: Int32, statement: OpaquePointer?) -> String {
        String(cString: sqlite3_column_text(statement, column))
    }

    private func nullableText(column: Int32, statement: OpaquePointer?) -> String? {
        guard let value = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: value)
    }

    private func uuid(column: Int32, statement: OpaquePointer?) throws -> UUID {
        guard let uuid = UUID(uuidString: text(column: column, statement: statement)) else {
            throw SQLiteSessionHistoryStoreError.invalidRow("Invalid UUID column \(column).")
        }
        return uuid
    }

    private func date(column: Int32, statement: OpaquePointer?) -> Date {
        Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, column)) / 1_000)
    }

    private func nullableDate(column: Int32, statement: OpaquePointer?) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return date(column: column, statement: statement)
    }

    private func nullableDouble(column: Int32, statement: OpaquePointer?) -> Double? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, column)
    }

    private func encodeAttributes(_ attributes: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(attributes),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func decodeAttributes(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private func placeholders(count: Int) -> String {
        Array(repeating: "?", count: max(count, 1)).joined(separator: ", ")
    }

    private func enumValue<T: RawRepresentable>(
        rawValue: String,
        type: T.Type
    ) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: rawValue) else {
            throw SQLiteSessionHistoryStoreError.invalidRow("Unknown raw value \(rawValue).")
        }
        return value
    }

    private func nullableEnumValue<T: RawRepresentable>(
        rawValue: String?,
        type: T.Type
    ) throws -> T? where T.RawValue == String {
        guard let rawValue else {
            return nil
        }
        return try enumValue(rawValue: rawValue, type: type)
    }

    private func makeError(database: OpaquePointer?, fallback: String) -> SQLiteSessionHistoryStoreError {
        if let database, let message = sqlite3_errmsg(database) {
            return .sqlite(String(cString: message))
        }
        return .sqlite(fallback)
    }
}

public enum SQLiteSessionHistoryStoreError: Error, LocalizedError {
    case sqlite(String)
    case invalidRow(String)

    public var errorDescription: String? {
        switch self {
        case let .sqlite(message), let .invalidRow(message):
            return message
        }
    }
}

private enum BindableValue {
    case text(String)
    case int(Int64)
}
