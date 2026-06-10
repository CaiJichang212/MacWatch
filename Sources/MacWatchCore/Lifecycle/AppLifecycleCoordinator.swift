public final class AppLifecycleCoordinator: AppLifecycleEventSink {
    private let handler: ((AppLifecycleEvent) -> Void)?

    public private(set) var events: [AppLifecycleEvent] = []

    public init(handler: ((AppLifecycleEvent) -> Void)? = nil) {
        self.handler = handler
    }

    public func record(_ event: AppLifecycleEvent) {
        events.append(event)
        handler?(event)
    }
}
