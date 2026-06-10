import Foundation

final class MenuBarCommandHandler: NSObject {
    private let openMainWindowAction: () -> Void
    private let openSettingsAction: () -> Void
    private let quitApplicationAction: () -> Void

    init(
        openMainWindow: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quitApplication: @escaping () -> Void
    ) {
        openMainWindowAction = openMainWindow
        openSettingsAction = openSettings
        quitApplicationAction = quitApplication
    }

    @objc
    func openMainWindow() {
        openMainWindowAction()
    }

    @objc
    func openSettings() {
        openSettingsAction()
    }

    @objc
    func quitApplication() {
        quitApplicationAction()
    }
}
