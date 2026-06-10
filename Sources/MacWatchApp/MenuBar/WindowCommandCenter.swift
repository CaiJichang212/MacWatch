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

    func registerOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func registerNavigationAction(_ action: @escaping (MainWindowRoute) -> Void) {
        navigateAction = action
        if let pendingRoute {
            self.pendingRoute = nil
            action(pendingRoute)
        }
    }

    func openMainWindow(route: MainWindowRoute = .dashboard) {
        pendingRoute = route
        openMainWindowAction?()
        navigateAction?(route)
    }
}
