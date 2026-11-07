import AppKit

/// Закрытие окна по умолчанию оставляет приложение в Dock, как принято на Mac.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = ProfileDefaults.current) {
        self.defaults = defaults
    }

    override convenience init() {
        ProfileLaunch.prepare()
        self.init(defaults: ProfileDefaults.current)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // В `TenFingersApp.init` объекта NSApp ещё нет, поэтому внешний вид задаём здесь, до первого кадра.
        ThemeResolver.applyStoredAppearance(defaults: defaults)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if FullScreenRestore.take(defaults: ProfileDefaults.device) {
            Task { @MainActor in await FullScreenRestore.apply() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        ProfileDefaults.deviceStore(pairedWith: defaults).bool(forKey: SettingsKey.quitOnWindowClose)
    }
}
