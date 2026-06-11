import Foundation
import MacWatchCore

enum MainWindowRoute: Hashable {
    case dashboard
    case compatibility
    case detail(TemperatureDomain)
}

final class WindowCommandCenter {
    static let shared = WindowCommandCenter()

    private var openMainWindowAction: (() -> Void)?
    private var navigateAction: ((MainWindowRoute) -> Void)?
    private var pendingRoute: MainWindowRoute?
    private var openMainWindowInvocationCounter = 0
    private let lock = NSLock()

    func registerOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action

        if let pendingRoute {
            openMainWindowAction?()
            if let navigateAction {
                navigateAction(pendingRoute)
                self.pendingRoute = nil
            }
        }
    }

    func registerNavigationAction(_ action: @escaping (MainWindowRoute) -> Void) {
        navigateAction = action
        if let pendingRoute {
            self.pendingRoute = nil
            action(pendingRoute)
        }
    }

    var openMainWindowInvocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return openMainWindowInvocationCounter
    }

    func openMainWindow(route: MainWindowRoute = .dashboard) {
        lock.lock()
        openMainWindowInvocationCounter += 1
        lock.unlock()

        pendingRoute = route
        openMainWindowAction?()
        navigateAction?(route)
    }
}
