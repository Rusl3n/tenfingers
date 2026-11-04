import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

// Проверка обновлений и ход установки (7b, задача 6). Сети и /Applications нет: `fetch` и установщик поддельные.

private let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)

private func manifestJSON(version: String = "2.4.0", build: Int = 10, format: Int = 1, minimum: String = "15.0",
                          zipName: String = "TenFingers-2.4.0.zip") -> Data {
    Data("""
    {"format": \(format), "version": "\(version)", "build": \(build), "commit": "abc", "schemaGeneration": 6,
     "minimumSystemVersion": "\(minimum)",
     "zip": {"name": "\(zipName)", "size": 1, "sha256": "aa"}, "dmg": {"name": "a.dmg", "size": 2, "sha256": "bb"},
     "notesURL": "https://example.com/notes"}
    """.utf8)
}

private func manifest(version: String = "2.4.0", zipName: String = "TenFingers-2.4.0.zip") throws -> ReleaseManifest {
    try ReleaseManifest.decode(manifestJSON(version: version, zipName: zipName))
}

/// Поддельная сеть: что вернуть и какие адреса запрошены.
@MainActor private final class FakeFetch {
    var result: Result<Data, any Error> = .success(manifestJSON())
    private(set) var urls: [URL] = []
    /// Если включено, запрос ждёт `release()`; `isWaiting` говорит, что он уже ждёт.
    var hold = false
    private(set) var isWaiting = false
    private var gate: CheckedContinuation<Void, Never>?
    func release() { gate?.resume(); gate = nil; isWaiting = false }
    func callAsFunction(_ url: URL) async throws -> Data {
        urls.append(url)
        if hold { await withCheckedContinuation { gate = $0; isWaiting = true } }
        return try result.get()
    }
}

/// Поддельный установщик: журнал вызовов по порядку, отказ на заданном шаге, снимок состояния проверки на каждом шаге.
@MainActor private final class FakeInstaller: UpdateInstalling {
    private(set) var calls: [String] = []
    private(set) var statesAtCall: [String: UpdateChecker.State] = [:]
    private(set) var zipURLs: [URL] = []
    var failAt: String?
    var error: any Error = UpdateError.backupFailed("x")
    var progressValues: [Double] = []
    var downloadDelay: Duration?
    var onBackup: (() -> Void)?
    var onReplace: (() -> Void)?
    weak var checker: UpdateChecker?
    let backupURL = URL(filePath: "/tmp/backups/before-update-2.4.0-x", directoryHint: .isDirectory)

    private func record(_ name: String) throws {
        calls.append(name)
        if let checker { statesAtCall[name] = checker.state }
        if failAt == name { throw error }
    }

    func preflight(manifest: ReleaseManifest) throws { try record("preflight") }
    func download(_ manifest: ReleaseManifest, zipURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        zipURLs.append(zipURL)
        try record("download")
        for value in progressValues { progress(value); await Task.yield() }
        if let downloadDelay { try await Task.sleep(for: downloadDelay) }
        try Task.checkCancellation()
        return URL(filePath: "/tmp/new/TenFingers.app")
    }
    func backup(version: String) throws -> URL { try record("backup"); onBackup?(); return backupURL }
    func replace(with newApp: URL) throws { try record("replace"); onReplace?() }
    func discardDownload(_ newApp: URL) { calls.append("discard") }
    func relaunch() throws { try record("relaunch") }
}

@MainActor private struct Harness {
    let defaults: UserDefaults
    let name: String
    let fetch = FakeFetch()
    let installer = FakeInstaller()
    var date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() { (defaults, name) = makeTestDefaults("UpdateCheckerTests-") }
    func cleanUp() { removeTestDefaults(name) }

    func checker(version: String? = "2.3.1", build: String = "5", bundled: Bool = true,
                 system: OperatingSystemVersion = sequoia) -> UpdateChecker {
        var info: [String: Any] = [:]
        if let version { info["CFBundleShortVersionString"] = version; info["CFBundleVersion"] = build }
        let fetch = fetch, installer = installer, date = date
        let checker = UpdateChecker(defaults: defaults, fetch: { try await fetch($0) }, installer: { installer },
                                    now: { date }, info: info, systemVersion: system, isBundledApp: bundled)
        installer.checker = checker
        return checker
    }
}

// MARK: Проверка

@MainActor @Test func notFoundIsSilentInAutoCheckAndFailureInManual() async throws {
    let h = Harness(); defer { h.cleanUp() }
    h.fetch.result = .failure(UpdateFetchError.http(404))
    let checker = h.checker()
    await checker.check(manual: false)
    #expect(checker.state == .idle)
    #expect(h.defaults.object(forKey: SettingsKey.updateLastCheck) == nil)
    await checker.check(manual: true)
    guard case .failed = checker.state else { Issue.record("\(checker.state)"); return }
    #expect(h.defaults.object(forKey: SettingsKey.updateLastCheck) == nil)
}

@MainActor @Test func networkErrorIsSilentInAutoCheckAndFailureInManual() async {
    let h = Harness(); defer { h.cleanUp() }
    h.fetch.result = .failure(URLError(.notConnectedToInternet))
    let checker = h.checker()
    await checker.check(manual: false)
    #expect(checker.state == .idle)
    await checker.check(manual: true)
    guard case .failed = checker.state else { Issue.record("\(checker.state)"); return }
}

@MainActor @Test func garbageResponseIsSilentInAutoCheckAndFailureInManual() async {
    let h = Harness(); defer { h.cleanUp() }
    h.fetch.result = .success(Data("не json".utf8))
    let checker = h.checker()
    await checker.check(manual: false)
    #expect(checker.state == .idle)
    await checker.check(manual: true)
    guard case .failed = checker.state else { Issue.record("\(checker.state)"); return }
}

@MainActor @Test func failedAutoCheckKeepsEarlierOffer() async throws {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker()
    await checker.check(manual: true)
    #expect(checker.state == .available(try manifest()))
    h.fetch.result = .failure(URLError(.timedOut))
    await checker.check(manual: false)
    #expect(checker.state == .available(try manifest()))
}

@MainActor @Test func newerVersionIsOfferedAndLastCheckRecorded() async throws {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker()
    await checker.check(manual: false)
    #expect(checker.state == .available(try manifest()))
    #expect(h.defaults.object(forKey: SettingsKey.updateLastCheck) as? Date == h.date)
    #expect(h.fetch.urls == [UpdateChecker.defaultFeedURL])
}

@MainActor @Test func sameVersionIsUpToDate() async {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker(version: "2.4.0", build: "10")
    await checker.check(manual: true)
    #expect(checker.state == .upToDate)
    #expect(h.defaults.object(forKey: SettingsKey.updateLastCheck) as? Date == h.date)
}

@MainActor @Test func skipRemembersVersionAndNextCheckIsIdle() async throws {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker()
    await checker.check(manual: true)
    checker.skip()
    #expect(h.defaults.string(forKey: SettingsKey.updateSkippedVersion) == "2.4.0")
    #expect(checker.state == .idle)
    await checker.check(manual: true)
    #expect(checker.state == .idle)
    // следующая версия снова предлагается
    h.fetch.result = .success(manifestJSON(version: "2.5.0"))
    await checker.check(manual: true)
    #expect(checker.state == .available(try manifest(version: "2.5.0")))
}

@MainActor @Test func skippedVersionNotNewerThanInstalledIsUpToDate() async {
    let h = Harness(); defer { h.cleanUp() }
    h.defaults.set("2.4.0", forKey: SettingsKey.updateSkippedVersion)
    let checker = h.checker(version: "2.4.0", build: "10")
    await checker.check(manual: true)
    #expect(checker.state == .upToDate)
    let newer = h.checker(version: "2.9.0", build: "1")
    await newer.check(manual: true)
    #expect(newer.state == .upToDate)
}

@MainActor @Test func unsupportedFormatOrSystemIsFailureInManualOnly() async {
    let h = Harness(); defer { h.cleanUp() }
    h.fetch.result = .success(manifestJSON(format: 2))
    let checker = h.checker()
    await checker.check(manual: false)
    #expect(checker.state == .idle)
    await checker.check(manual: true)
    guard case .failed = checker.state else { Issue.record("\(checker.state)"); return }
    h.fetch.result = .success(manifestJSON(minimum: "99.0"))
    await checker.check(manual: true)
    guard case .failed = checker.state else { Issue.record("\(checker.state)"); return }
}

@MainActor @Test func developmentBuildWithoutFeedDoesNotTouchNetwork() async {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker(version: "2.4.0-dev")
    #expect(checker.state == .development)
    await checker.check(manual: true)
    await checker.check(manual: false)
    checker.checkIfDue()
    #expect(checker.state == .development)
    #expect(h.fetch.urls.isEmpty)
}

@MainActor @Test func missingVersionOrNonAppIsDevelopmentEvenWithFeed() async {
    let h = Harness(); defer { h.cleanUp() }
    h.defaults.set("https://example.com/release.json", forKey: SettingsKey.updateFeedURL)
    let swiftRun = h.checker(version: nil, bundled: false)
    #expect(swiftRun.state == .development)
    await swiftRun.check(manual: true)
    let notApp = h.checker(version: "2.4.0-dev", bundled: false)
    await notApp.check(manual: true)
    #expect(h.fetch.urls.isEmpty)
}

@MainActor @Test func developmentBuildWithFeedChecksThatFeed() async throws {
    let h = Harness(); defer { h.cleanUp() }
    h.defaults.set("https://example.com/feed/release.json", forKey: SettingsKey.updateFeedURL)
    let checker = h.checker(version: "2.3.0-dev")
    #expect(checker.state == .idle)
    await checker.check(manual: true)
    #expect(h.fetch.urls == [URL(string: "https://example.com/feed/release.json")!])
    #expect(checker.state == .available(try manifest()))
}

@MainActor @Test func feedURLIsIgnoredInReleaseBuild() async {
    let h = Harness(); defer { h.cleanUp() }
    h.defaults.set("https://example.com/feed/release.json", forKey: SettingsKey.updateFeedURL)
    let checker = h.checker(version: "2.3.1")
    await checker.check(manual: true)
    #expect(h.fetch.urls == [UpdateChecker.defaultFeedURL])
}

@MainActor @Test func checkIfDueRespectsGapAndSwitch() async {
    let h = Harness(); defer { h.cleanUp() }
    h.defaults.set(h.date.addingTimeInterval(-19 * 3600), forKey: SettingsKey.updateLastCheck)
    let checker = h.checker()
    checker.checkIfDue()
    await checker.waitForCheck()
    #expect(h.fetch.urls.isEmpty)

    h.defaults.set(h.date.addingTimeInterval(-21 * 3600), forKey: SettingsKey.updateLastCheck)
    h.defaults.set(false, forKey: SettingsKey.updateAutoCheck)
    checker.checkIfDue()
    await checker.waitForCheck()
    #expect(h.fetch.urls.isEmpty)

    h.defaults.set(true, forKey: SettingsKey.updateAutoCheck)
    checker.checkIfDue()
    await checker.waitForCheck()
    #expect(h.fetch.urls.count == 1)
    #expect(checker.state == .available(try! manifest()))
}

// MARK: Установка

private func waitUntilInstalled(_ checker: UpdateChecker) async { await checker.waitForInstall() }

@MainActor @Test func installRunsStepsInOrderAndShowsProgress() async throws {
    let h = Harness(); defer { h.cleanUp() }
    h.installer.progressValues = [0.5, 1]
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    #expect(h.installer.calls == ["preflight", "download", "backup", "replace", "relaunch"])
    #expect(h.installer.statesAtCall["preflight"] == .installing(.downloading(0)))
    #expect(h.installer.statesAtCall["backup"] == .installing(.backingUp))
    #expect(h.installer.statesAtCall["replace"] == .installing(.installing))
    #expect(h.installer.statesAtCall["relaunch"] == .installing(.installing))
    #expect(checker.state == .installing(.installing))
}

@MainActor @Test func checkFinishingDuringInstallKeepsInstallingState() async {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker()
    await checker.check(manual: true)
    h.fetch.hold = true
    checker.checkNow()
    while !h.fetch.isWaiting { await Task.yield() }
    checker.install()
    await checker.waitForInstall()
    #expect(checker.state == .installing(.installing))
    h.fetch.release()
    await checker.waitForCheck()
    #expect(checker.state == .installing(.installing))
}

@MainActor @Test func zipURLIsNextToReleaseJSON() async {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    #expect(h.installer.zipURLs == [URL(string: "https://github.com/Rusl3n/tenfingers/releases/latest/download/TenFingers-2.4.0.zip")!])

    let h2 = Harness(); defer { h2.cleanUp() }
    h2.defaults.set("file:///tmp/feed/release.json", forKey: SettingsKey.updateFeedURL)
    let dev = h2.checker(version: "2.3.0-dev")
    await dev.check(manual: true)
    dev.install()
    await waitUntilInstalled(dev)
    #expect(h2.installer.zipURLs == [URL(string: "file:///tmp/feed/TenFingers-2.4.0.zip")!])
}

@MainActor @Test func zipNameWithSlashIsRefused() async throws {
    let h = Harness(); defer { h.cleanUp() }
    h.fetch.result = .success(manifestJSON(zipName: "../evil.zip"))
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    #expect(h.installer.calls.isEmpty)
    guard case .installFailed(.badBundle) = checker.state else { Issue.record("\(checker.state)"); return }
}

@MainActor @Test(arguments: ["preflight", "download", "backup", "replace"])
func installStopsAtFirstError(step: String) async throws {
    let h = Harness(); defer { h.cleanUp() }
    h.installer.failAt = step
    h.installer.error = UpdateError.checksum
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    let order = ["preflight", "download", "backup", "replace", "relaunch"]
    let expected = Array(order.prefix(through: order.firstIndex(of: step)!))
    // после загрузки сбой оставляет временную папку: её убирает установщик
    let cleaned = step == "backup" || step == "replace" ? expected + ["discard"] : expected
    #expect(h.installer.calls == cleaned)
    #expect(checker.state == .installFailed(.checksum))
    #expect(!h.installer.calls.contains("relaunch"))
}

@MainActor @Test func backupFolderIsRememberedAfterReplaceFailure() async {
    let h = Harness(); defer { h.cleanUp() }
    h.installer.failAt = "replace"
    h.installer.error = UpdateError.replaceFailed("move current: x")
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    #expect(checker.backupFolder == h.installer.backupURL)
    #expect(checker.statusText.contains(h.installer.backupURL.path))
}

@MainActor @Test func nonUpdateErrorFromPreflightGetsReadableState() async {
    let h = Harness(); defer { h.cleanUp() }
    h.installer.failAt = "preflight"
    h.installer.error = SchemaGeneration.UnreadableMarker()
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    #expect(checker.state == .installFailed(.unreadableGeneration))
    #expect(!checker.statusText.isEmpty)

    let h2 = Harness(); defer { h2.cleanUp() }
    h2.installer.failAt = "preflight"
    h2.installer.error = Boom()
    let other = h2.checker()
    await other.check(manual: true)
    other.install()
    await waitUntilInstalled(other)
    guard case .installFailed(.preflightFailed) = other.state else { Issue.record("\(other.state)"); return }
}

@MainActor @Test func downloadNetworkErrorBecomesDownloadFailed() async {
    let h = Harness(); defer { h.cleanUp() }
    h.installer.failAt = "download"
    h.installer.error = URLError(.notConnectedToInternet)
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    guard case .installFailed(.downloadFailed) = checker.state else { Issue.record("\(checker.state)"); return }
    #expect(h.installer.calls == ["preflight", "download"])
}

@MainActor @Test func relaunchFailureIsShownAsInstallError() async {
    let h = Harness(); defer { h.cleanUp() }
    h.installer.failAt = "relaunch"
    h.installer.error = Boom()
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    guard case .installFailed(.relaunchFailed) = checker.state else { Issue.record("\(checker.state)"); return }
    #expect(h.installer.calls == ["preflight", "download", "backup", "replace", "relaunch"])
    #expect(!h.installer.calls.contains("discard"))
    // бандл уже новый: возвращаться к «Доступна версия» нельзя
    checker.dismissFailure()
    #expect(checker.state == .idle)
}

@MainActor @Test func cancelDuringDownloadReturnsToAvailableAndCleans() async throws {
    let h = Harness(); defer { h.cleanUp() }
    h.installer.downloadDelay = .seconds(10)
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    try await Task.sleep(for: .milliseconds(50))
    checker.cancel()
    await waitUntilInstalled(checker)
    #expect(checker.state == .available(try manifest()))
    #expect(h.installer.calls == ["preflight", "download"])
}

@MainActor @Test func cancelAfterBackupStopsBeforeReplace() async throws {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker()
    await checker.check(manual: true)
    // отмена приходит в момент резервной копии (синхронный шаг): до замены
    h.installer.onBackup = { checker.cancel() }
    checker.install()
    await waitUntilInstalled(checker)
    #expect(h.installer.calls == ["preflight", "download", "backup", "discard"])
    #expect(checker.state == .available(try manifest()))
}

@MainActor @Test func cancelIsIgnoredOnceReplacing() async throws {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker()
    await checker.check(manual: true)
    h.installer.onReplace = { checker.cancel() }
    checker.install()
    await waitUntilInstalled(checker)
    #expect(h.installer.calls == ["preflight", "download", "backup", "replace", "relaunch"])
}

@MainActor @Test func dismissFailureReturnsToOffer() async throws {
    let h = Harness(); defer { h.cleanUp() }
    h.installer.failAt = "backup"
    let checker = h.checker()
    await checker.check(manual: true)
    checker.install()
    await waitUntilInstalled(checker)
    checker.dismissFailure()
    #expect(checker.state == .available(try manifest()))
}

// MARK: Тексты

@MainActor @Test func errorTextsSayNothingChangedAndWhereTheCopyIs() {
    let copy = URL(filePath: "/Users/x/Library/Application Support/TenFingers.backups/before-update-2.4.0-1")
    for error in [UpdateError.checksum, .size, .signature, .badBundle("Info.plist"), .backupFailed("x"),
                  .replaceFailed("move current: x"), .olderGeneration(stored: 9, update: 6), .translocated,
                  .notWritable, .unreadableGeneration, .preflightFailed("x"), .downloadFailed("x")] {
        let plain = UpdateChecker.message(for: error, backup: nil)
        #expect(!plain.isEmpty)
        let withCopy = UpdateChecker.message(for: error, backup: copy)
        #expect(withCopy.contains(copy.path), "\(error)")
    }
    // «не изменены» — в каждом сообщении, кроме новой версии, которая уже установлена
    #expect(UpdateChecker.message(for: .checksum, backup: nil).contains("не изменены"))
    #expect(!UpdateChecker.message(for: .relaunchFailed("x"), backup: nil).contains("не изменены"))
    #expect(UpdateChecker.message(for: .relaunchFailed("x"), backup: nil).contains("вручную"))
    // замена не откатилась: прежняя версия лежит рядом
    #expect(UpdateChecker.message(for: .replaceFailed("move new: a; restore failed: b"), backup: nil).contains(".previous"))
}

@Test func releasePageButtonOnlyForPlacementErrors() {
    #expect(UpdateError.translocated.suggestsReleasePage)
    #expect(UpdateError.notWritable.suggestsReleasePage)
    #expect(!UpdateError.checksum.suggestsReleasePage)
    #expect(!UpdateError.backupFailed("x").suggestsReleasePage)
}

@MainActor @Test func statusTextMatchesState() async throws {
    let h = Harness(); defer { h.cleanUp() }
    let checker = h.checker()
    await checker.check(manual: true)
    #expect(checker.statusText == "Доступна версия 2.4.0")
    let latest = h.checker(version: "2.4.0", build: "10")
    await latest.check(manual: true)
    #expect(latest.statusText == "Установлена последняя версия")
    h.fetch.result = .failure(UpdateFetchError.http(500))
    await latest.check(manual: true)
    #expect(latest.statusText.hasPrefix("Не удалось проверить: "))
    #expect(h.checker(version: "2.4.0-dev").statusText == "Сборка для разработки, обновления выключены")
    #expect(UpdateChecker.stepText(.downloading(0.426)) == "Скачивание… 42%")
    #expect(UpdateChecker.stepText(.verifying) == "Проверка")
    #expect(UpdateChecker.stepText(.backingUp) == "Резервная копия")
    #expect(UpdateChecker.stepText(.installing) == "Установка")
}

@MainActor @Test func updateIconExists() {
    #expect(NSImage(systemSymbolName: UpdateBanner.icon, accessibilityDescription: nil) != nil)
    #expect(UpdateBanner.icon == "arrow.down.circle")
}

private struct Boom: Error {}
