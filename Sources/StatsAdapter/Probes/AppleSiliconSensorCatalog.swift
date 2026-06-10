import Foundation
import MacWatchCore

public struct AppleSiliconSensorCatalog: Sendable {
    public init() {}

    public func domain(forRawKey rawKey: String) -> TemperatureDomain? {
        if rawKey.hasPrefix("pACC MTR Temp Sensor")
            || rawKey.hasPrefix("eACC MTR Temp Sensor")
            || rawKey.hasPrefix("PMU tdie")
            || rawKey.hasPrefix("PMU2 tdie") {
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
        if smcMemoryKeySet.contains(rawKey) {
            return .memory
        }
        if smcSSDKeySet.contains(rawKey) {
            return .ssd
        }
        if smcBatteryKeySet.contains(rawKey) {
            return .battery
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
            return "CPU die sensor \(index)"
        }
        if rawKey.hasPrefix("PMU2 tdie"), let index = sensorIndex(in: rawKey) {
            return "CPU die sensor \(index) secondary"
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
            return ["Tp09", "Tp01", "Tp05", "Tp0D", "Tp0b"]
        case .m2, .m2Pro, .m2Max, .m2Ultra:
            return ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0b"]
        case .m3, .m3Pro, .m3Max, .m3Ultra:
            return ["Te05", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D"]
        case .m4, .m4Pro, .m4Max, .m4Ultra:
            return ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        case .m5, .m5Pro, .m5Max, .m5Ultra:
            return ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        }
    }

    public func isCPUHIDKey(_ rawKey: String) -> Bool {
        rawKey.hasPrefix("pACC MTR Temp Sensor")
            || rawKey.hasPrefix("eACC MTR Temp Sensor")
            || rawKey.hasPrefix("PMU tdie")
            || rawKey.hasPrefix("PMU2 tdie")
    }

    public func isGPUHIDKey(_ rawKey: String) -> Bool {
        rawKey.hasPrefix("GPU MTR Temp Sensor")
    }

    public func isSSDHIDKey(_ rawKey: String) -> Bool {
        rawKey.hasPrefix("NAND CH")
    }

    public func smcGPUKeys(for platform: ApplePlatform) -> [String] {
        switch platform {
        case .m4, .m4Pro, .m4Max, .m4Ultra:
            return ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
        default:
            return ["Tg0G", "Tg0H"]
        }
    }

    public func smcMemoryKeys(for platform: ApplePlatform) -> [String] {
        switch platform {
        case .m1, .m1Pro, .m1Max, .m1Ultra:
            return ["Tm02", "Tm06", "Tm08", "Tm09"]
        case .m4, .m4Pro, .m4Max, .m4Ultra, .m5, .m5Pro, .m5Max, .m5Ultra:
            return ["Tm0p", "Tm1p", "Tm2p"]
        default:
            return ["Tm0p", "Tm1p", "Tm2p"]
        }
    }

    public func smcSSDKeys() -> [String] {
        ["TH0x"]
    }

    public func smcBatteryKeys() -> [String] {
        ["TB1T", "TB2T"]
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
        "Tm0p": "Memory Proximity 1",
        "Tm1p": "Memory Proximity 2",
        "Tm2p": "Memory Proximity 3",
        "TH0x": "NAND",
        "TB1T": "Battery 1",
        "TB2T": "Battery 2",
    ]

    private let legacyCPUKeys = ["TC0D", "TC0E", "TC0F", "TC0P", "TC0H"]
    private let smcCPUKeySet: Set<String> = [
        "Te05", "Te09", "Te0H", "Te0S",
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
        "TC0D", "TC0E", "TC0F", "TC0P", "TC0H",
    ]
    private let smcGPUKeySet: Set<String> = [
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k",
    ]
    private let smcMemoryKeySet: Set<String> = [
        "Tm0p", "Tm1p", "Tm2p", "Tm02", "Tm06", "Tm08", "Tm09",
    ]
    private let smcSSDKeySet: Set<String> = [
        "TH0x",
    ]
    private let smcBatteryKeySet: Set<String> = [
        "TB1T", "TB2T",
    ]
}
