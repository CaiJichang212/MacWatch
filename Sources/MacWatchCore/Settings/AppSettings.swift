public struct AppSettings: Equatable, Sendable {
    public var launchMainWindowOnStart: Bool

    public init(launchMainWindowOnStart: Bool) {
        self.launchMainWindowOnStart = launchMainWindowOnStart
    }
}

public extension AppSettings {
    static let `default` = AppSettings(launchMainWindowOnStart: true)
}
