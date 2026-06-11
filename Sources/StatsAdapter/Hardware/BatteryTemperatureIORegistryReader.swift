import Foundation
import IOKit

public struct BatteryTemperatureReading: Equatable, Sendable {
    public let valueCelsius: Double
    public let ioRegistryProperty: String
}

public protocol BatteryTemperatureReadingSource: Sendable {
    func hasBatteryService() -> Bool
    func readTemperature() -> BatteryTemperatureReading?
}

public final class BatteryTemperatureIORegistryReader: BatteryTemperatureReadingSource {
    private let serviceName: String
    private let propertyName: String

    public init(
        serviceName: String = "AppleSmartBattery",
        propertyName: String = "Temperature"
    ) {
        self.serviceName = serviceName
        self.propertyName = propertyName
    }

    public func hasBatteryService() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
        guard service != 0 else {
            return false
        }
        IOObjectRelease(service)
        return true
    }

    public func readTemperature() -> BatteryTemperatureReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            propertyName as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        let rawValue: Double?
        if let number = property as? NSNumber {
            rawValue = number.doubleValue
        } else if let value = property as? Double {
            rawValue = value
        } else {
            rawValue = nil
        }

        guard let rawValue else {
            return nil
        }

        return BatteryTemperatureReading(
            valueCelsius: rawValue / 100.0,
            ioRegistryProperty: propertyName
        )
    }
}
