public enum AppLifecycleEvent: Equatable, Sendable {
    case launched
    case willSleep
    case didWake
    case willTerminate
}

public protocol AppLifecycleEventSink: AnyObject {
    func record(_ event: AppLifecycleEvent)
}
