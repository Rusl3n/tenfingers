import CryptoKit
import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private struct StubDownloader: UpdateDownloading {
    var file: URL?
    var error: (any Error)?
    func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if let error { throw error }
        progress(1)
        // отдаём копию: установщик забирает файл себе
        let copy = file!.deletingLastPathComponent().appending(path: "dl-\(UUID().uuidString).zip")
        try FileManager.default.copyItem(at: file!, to: copy)
        return copy
    }
}

/// Файловая система, роняющая заданное по счёту перемещение.
private final class FailingFileSystem: UpdateFileSystem, @unchecked Sendable {
    private let live = LiveUpdateFileSystem()
    private let failingMove: Int
    private let lock = NSLock()
    private var moves = 0
    init(failingMove: Int) { self.failingMove = failingMove }
    func moveItem(at source: URL, to destination: URL) throws {
        lock.lock(); moves += 1; let n = moves; lock.unlock()
        if n == failingMove { throw CocoaError(.fileWriteUnknown) }
        try live.moveItem(at: source, to: destination)
    }
    func removeItem(at url: URL) throws { try live.removeItem(at: url) }
}

private struct Boom: Error {}

private func shell(_ path: String, _ args: [String]) throws {
    let result = try UpdateTools.run(path, args)
    #expect(result.status == 0, "\(path) \(args): \(result.output)")
}

/// Поддельный `.app`: `Contents/Info.plist` и пустой исполняемый файл, подпись ad-hoc.
private func makeFakeApp(at url: URL, version: String, generation: Int, identifier: String = "local.tenfingers",
                         marker: String = "") throws {
    let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "TenFingers",
                                "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
                                "CFBundleVersion": "1", "TFSchemaGeneration": generation]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appending(path: "Info.plist"))
    try Data().write(to: contents.appending(path: "MacOS/TenFingers"))
    try FileManager.default.createDirectory(at: contents.appending(path: "Resources"), withIntermediateDirectories: true)
    try marker.write(to: contents.appending(path: "Resources/marker.txt"), atomically: true, encoding: .utf8)
    try shell("/usr/bin/codesign", ["-s", "-", "--force", url.path])
}

@MainActor private struct Env {
    let root: URL
    let apps: URL
    let bundle: URL
    let storeDirectory: URL
    let storeURL: URL
    let backups: URL
    let container: ModelContainer
    let defaultsName: String
    let defaults: UserDefaults

    init(storeGeneration: Int? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "UpdateInstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        apps = root.appending(path: "Apps", directoryHint: .isDirectory)
        bundle = apps.appending(path: "TenFingers.app", directoryHint: .isDirectory)
        storeDirectory = root.appending(path: "TenFingers", directoryHint: .isDirectory)
        storeURL = storeDirectory.appending(path: "TenFingers.store")
        backups = root.appending(path: "TenFingers.backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try makeFakeApp(at: bundle, version: "1.0.0", generation: 6, marker: "old")
        container = try ModelStore.makeContainer(at: storeURL)
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        container.mainContext.insert(SessionRecord(
            mode: "course", language: "ru", lessonId: "ru.1.1", startedAt: base, endedAt: base.addingTimeInterval(60),
            logicalDay: "2026-09-21", activeSeconds: 60, chars: 100, errorCount: 1, cpm: 100, accuracy: 0.99,
            completed: true, hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 1, exerciseKind: "check",
            pinkyPresses: 1, pinkyErrors: 0, source: nil))
        try container.mainContext.save()
        if let storeGeneration { try SchemaGeneration.write(storeGeneration, at: storeURL) }
        (defaults, defaultsName) = makeTestDefaults("UpdateInstallerTests-")
    }

    func cleanUp() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: apps.path)
        try? FileManager.default.removeItem(at: root)
        removeTestDefaults(defaultsName)
    }

    /// Архив с новой версией и описание выпуска к нему.
    func release(version: String = "2.0.0", generation: Int = 6, identifier: String = "local.tenfingers",
                 manifestVersion: String? = nil, manifestGeneration: Int? = nil,
                 sha: String? = nil, size: Int? = nil) throws -> (manifest: ReleaseManifest, zip: URL) {
        let staging = root.appending(path: "staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let app = staging.appending(path: "TenFingers.app", directoryHint: .isDirectory)
        try makeFakeApp(at: app, version: version, generation: generation, identifier: identifier, marker: "new")
        let zip = staging.appending(path: "TenFingers-\(version).zip")
        try shell("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        let data = try Data(contentsOf: zip)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let asset = #"{"name":"TenFingers-\#(version).zip","size":\#(size ?? data.count),"sha256":"\#(sha ?? digest)"}"#
        let json = #"""
        {"format":1,"version":"\#(manifestVersion ?? version)","build":10,"commit":"abc1234",
         "schemaGeneration":\#(manifestGeneration ?? generation),"minimumSystemVersion":"15.0",
         "zip":\#(asset),"dmg":{"name":"TenFingers-\#(version).dmg","size":1,"sha256":"00"},
         "notesURL":"https://example.com/notes"}
        """#
        return (try ReleaseManifest.decode(Data(json.utf8)), zip)
    }

    func installer(zip: URL? = nil, downloadError: (any Error)? = nil, fileSystem: UpdateFileSystem = LiveUpdateFileSystem(),
                   saveContext: (() throws -> Void)? = nil, makeArchive: (() throws -> Data)? = nil,
                   bundleURL: URL? = nil, relauncher: @escaping UpdateInstaller.Relauncher = { _ in }) -> UpdateInstaller {
        let context = container.mainContext
        let defaults = defaults
        return UpdateInstaller(
            bundleURL: bundleURL ?? bundle, storeURL: storeURL, backupsDirectory: backups,
            downloader: StubDownloader(file: zip, error: downloadError),
            now: { Date(timeIntervalSinceReferenceDate: 800_000_000) },
            saveContext: saveContext ?? { try context.save() },
            makeArchive: makeArchive ?? { try ProgressArchive.export(context: context, defaults: defaults) },
            fileSystem: fileSystem, relauncher: relauncher)
    }

    func marker(of app: URL) -> String? { try? String(contentsOf: app.appending(path: "Contents/Resources/marker.txt"), encoding: .utf8) }

    func updateFolders() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []).filter { $0.hasPrefix(".TenFingers-update-") }
    }

    func storeFingerprint() throws -> [String: Int] {
        var result: [String: Int] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path) where !name.hasSuffix("-shm") {
            result[name] = try Data(contentsOf: storeDirectory.appending(path: name)).count
        }
        return result
    }
}

private let zipURL = URL(string: "https://example.com/TenFingers-2.0.0.zip")!

@MainActor @Test func fullChainReplacesBundleAndKeepsData() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, zip) = try env.release()
    let installer = env.installer(zip: zip)
    try installer.preflight(manifest: manifest)
    let storeBefore = try env.storeFingerprint()

    let newApp = try await installer.download(manifest, zipURL: zipURL, progress: { _ in })
    #expect(newApp.lastPathComponent == "TenFingers.app")
    #expect(env.marker(of: env.bundle) == "old")
    let backup = try installer.backup(version: manifest.version)
    try installer.replace(with: newApp)

    #expect(env.marker(of: env.bundle) == "new")
    #expect(env.marker(of: env.apps.appending(path: "TenFingers.app.previous")) == "old")
    #expect(try rowCount("ZSESSIONRECORD", in: env.storeURL) == 1)
    #expect(try rowCount("ZSESSIONRECORD", in: backup.appending(path: "TenFingers.store")) == 1)
    #expect(FileManager.default.fileExists(atPath: backup.appending(path: "progress.tenfingers").path))
    #expect(try env.storeFingerprint().keys == storeBefore.keys)

    UpdateInstaller.cleanUpAfterSuccessfulLaunch(bundleURL: env.bundle)
    #expect(!FileManager.default.fileExists(atPath: env.apps.appendingPathComponent("TenFingers.app.previous").path))
    #expect(env.updateFolders().isEmpty)
    #expect(env.marker(of: env.bundle) == "new")
    #expect(FileManager.default.fileExists(atPath: backup.path))
}

@MainActor @Test(arguments: ["sha", "size", "identifier", "version", "generation", "signature", "twoApps"])
func badDownloadIsRefusedAndCleaned(case kind: String) async throws {
    let env = try Env()
    defer { env.cleanUp() }
    var release: (manifest: ReleaseManifest, zip: URL)
    var expected: UpdateError
    switch kind {
    case "sha": release = try env.release(sha: String(repeating: "0", count: 64)); expected = .checksum
    case "size": release = try env.release(size: 1); expected = .size
    case "identifier": release = try env.release(identifier: "other.app"); expected = .badBundle("CFBundleIdentifier")
    case "version": release = try env.release(manifestVersion: "9.9.9"); expected = .badBundle("CFBundleShortVersionString")
    case "generation": release = try env.release(manifestGeneration: 7); expected = .badBundle("TFSchemaGeneration")
    case "signature":
        release = try env.release()
        // портим подпись после упаковки: меняем содержимое и пакуем заново, манифест пересчитывается
        let staging = env.root.appending(path: "tampered-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try shell("/usr/bin/ditto", ["-x", "-k", release.zip.path, staging.path])
        try "changed".write(to: staging.appending(path: "TenFingers.app/Contents/Resources/marker.txt"), atomically: true, encoding: .utf8)
        let zip = staging.appending(path: "t.zip")
        try shell("/usr/bin/ditto", ["-c", "-k", "--keepParent", staging.appending(path: "TenFingers.app").path, zip.path])
        let data = try Data(contentsOf: zip)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let json = #"{"format":1,"version":"2.0.0","build":1,"commit":"a","schemaGeneration":6,"minimumSystemVersion":"15.0","zip":{"name":"t.zip","size":\#(data.count),"sha256":"\#(digest)"},"dmg":{"name":"d","size":1,"sha256":"0"},"notesURL":"https://example.com"}"#
        release = (try ReleaseManifest.decode(Data(json.utf8)), zip)
        expected = .signature
    default:
        release = try env.release()
        // два приложения в архиве
        let staging = env.root.appending(path: "two-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: env.bundle, to: staging.appending(path: "TenFingers.app"))
        try FileManager.default.copyItem(at: env.bundle, to: staging.appending(path: "Other.app"))
        let zip = env.root.appending(path: "two-\(UUID().uuidString).zip")
        try shell("/usr/bin/ditto", ["-c", "-k", staging.path, zip.path])
        let data = try Data(contentsOf: zip)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let json = #"{"format":1,"version":"2.0.0","build":1,"commit":"a","schemaGeneration":6,"minimumSystemVersion":"15.0","zip":{"name":"t.zip","size":\#(data.count),"sha256":"\#(digest)"},"dmg":{"name":"d","size":1,"sha256":"0"},"notesURL":"https://example.com"}"#
        release = (try ReleaseManifest.decode(Data(json.utf8)), zip)
        expected = .badBundle("content: [\"Other.app\", \"TenFingers.app\"]")
    }
    let installer = env.installer(zip: release.zip)
    await #expect(throws: expected) {
        _ = try await installer.download(release.manifest, zipURL: zipURL, progress: { _ in })
    }
    #expect(env.marker(of: env.bundle) == "old")
    #expect(env.updateFolders().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: env.apps.path) == ["TenFingers.app"])
}

@MainActor @Test func downloaderCancellationBecomesCancelled() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, _) = try env.release()
    let installer = env.installer(downloadError: CancellationError())
    await #expect(throws: UpdateError.cancelled) {
        _ = try await installer.download(manifest, zipURL: zipURL, progress: { _ in })
    }
    #expect(env.updateFolders().isEmpty)
}

@MainActor @Test func cancelledTaskStopsBeforeDownload() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, zip) = try env.release()
    let installer = env.installer(zip: zip)
    let task = Task { @MainActor in try await installer.download(manifest, zipURL: zipURL, progress: { _ in }) }
    task.cancel()
    await #expect(throws: UpdateError.cancelled) { _ = try await task.value }
    #expect(env.updateFolders().isEmpty)
}

@MainActor @Test func translocatedPathIsRefused() throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, _) = try env.release()
    let translocated = env.root.appending(path: "AppTranslocation/ABC/d/TenFingers.app", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: translocated, withIntermediateDirectories: true)
    #expect(throws: UpdateError.translocated) {
        try env.installer(bundleURL: translocated).preflight(manifest: manifest)
    }
}

@MainActor @Test func readOnlyParentIsRefused() throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, _) = try env.release()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: env.apps.path)
    #expect(throws: UpdateError.notWritable) { try env.installer().preflight(manifest: manifest) }
}

@MainActor @Test func newerStoreGenerationIsRefused() throws {
    let env = try Env(storeGeneration: 9)
    defer { env.cleanUp() }
    let (manifest, _) = try env.release()   // поколение 6 (в тесте описание «7» ниже)
    #expect(throws: UpdateError.olderGeneration(stored: 9, update: 6)) {
        try env.installer().preflight(manifest: manifest)
    }
    let seven = try env.release(generation: 7)
    #expect(throws: UpdateError.olderGeneration(stored: 9, update: 7)) {
        try env.installer().preflight(manifest: seven.manifest)
    }
}

@MainActor @Test func equalOrOlderStoreGenerationPasses() throws {
    let env = try Env(storeGeneration: 6)
    defer { env.cleanUp() }
    let (manifest, _) = try env.release()
    try env.installer().preflight(manifest: manifest)
    try SchemaGeneration.write(5, at: env.storeURL)
    try env.installer().preflight(manifest: manifest)
}

@MainActor @Test func saveFailureCancelsBackup() throws {
    let env = try Env()
    defer { env.cleanUp() }
    let installer = env.installer(saveContext: { throw Boom() })
    do { _ = try installer.backup(version: "2.0.0"); Issue.record("ожидалась ошибка") } catch let error as UpdateError {
        guard case .backupFailed = error else { Issue.record("\(error)"); return }
    }
    let saved = (try? FileManager.default.contentsOfDirectory(atPath: env.backups.path)) ?? []
    #expect(saved.isEmpty)
    #expect(env.marker(of: env.bundle) == "old")
}

@MainActor @Test func archiveFailureCancelsBackup() throws {
    let env = try Env()
    defer { env.cleanUp() }
    let installer = env.installer(makeArchive: { throw Boom() })
    do { _ = try installer.backup(version: "2.0.0"); Issue.record("ожидалась ошибка") } catch let error as UpdateError {
        guard case .backupFailed = error else { Issue.record("\(error)"); return }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: env.backups.path).isEmpty)
    #expect(env.marker(of: env.bundle) == "old")
}

@MainActor @Test func failedSecondMoveRestoresPrevious() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, zip) = try env.release()
    let newApp = try await env.installer(zip: zip).download(manifest, zipURL: zipURL, progress: { _ in })
    let installer = env.installer(fileSystem: FailingFileSystem(failingMove: 2))
    do { try installer.replace(with: newApp); Issue.record("ожидалась ошибка") } catch let error as UpdateError {
        guard case .replaceFailed = error else { Issue.record("\(error)"); return }
    }
    #expect(env.marker(of: env.bundle) == "old")
    #expect(!FileManager.default.fileExists(atPath: env.apps.appendingPathComponent("TenFingers.app.previous").path))
    #expect(FileManager.default.fileExists(atPath: newApp.path))
}

@MainActor @Test func staleLeftoverPreviousDoesNotBlockReplace() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let stale = env.apps.appending(path: "TenFingers.app.previous", directoryHint: .isDirectory)
    try makeFakeApp(at: stale, version: "0.5.0", generation: 6, marker: "stale")
    let (manifest, zip) = try env.release()
    let installer = env.installer(zip: zip)
    let newApp = try await installer.download(manifest, zipURL: zipURL, progress: { _ in })
    try installer.replace(with: newApp)
    #expect(env.marker(of: env.bundle) == "new")
    #expect(env.marker(of: stale) == "old")
}

@MainActor @Test func rollBackRestoresPreviousBundle() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, zip) = try env.release()
    let installer = env.installer(zip: zip)
    try installer.replace(with: try await installer.download(manifest, zipURL: zipURL, progress: { _ in }))
    #expect(env.marker(of: env.bundle) == "new")

    try UpdateInstaller.rollBack(bundleURL: env.bundle)
    #expect(env.marker(of: env.bundle) == "old")
    #expect(!FileManager.default.fileExists(atPath: env.apps.appendingPathComponent("TenFingers.app.previous").path))
    #expect(try rowCount("ZSESSIONRECORD", in: env.storeURL) == 1)
}

@MainActor @Test func rollBackWithoutPreviousFails() throws {
    let env = try Env()
    defer { env.cleanUp() }
    #expect(throws: (any Error).self) { try UpdateInstaller.rollBack(bundleURL: env.bundle) }
    #expect(env.marker(of: env.bundle) == "old")
}

@MainActor @Test func relaunchCallsInjectedRelauncher() throws {
    let env = try Env()
    defer { env.cleanUp() }
    var received: URL?
    try env.installer(relauncher: { received = $0 }).relaunch()
    #expect(received == env.bundle)
}

@MainActor @Test func cleanUpRemovesPreviousAndWorkFolders() throws {
    let env = try Env()
    defer { env.cleanUp() }
    try FileManager.default.createDirectory(at: env.apps.appending(path: "TenFingers.app.previous"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: env.apps.appending(path: ".TenFingers-update-A"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: env.apps.appending(path: ".TenFingers-update-B"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: env.apps.appending(path: "Keep"), withIntermediateDirectories: true)
    UpdateInstaller.cleanUpAfterSuccessfulLaunch(bundleURL: env.bundle)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: env.apps.path)) == ["TenFingers.app", "Keep"])
}

// MARK: Правки по ревью (7b, задача 6)

/// Загрузчик, который ждёт отмены задачи и бросает свою ошибку (а не `CancellationError`).
private struct WaitsForCancelDownloader: UpdateDownloading {
    func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        throw Boom()
    }
}

@MainActor @Test func urlCancelledErrorBecomesCancelled() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, _) = try env.release()
    let installer = env.installer(downloadError: URLError(.cancelled))
    await #expect(throws: UpdateError.cancelled) {
        _ = try await installer.download(manifest, zipURL: zipURL, progress: { _ in })
    }
    #expect(env.updateFolders().isEmpty)
}

@MainActor @Test func anyDownloaderErrorOfCancelledTaskBecomesCancelled() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, _) = try env.release()
    let installer = UpdateInstaller(
        bundleURL: env.bundle, storeURL: env.storeURL, backupsDirectory: env.backups,
        downloader: WaitsForCancelDownloader(), now: { .now }, saveContext: {}, makeArchive: { Data() })
    let task = Task { @MainActor in try await installer.download(manifest, zipURL: zipURL, progress: { _ in }) }
    try await Task.sleep(for: .milliseconds(30))
    task.cancel()
    await #expect(throws: UpdateError.cancelled) { _ = try await task.value }
    #expect(env.updateFolders().isEmpty)
}

@MainActor @Test func otherDownloaderErrorIsPassedThrough() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, _) = try env.release()
    await #expect(throws: URLError.self) {
        _ = try await env.installer(downloadError: URLError(.notConnectedToInternet))
            .download(manifest, zipURL: zipURL, progress: { _ in })
    }
}

@MainActor @Test func discardDownloadRemovesWorkFolderOnly() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, zip) = try env.release()
    let installer = env.installer(zip: zip)
    let newApp = try await installer.download(manifest, zipURL: zipURL, progress: { _ in })
    #expect(env.updateFolders().count == 1)
    installer.discardDownload(newApp)
    #expect(env.updateFolders().isEmpty)
    #expect(env.marker(of: env.bundle) == "old")
    // чужой путь не трогается
    installer.discardDownload(env.bundle)
    #expect(env.marker(of: env.bundle) == "old")
}

@MainActor @Test func discardDownloadKeepsFolderWhenBundleIsMissing() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let (manifest, zip) = try env.release()
    let installer = env.installer(zip: zip)
    let newApp = try await installer.download(manifest, zipURL: zipURL, progress: { _ in })
    try FileManager.default.removeItem(at: env.bundle)   // как после неудачного отката замены
    installer.discardDownload(newApp)
    #expect(FileManager.default.fileExists(atPath: newApp.path))
}

@MainActor @Test func cleanUpIgnoresNonAppBundleURL() throws {
    let env = try Env()
    defer { env.cleanUp() }
    // `swift run`: «бандл» — папка с исполняемым файлом, а не .app
    let folder = env.apps.appending(path: "debug", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: env.apps.appending(path: "debug.previous"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: env.apps.appending(path: ".TenFingers-update-A"), withIntermediateDirectories: true)
    UpdateInstaller.cleanUpAfterSuccessfulLaunch(bundleURL: folder)
    #expect(FileManager.default.fileExists(atPath: env.apps.appending(path: "debug.previous").path))
    #expect(FileManager.default.fileExists(atPath: env.apps.appending(path: ".TenFingers-update-A").path))
}

/// Живая загрузка по `file://`: файл отдан целиком, в `NSTemporaryDirectory` не остаётся пустой папки.
@MainActor @Test func liveDownloaderLeavesNoEmptyFolder() async throws {
    let env = try Env()
    defer { env.cleanUp() }
    let source = env.root.appending(path: "source.bin")
    try Data("payload".utf8).write(to: source)
    func leftovers() -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
            .filter { $0.hasPrefix("TenFingers-download-") })
    }
    let before = leftovers()
    let file = try await URLSessionDownloader().download(source, progress: { _ in })
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(try Data(contentsOf: file) == Data("payload".utf8))
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) && !isDirectory.boolValue)
    try FileManager.default.removeItem(at: file)
    #expect(leftovers() == before)
}
