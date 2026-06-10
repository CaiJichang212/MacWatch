import MacWatchCore
import StatsAdapter

@main
struct MacWatchAppBootstrap {
    static func main() {
        _ = AppSettings.default
        _ = StatsAdapterBoundary.placeholder
    }
}
