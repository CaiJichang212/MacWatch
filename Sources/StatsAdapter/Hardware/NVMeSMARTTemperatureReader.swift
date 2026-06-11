import Foundation
import IOKit
import IOKit.storage
import StatsAdapterIOHID

public struct NVMeSMARTTemperatureReading: Equatable, Sendable {
    public let valueCelsius: Double
    public let smartField: String
}

public protocol NVMeSMARTTemperatureReadingSource: Sendable {
    func hasInternalSMARTCapableDisk() -> Bool
    func readInternalTemperature() -> NVMeSMARTTemperatureReading?
}

public final class NVMeSMARTTemperatureReader: NVMeSMARTTemperatureReadingSource {
    public init() {}

    public func hasInternalSMARTCapableDisk() -> Bool {
        guard let service = firstSMARTCapableInternalDisk() else {
            return false
        }
        IOObjectRelease(service)
        return true
    }

    public func readInternalTemperature() -> NVMeSMARTTemperatureReading? {
        guard let service = firstSMARTCapableInternalDisk() else {
            return nil
        }
        defer { IOObjectRelease(service) }

        var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var smartInterface: UnsafeMutablePointer<UnsafeMutablePointer<IONVMeSMARTInterface>?>?
        var score: Int32 = 0

        let createResult = IOCreatePlugInInterfaceForService(
            service,
            nvmeSMARTUserClientTypeID,
            ioCFPluginInterfaceID,
            &pluginInterface,
            &score
        )
        guard createResult == kIOReturnSuccess else {
            return nil
        }
        defer {
            if pluginInterface != nil {
                IODestroyPlugInInterface(pluginInterface)
            }
        }

        let queryResult = withUnsafeMutablePointer(to: &smartInterface) {
            $0.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) {
                pluginInterface?.pointee?.pointee.QueryInterface(
                    pluginInterface,
                    CFUUIDGetUUIDBytes(nvmeSMARTInterfaceID),
                    $0
                ) ?? KERN_FAILURE
            }
        }
        guard queryResult == kIOReturnSuccess,
              let smartInterface = smartInterface,
              let smart = smartInterface.pointee else {
            return nil
        }
        defer {
            _ = pluginInterface?.pointee?.pointee.Release(smartInterface)
        }

        var smartData = nvme_smart_log()
        guard smart.pointee.SMARTReadData(smartInterface, &smartData) == kIOReturnSuccess else {
            return nil
        }

        let kelvin = Double(UInt16(bytes: (smartData.temperature.1, smartData.temperature.0)))
        guard kelvin > 0 else {
            return nil
        }

        return NVMeSMARTTemperatureReading(
            valueCelsius: kelvin - 273.15,
            smartField: "temperature"
        )
    }

    private func firstSMARTCapableInternalDisk() -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(kIOBlockStorageDeviceClass),
            &iterator
        ) == kIOReturnSuccess else {
            return nil
        }

        while case let service = IOIteratorNext(iterator), service != 0 {
            if let isSMARTCapable = IORegistryEntryCreateCFProperty(
                service,
                "NVMe SMART Capable" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? Bool,
               isSMARTCapable == true,
               isInternalService(service) {
                IOObjectRelease(iterator)
                return service
            }

            IOObjectRelease(service)
        }

        IOObjectRelease(iterator)
        return nil
    }

    private func isInternalService(_ service: io_service_t) -> Bool {
        var current: io_registry_entry_t = service
        var shouldReleaseCurrent = false

        while current != 0 {
            if let properties = copyProperties(for: current),
               Self.isInternalDisk(properties: properties) {
                if shouldReleaseCurrent {
                    IOObjectRelease(current)
                }
                return true
            }

            var parent: io_registry_entry_t = 0
            let parentResult = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if shouldReleaseCurrent {
                IOObjectRelease(current)
            }

            guard parentResult == kIOReturnSuccess, parent != 0 else {
                return false
            }

            current = parent
            shouldReleaseCurrent = true
        }

        return false
    }

    private func copyProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &properties,
            kCFAllocatorDefault,
            0
        ) == kIOReturnSuccess else {
            return nil
        }

        return properties?.takeRetainedValue() as? [String: Any]
    }

    static func isInternalDisk(properties: [String: Any]) -> Bool {
        if let isInternal = boolValue(properties["Internal"]) {
            return isInternal
        }

        if let location = properties["Physical Interconnect Location"] as? String {
            return location.caseInsensitiveCompare("Internal") == .orderedSame
        }

        return false
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }
}

private let nvmeSMARTUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(
    nil,
    0xAA, 0x0F, 0xA6, 0xF9,
    0xC2, 0xD6, 0x45, 0x7F,
    0xB1, 0x0B, 0x59, 0xA1,
    0x32, 0x53, 0x29, 0x2F
)

private let nvmeSMARTInterfaceID = CFUUIDGetConstantUUIDWithBytes(
    nil,
    0xCC, 0xD1, 0xDB, 0x19,
    0xFD, 0x9A, 0x4D, 0xAF,
    0xBF, 0x95, 0x12, 0x45,
    0x4B, 0x23, 0x0A, 0xB6
)

private let ioCFPluginInterfaceID = CFUUIDGetConstantUUIDWithBytes(
    nil,
    0xC2, 0x44, 0xE8, 0x58,
    0x10, 0x9C, 0x11, 0xD4,
    0x91, 0xD4, 0x00, 0x50,
    0xE4, 0xC6, 0x42, 0x6F
)

private extension UInt16 {
    init(bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
    }
}
