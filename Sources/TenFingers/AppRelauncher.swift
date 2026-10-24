import AppKit
import OSLog

private let relaunchLog = Logger(subsystem: "local.tenfingers", category: "relaunch")

/// Перезапуск приложения: новый экземпляр через NSWorkspace, затем выход из текущего.
/// Выход идёт обычным путём `NSApp.terminate`, поэтому незаконченное упражнение записывается, как при любом выходе.
@MainActor enum AppRelauncher {
    /// Только из собранного `.app` (при `swift run` перезапускать нечего).
    static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func relaunch() {
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
