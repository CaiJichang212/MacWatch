public final class AppLifecycleCoordinator: AppLifecycleEventSink {
    public private(set) var events: [AppLifecycleEvent] = []

    public init() {}

    public func record(_ event: AppLifecycleEvent) {
        events.append(event)
    }
}
