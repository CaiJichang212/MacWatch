import Foundation
import IOKit

public protocol SMCValueReading: Sendable {
    func getAllKeys() -> [String]
    func getValue(_ key: String) -> Double?
}

public final class SMCReadOnlyClient: SMCValueReading, @unchecked Sendable {
    private var connection: io_connect_t = 0

    public init() {
        openConnection()
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    public var isAvailable: Bool {
        connection != 0
    }

    public func getAllKeys() -> [String] {
        guard let keyCount = getValue("#KEY") else {
            return []
        }

        var keys: [String] = []
        for index in 0..<Int(keyCount) {
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.data8 = SMCCommand.readIndex.rawValue
            input.data32 = UInt32(index)

            guard performCall(command: .kernelIndex, input: &input, output: &output) == kIOReturnSuccess else {
                continue
            }

            keys.append(output.key.toString())
        }
        return keys
    }

    public func getValue(_ key: String) -> Double? {
        guard let value = readValue(for: key) else {
            return nil
        }

        if value.bytes.contains(where: { $0 != 0 }) == false,
           ["FS! ", "F0Md", "F1Md", "F0md", "F1md"].contains(key) == false {
            return nil
        }

        return decode(value: value)
    }

    private func openConnection() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return
        }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else {
            return
        }
        defer { IOObjectRelease(device) }

        IOServiceOpen(device, mach_task_self_, 0, &connection)
    }

    private func readValue(for key: String) -> SMCValue? {
        guard connection != 0, key.count == 4 else {
            return nil
        }

        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = FourCharCode(fromString: key)
        input.data8 = SMCCommand.readKeyInfo.rawValue
        guard performCall(command: .kernelIndex, input: &input, output: &output) == kIOReturnSuccess else {
            return nil
        }

        let dataSize = output.keyInfo.dataSize
        let dataType = output.keyInfo.dataType
        input.keyInfo.dataSize = dataSize
        input.data8 = SMCCommand.readBytes.rawValue
        guard performCall(command: .kernelIndex, input: &input, output: &output) == kIOReturnSuccess else {
            return nil
        }

        let rawBytes = withUnsafeBytes(of: output.bytes) { buffer in
            Array(buffer.prefix(Int(dataSize)))
        }

        return SMCValue(
            key: key,
            dataSize: UInt32(dataSize),
            dataType: dataType.toString(),
            bytes: rawBytes
        )
    }

    private func decode(value: SMCValue) -> Double? {
        guard value.bytes.isEmpty == false else {
            return nil
        }

        switch value.dataType {
        case SMCDataType.ui8.rawValue:
            return Double(value.bytes[0])
        case SMCDataType.ui16.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes: (value.bytes[0], value.bytes[1])))
        case SMCDataType.ui32.rawValue:
            guard value.bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes: (value.bytes[0], value.bytes[1], value.bytes[2], value.bytes[3])))
        case SMCDataType.sp1e.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 16384
        case SMCDataType.sp3c.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 4096
        case SMCDataType.sp4b.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 2048
        case SMCDataType.sp5a.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 1024
        case SMCDataType.spa5.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 32
        case SMCDataType.sp69.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 512
        case SMCDataType.sp78.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 256
        case SMCDataType.sp87.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 128
        case SMCDataType.sp96.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 64
        case SMCDataType.spb4.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 16
        case SMCDataType.spf0.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1]))
        case SMCDataType.flt.rawValue:
            guard value.bytes.count >= 4 else { return nil }
            return value.bytes.withUnsafeBytes { rawBuffer in
                Double(rawBuffer.load(as: Float.self))
            }
        case SMCDataType.fpe2.rawValue:
            guard value.bytes.count >= 2 else { return nil }
            return Double(Int(fromFPE2: (value.bytes[0], value.bytes[1])))
        default:
            return nil
        }
    }

    private func performCall(
        command: SMCCommand,
        input: inout SMCKeyData,
        output: inout SMCKeyData
    ) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        return IOConnectCallStructMethod(
            connection,
            UInt32(command.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }
}

private enum SMCDataType: String {
    case ui8 = "ui8 "
    case ui16 = "ui16"
    case ui32 = "ui32"
    case sp1e = "sp1e"
    case sp3c = "sp3c"
    case sp4b = "sp4b"
    case sp5a = "sp5a"
    case spa5 = "spa5"
    case sp69 = "sp69"
    case sp78 = "sp78"
    case sp87 = "sp87"
    case sp96 = "sp96"
    case spb4 = "spb4"
    case spf0 = "spf0"
    case flt = "flt "
    case fpe2 = "fpe2"
}

private enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readIndex = 8
    case readKeyInfo = 9
}

private struct SMCKeyData {
    typealias ByteTuple = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var limits = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: ByteTuple = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

private struct SMCValue {
    let key: String
    let dataSize: UInt32
    let dataType: String
    let bytes: [UInt8]
}

private extension FourCharCode {
    init(fromString string: String) {
        precondition(string.count == 4)
        self = string.utf8.reduce(0) { partialResult, character in
            (partialResult << 8) | UInt32(character)
        }
    }

    func toString() -> String {
        String(describing: UnicodeScalar(self >> 24 & 0xff)!)
            + String(describing: UnicodeScalar(self >> 16 & 0xff)!)
            + String(describing: UnicodeScalar(self >> 8 & 0xff)!)
            + String(describing: UnicodeScalar(self & 0xff)!)
    }
}

private extension UInt16 {
    init(bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
    }
}

private extension UInt32 {
    init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
    }
}

private extension Int {
    init(fromFPE2 bytes: (UInt8, UInt8)) {
        self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
    }
}
