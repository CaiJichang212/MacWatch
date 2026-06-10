import Dispatch
import Foundation

@MainActor
final class MainThreadLagMonitor {
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "MacWatch.acceptance.main-thread-lag", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private(set) var maxLagMilliseconds: Double = 0

    init(interval: TimeInterval = 1.0 / 60.0) {
        self.interval = interval
    }

    func start() {
        guard timer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler {
            let scheduled = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                let actual = DispatchTime.now().uptimeNanoseconds
                let lag = max(0, Double(actual - scheduled) / 1_000_000)
                if lag > self.maxLagMilliseconds {
                    self.maxLagMilliseconds = lag
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() -> Double {
        timer?.cancel()
        timer = nil
        return maxLagMilliseconds
    }
}
