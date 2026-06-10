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
        switch chipName.lowercased() {
        case "apple m1":
            self = .m1
        case "apple m1 pro":
            self = .m1Pro
        case "apple m1 max":
            self = .m1Max
        case "apple m1 ultra":
            self = .m1Ultra
        case "apple m2":
            self = .m2
        case "apple m2 pro":
            self = .m2Pro
        case "apple m2 max":
            self = .m2Max
        case "apple m2 ultra":
            self = .m2Ultra
        case "apple m3":
            self = .m3
        case "apple m3 pro":
            self = .m3Pro
        case "apple m3 max":
            self = .m3Max
        case "apple m3 ultra":
            self = .m3Ultra
        case "apple m4":
            self = .m4
        case "apple m4 pro":
            self = .m4Pro
        case "apple m4 max":
            self = .m4Max
        case "apple m4 ultra":
            self = .m4Ultra
        case "apple m5":
            self = .m5
        case "apple m5 pro":
            self = .m5Pro
        case "apple m5 max":
            self = .m5Max
        case "apple m5 ultra":
            self = .m5Ultra
        default:
            return nil
        }
    }
}
