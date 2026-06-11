public enum TemperatureDomain: String, CaseIterable, Codable, Sendable {
    case cpu
    case gpu
    case ssd
    case battery
    case system
    case sensor
}
