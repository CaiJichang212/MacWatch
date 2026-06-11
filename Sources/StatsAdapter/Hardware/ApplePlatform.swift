import Foundation

public enum ApplePlatform: String, CaseIterable, Sendable {
    case intel
    case m1
    case m1Pro
    case m1Max
    case m1Ultra
    case m2
    case m2Pro
    case m2Max
    case m2Ultra
    case m3
    case m3Pro
    case m3Max
    case m3Ultra
    case m4
    case m4Pro
    case m4Max
    case m4Ultra
    case m5
    case m5Pro
    case m5Max
    case m5Ultra

    public var generation: Int {
        switch self {
        case .intel:
            return 0
        case .m1, .m1Pro, .m1Max, .m1Ultra:
            return 1
        case .m2, .m2Pro, .m2Max, .m2Ultra:
            return 2
        case .m3, .m3Pro, .m3Max, .m3Ultra:
            return 3
        case .m4, .m4Pro, .m4Max, .m4Ultra:
            return 4
        case .m5, .m5Pro, .m5Max, .m5Ultra:
            return 5
        }
    }
}

public extension ApplePlatform {
    init?(chipName: String) {
        let normalized = chipName
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for (prefix, platform) in Self.chipNamePrefixes {
            if normalized == prefix || normalized.hasPrefix("\(prefix) ") || normalized.hasPrefix("\(prefix)(") {
                self = platform
                return
            }
        }

        return nil
    }

    private static var chipNamePrefixes: [(String, ApplePlatform)] {
        [
            ("apple m1 ultra", .m1Ultra),
            ("apple m1 max", .m1Max),
            ("apple m1 pro", .m1Pro),
            ("apple m1", .m1),
            ("apple m2 ultra", .m2Ultra),
            ("apple m2 max", .m2Max),
            ("apple m2 pro", .m2Pro),
            ("apple m2", .m2),
            ("apple m3 ultra", .m3Ultra),
            ("apple m3 max", .m3Max),
            ("apple m3 pro", .m3Pro),
            ("apple m3", .m3),
            ("apple m4 ultra", .m4Ultra),
            ("apple m4 max", .m4Max),
            ("apple m4 pro", .m4Pro),
            ("apple m4", .m4),
            ("apple m5 ultra", .m5Ultra),
            ("apple m5 max", .m5Max),
            ("apple m5 pro", .m5Pro),
            ("apple m5", .m5),
        ]
    }
}
