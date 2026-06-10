import Foundation
import IOKit

public struct IOAcceleratorTemperatureReading: Equatable, Sendable {
    public let valueCelsius: Double
    public let statisticsField: String
}

public protocol IOAcceleratorTemperatureReadingSource: Sendable {
    func readTemperature() -> IOAcceleratorTemperatureReading?
}

public final class IOAcceleratorTemperatureReader: IOAcceleratorTemperatureReadingSource {
    public init() {}

    public func readTemperature() -> IOAcceleratorTemperatureReading? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                service,
                &properties,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any],
            let statistics = dictionary["PerformanceStatistics"] as? [String: Any] else {
                continue
            }

            if let number = statistics["Temperature(C)"] as? NSNumber {
                return IOAcceleratorTemperatureReading(
                    valueCelsius: number.doubleValue,
                    statisticsField: "Temperature(C)"
                )
            }
        }

        return nil
    }
}
