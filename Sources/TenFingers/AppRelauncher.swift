import AppKit
import OSLog

private let relaunchLog = Logger(subsystem: "local.tenfingers", category: "relaunch")

/// Перезапуск приложения: новый экземпляр через NSWorkspace, затем выход из текущего.
/// Выход идёт обычным путём `NSApp.terminate`, поэтому незаконченное упражнение записывается, как при любом выходе.
@MainActor enum AppRelauncher {
    /// Только из собранного `.app` (при `swift run` перезапускать нечего).
    static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func relaunch() {
        FullScreenRestore.record(
            wasFullScreen: NSApp.windows.contains { $0.styleMask.contains(.fullScreen) },
            defaults: ProfileDefaults.device)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    relaunchLog.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

/// Полный экран переживает перезапуск: перед выходом пишем флаг (уровень Mac), новый экземпляр читает его один раз.
enum FullScreenRestore {
    static func record(wasFullScreen: Bool, defaults: UserDefaults) {
        if wasFullScreen { defaults.set(true, forKey: SettingsKey.restoreFullScreen) }
    }

    /// Прочитать и сразу удалить флаг: восстановление — только для одного запуска.
    static func take(defaults: UserDefaults) -> Bool {
        let flag = defaults.bool(forKey: SettingsKey.restoreFullScreen)
        defaults.removeObject(forKey: SettingsKey.restoreFullScreen)
        return flag
    }

    /// Нужно ли переключить окно во весь экран.
    static func shouldEnter(flag: Bool, windowIsFullScreen: Bool) -> Bool { flag && !windowIsFullScreen }

    /// Ждёт появления главного окна (до ~5 с) и переводит его во весь экран.
    @MainActor static func apply() async {
        for _ in 0..<25 {
            if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
                if shouldEnter(flag: true, windowIsFullScreen: window.styleMask.contains(.fullScreen)) {
                    window.toggleFullScreen(nil)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
