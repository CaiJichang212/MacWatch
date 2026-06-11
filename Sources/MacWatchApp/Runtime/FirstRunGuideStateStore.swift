import Foundation

struct FirstRunGuideStateStore {
    private static let storageKey = "MacWatch.firstRunGuide.hasCompleted"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldShowFirstRunGuide() -> Bool {
        defaults.bool(forKey: Self.storageKey) == false
    }

    func markFirstRunGuideCompleted() {
        defaults.set(true, forKey: Self.storageKey)
    }
}
