import Foundation

final class WindowCommandCenter {
    static let shared = WindowCommandCenter()

    private var openMainWindowAction: (() -> Void)?

    func registerOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func openMainWindow() {
        openMainWindowAction?()
    }
}
