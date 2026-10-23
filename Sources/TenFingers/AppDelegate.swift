import AppKit

/// Закрытие окна по умолчанию оставляет приложение в Dock, как принято на Mac.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    override convenience init() {
        self.init(defaults: .standard)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // В `TenFingersApp.init` объекта NSApp ещё нет, поэтому внешний вид задаём здесь, до первого кадра.
        ThemeResolver.applyStoredAppearance(defaults: defaults)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        defaults.bool(forKey: SettingsKey.quitOnWindowClose)
    }
}
