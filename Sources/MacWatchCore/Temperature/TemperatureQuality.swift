public enum TemperatureQuality: String, CaseIterable, Codable, Sendable {
    case valid
    case unsupported
    case readFailed
    case stale
}
