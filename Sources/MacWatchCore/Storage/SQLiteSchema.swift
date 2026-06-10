public struct SQLiteCreateTableStatement: Equatable, Sendable {
    public let tableName: String
    public let columns: [String]
    public let sql: String

    public init(tableName: String, columns: [String], sql: String) {
        self.tableName = tableName
        self.columns = columns
        self.sql = sql
    }
}

public struct SQLiteCreateIndexStatement: Equatable, Sendable {
    public let indexName: String
    public let sql: String

    public init(indexName: String, sql: String) {
        self.indexName = indexName
        self.sql = sql
    }
}

public enum SQLiteSchema {
    public static let version = 1

    public static let allCreateTableStatements: [SQLiteCreateTableStatement] = [
        SQLiteCreateTableStatement(
            tableName: "monitoring_session",
            columns: [
                "id",
                "started_at_ms",
                "ended_at_ms",
                "app_version",
                "model",
                "chip",
                "os_version",
                "created_at_ms",
            ],
            sql: """
            CREATE TABLE IF NOT EXISTS monitoring_session (
                id TEXT PRIMARY KEY,
                started_at_ms INTEGER NOT NULL,
                ended_at_ms INTEGER,
                app_version TEXT,
                model TEXT,
                chip TEXT,
                os_version TEXT,
                created_at_ms INTEGER NOT NULL
            );
            """
        ),
        SQLiteCreateTableStatement(
            tableName: "temperature_sample",
            columns: [
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
            ],
            sql: """
            CREATE TABLE IF NOT EXISTS temperature_sample (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                timestamp_ms INTEGER NOT NULL,
                metric_name TEXT NOT NULL,
                domain TEXT NOT NULL,
                device_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                value_celsius REAL,
                source TEXT NOT NULL,
                quality TEXT NOT NULL,
                raw_key TEXT,
                error_code TEXT,
                attributes_json TEXT,
                created_at_ms INTEGER NOT NULL,
                FOREIGN KEY(session_id) REFERENCES monitoring_session(id)
            );
            """
        ),
        SQLiteCreateTableStatement(
            tableName: "temperature_capability",
            columns: [
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
            ],
            sql: """
            CREATE TABLE IF NOT EXISTS temperature_capability (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                domain TEXT NOT NULL,
                source TEXT NOT NULL,
                supported INTEGER NOT NULL,
                readable INTEGER NOT NULL,
                reason_code TEXT NOT NULL,
                reason_message TEXT NOT NULL,
                raw_key TEXT,
                detected_at_ms INTEGER NOT NULL,
                updated_at_ms INTEGER NOT NULL,
                FOREIGN KEY(session_id) REFERENCES monitoring_session(id)
            );
            """
        ),
        SQLiteCreateTableStatement(
            tableName: "timeline_event",
            columns: [
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
            ],
            sql: """
            CREATE TABLE IF NOT EXISTS timeline_event (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                started_at_ms INTEGER NOT NULL,
                ended_at_ms INTEGER,
                domain TEXT,
                metric_name TEXT,
                reason_code TEXT,
                message TEXT,
                created_at_ms INTEGER NOT NULL,
                FOREIGN KEY(session_id) REFERENCES monitoring_session(id)
            );
            """
        ),
    ]

    public static let allCreateIndexStatements: [SQLiteCreateIndexStatement] = [
        SQLiteCreateIndexStatement(
            indexName: "idx_temperature_sample_session_metric_time",
            sql: """
            CREATE INDEX IF NOT EXISTS idx_temperature_sample_session_metric_time
            ON temperature_sample(session_id, metric_name, timestamp_ms);
            """
        ),
        SQLiteCreateIndexStatement(
            indexName: "idx_temperature_sample_session_domain_time",
            sql: """
            CREATE INDEX IF NOT EXISTS idx_temperature_sample_session_domain_time
            ON temperature_sample(session_id, domain, timestamp_ms);
            """
        ),
        SQLiteCreateIndexStatement(
            indexName: "idx_temperature_capability_session_domain",
            sql: """
            CREATE INDEX IF NOT EXISTS idx_temperature_capability_session_domain
            ON temperature_capability(session_id, domain);
            """
        ),
        SQLiteCreateIndexStatement(
            indexName: "idx_timeline_event_session_time",
            sql: """
            CREATE INDEX IF NOT EXISTS idx_timeline_event_session_time
            ON timeline_event(session_id, started_at_ms, ended_at_ms);
            """
        ),
    ]

    public static let createStatements: [String] =
        allCreateTableStatements.map(\.sql) +
        allCreateIndexStatements.map(\.sql)
}
