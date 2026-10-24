import AppKit
import Testing
@testable import TenFingers

@MainActor @Test func windowCloseKeepsAppRunningByDefault() {
    let (defaults, name) = makeTestDefaults("test.window.")
    defer { removeTestDefaults(name) }
    let delegate = AppDelegate(defaults: defaults)
    #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    defaults.set(true, forKey: SettingsKey.quitOnWindowClose)
    #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
}
