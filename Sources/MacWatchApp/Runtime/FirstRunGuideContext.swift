import Foundation
import StatsAdapter

struct FirstRunGuideContext {
    private static let knownMacBookAirModelIdentifiers: Set<String> = [
        "MacBookAir10,1",
        "Mac14,2",
        "Mac14,15",
        "Mac15,12",
        "Mac15,13",
        "Mac16,12",
        "Mac16,13",
        "Mac17,3",
        "Mac17,4",
    ]

    let modelIdentifier: String?
    let chipName: String?
    let isAppleSilicon: Bool
    let isMacBookAir: Bool

    var isSupportedTargetMachine: Bool {
        isAppleSilicon && isMacBookAir
    }

    var displayModel: String {
        modelIdentifier ?? "未知"
    }

    var displayChip: String {
        chipName ?? "未知"
    }

    var supportMessage: String {
        if isSupportedTargetMachine {
            return "当前设备在 MVP 覆盖范围内。"
        }

        if isAppleSilicon {
            return "未识别为 MacBook Air（M 系列）。MVP 默认只保证 MacBook Air 系列。"
        }

        return "当前非 Apple Silicon。MVP 默认面向 Apple Silicon 的 MacBook Air。"
    }

    static func detect() -> FirstRunGuideContext {
        let detector = ApplePlatformDetector()
        let modelIdentifier = detector.currentModelIdentifier()
        return FirstRunGuideContext(
            modelIdentifier: modelIdentifier,
            chipName: detector.currentChipName(),
            isAppleSilicon: detector.isAppleSilicon,
            isMacBookAir: isMacBookAirModelIdentifier(modelIdentifier)
        )
    }

    static func isMacBookAirModelIdentifier(_ modelIdentifier: String?) -> Bool {
        guard let modelIdentifier else {
            return false
        }

        if modelIdentifier.localizedCaseInsensitiveContains("MacBookAir") {
            return true
        }

        return knownMacBookAirModelIdentifiers.contains(modelIdentifier)
    }
}
