public enum TemperatureSource: String, CaseIterable, Codable, Sendable {
    case hidSensors = "HID Sensors"
    case smc = "SMC"
    case batteryIORegistry = "Battery IORegistry"
    case nvmeSMART = "NVMe SMART"
    case ioReportCandidate = "IOReport Candidate"
}
