public enum StatsReadOnlySource: String, CaseIterable, Sendable {
    case hidSensors
    case smcReadOnly
    case batteryIORegistry
    case nvmeSMART
}
