import Foundation
import MacWatchCore

public struct AppleSiliconSensorCatalog: Sendable {
    public init() {}

    public func domain(forRawKey rawKey: String) -> TemperatureDomain? {
        if rawKey.hasPrefix("pACC MTR Temp Sensor")
            || rawKey.hasPrefix("eACC MTR Temp Sensor") {
            return .cpu
        }
        if rawKey.hasPrefix("GPU MTR Temp Sensor") {
            return .gpu
        }
        if smcCPUKeySet.contains(rawKey) {
            return .cpu
        }
        if smcGPUKeySet.contains(rawKey) {
            return .gpu
        }
        if smcSSDKeySet.contains(rawKey) {
            return .ssd
        }
        if smcBatteryKeySet.contains(rawKey) {
            return .battery
        }
        if smcSystemKeySet.contains(rawKey) {
            return .system
        }
        return nil
    }

    public func displayName(forRawKey rawKey: String) -> String {
        if let name = exactDisplayNames[rawKey] {
            return name
        }
        if rawKey.hasPrefix("pACC MTR Temp Sensor"), let index = sensorIndex(in: rawKey) {
            return "CPU performance core \(index + 1)"
        }
        if rawKey.hasPrefix("eACC MTR Temp Sensor"), let index = sensorIndex(in: rawKey) {
            return "CPU efficiency core \(index + 1)"
        }
        if rawKey.hasPrefix("PMU tdie"), let index = sensorIndex(in: rawKey) {
            return "Power management unit die \(index)"
        }
        if rawKey.hasPrefix("PMU2 tdie"), let index = sensorIndex(in: rawKey) {
            return "Power management unit die \(index) secondary"
        }
        if rawKey.hasPrefix("GPU MTR Temp Sensor"), let index = sensorIndex(in: rawKey) {
            return "GPU core \(index + 1)"
        }
        return rawKey
    }

    public func smcCPUKeys(for platform: ApplePlatform) -> [String] {
        switch platform {
        case .intel:
            return legacyCPUKeys
        case .m1, .m1Pro, .m1Max, .m1Ultra:
            return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        case .m2, .m2Pro, .m2Max, .m2Ultra:
            return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        case .m3, .m3Pro, .m3Max, .m3Ultra:
            return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        case .m4, .m4Pro, .m4Max, .m4Ultra:
            return ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        case .m5, .m5Pro, .m5Max, .m5Ultra:
            return ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
        }
    }

    public func isCPUHIDKey(_ rawKey: String) -> Bool {
        rawKey.hasPrefix("pACC MTR Temp Sensor")
            || rawKey.hasPrefix("eACC MTR Temp Sensor")
    }

    public func isGPUHIDKey(_ rawKey: String) -> Bool {
        rawKey.hasPrefix("GPU MTR Temp Sensor")
    }

    public func isSSDHIDKey(_ rawKey: String) -> Bool {
        rawKey.hasPrefix("NAND CH")
    }

    public func smcGPUKeys(for platform: ApplePlatform) -> [String] {
        switch platform {
        case .m1, .m1Pro, .m1Max, .m1Ultra:
            return ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
        case .m2, .m2Pro, .m2Max, .m2Ultra:
            return ["Tg0f", "Tg0j"]
        case .m3, .m3Pro, .m3Max, .m3Ultra:
            return ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
        case .m4, .m4Pro, .m4Max, .m4Ultra:
            return ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
        case .m5, .m5Pro, .m5Max, .m5Ultra:
            return ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"]
        default:
            return ["Tg0G", "Tg0H"]
        }
    }

    public func smcSSDKeys() -> [String] {
        ["TH0x"]
    }

    public func smcBatteryKeys() -> [String] {
        ["TB1T", "TB2T"]
    }

    public func smcSystemKeys() -> [String] {
        Self.statsSystemSMCKeys
    }

    public func isStatsTemperatureSMCKey(_ rawKey: String) -> Bool {
        smcCPUKeySet.contains(rawKey)
            || smcGPUKeySet.contains(rawKey)
            || smcSSDKeySet.contains(rawKey)
            || smcBatteryKeySet.contains(rawKey)
            || smcSystemKeySet.contains(rawKey)
            || rawKey.first == "T"
    }

    private func sensorIndex(in rawKey: String) -> Int? {
        let digits = rawKey.reversed().prefix { $0.isNumber }.reversed()
        guard digits.isEmpty == false else {
            return nil
        }
        return Int(String(digits))
    }

    private let exactDisplayNames: [String: String] = [
        "Te05": "CPU efficiency core 1",
        "Te0S": "CPU efficiency core 2",
        "Te09": "CPU efficiency core 3",
        "Te0H": "CPU efficiency core 4",
        "Tp01": "CPU performance core 1",
        "Tp05": "CPU performance core 2",
        "Tp09": "CPU performance core 3",
        "Tp0D": "CPU performance core 4",
        "Tp0V": "CPU performance core 5",
        "Tp0Y": "CPU performance core 6",
        "Tp0b": "CPU performance core 7",
        "Tp0e": "CPU performance core 8",
        "Tg0G": "GPU 1",
        "Tg0H": "GPU 2",
        "Tg1U": "GPU 3",
        "Tg1k": "GPU 4",
        "Tg0K": "GPU 5",
        "Tg0L": "GPU 6",
        "Tg0d": "GPU 7",
        "Tg0e": "GPU 8",
        "Tg0j": "GPU 9",
        "Tg0k": "GPU 10",
        "TH0x": "NAND",
        "TB1T": "Battery 1",
        "TB2T": "Battery 2",
    ]

    private let legacyCPUKeys = ["TC0D", "TC0E", "TC0F", "TC0P", "TC0H"]
    private let smcCPUKeySet: Set<String> = [
        "Te05", "Te09", "Te0H", "Te0S",
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
        "Tp0T", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
        "Te0L", "Te0P", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0a", "Tp0d", "Tp0g", "Tp0m", "Tp0p", "Tp0u", "Tp0y",
        "TC0D", "TC0E", "TC0F", "TC0P", "TC0H",
    ]
    private let smcGPUKeySet: Set<String> = [
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k",
        "Tg05", "Tg0D", "Tg0T", "Tg0f", "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A",
        "Tg0U", "Tg0X", "Tg0g", "Tg1Y", "Tg1c", "Tg1g",
    ]
    private let smcSSDKeySet: Set<String> = [
        "TH0x",
    ]
    private let smcBatteryKeySet: Set<String> = [
        "TB1T", "TB2T",
    ]
    private static let statsSystemSMCKeys: [String] = {
        let wildcardKeys = [
            "TA%P",
            "Th%H",
            "TZ%C",
            "TI%P",
            "TH%A",
            "TH%B",
            "TH%C",
        ].flatMap(Self.expandSMCWildcard)

        return Array(Set(wildcardKeys + [
            "Tm0P",
            "Tp0P",
            "TW0P",
            "TL0P",
            "TTLD",
            "TTRD",
            "TN0D",
            "TN0H",
            "TN0P",
            "TaLP",
            "TaRF",
        ])).sorted()
    }()
    private static let statsSystemSMCKeySet: Set<String> = Set(statsSystemSMCKeys)

    private var smcSystemKeySet: Set<String> {
        Self.statsSystemSMCKeySet
    }

    private static func expandSMCWildcard(_ pattern: String) -> [String] {
        guard pattern.contains("%") else {
            return [pattern]
        }
        return (0...9).map { pattern.replacingOccurrences(of: "%", with: "\($0)") }
    }
}
