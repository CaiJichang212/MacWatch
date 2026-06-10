import Darwin
import Foundation

public final class ApplePlatformDetector: Sendable {
    public init() {}

    public func detect() -> ApplePlatform? {
        if isAppleSilicon == false {
            return .intel
        }

        guard let chipName = currentChipName() else {
            return nil
        }

        return ApplePlatform(chipName: chipName)
    }

    public func currentChipName() -> String? {
        readStringSysctl("machdep.cpu.brand_string")
    }

    public func currentModelIdentifier() -> String? {
        readStringSysctl("hw.model")
    }

    public var isAppleSilicon: Bool {
        readIntegerSysctl("hw.optional.arm64") == 1
    }

    private func readStringSysctl(_ name: String) -> String? {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: Int(size))
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func readIntegerSysctl(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }
        return value
    }
}
