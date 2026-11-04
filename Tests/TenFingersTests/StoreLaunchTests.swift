import Foundation
import SwiftData
import Testing
@testable import TenFingers

// Открытие базы при запуске, очистка после успеха и откат с экрана ошибки (7b, решения 8–9).

@MainActor private struct Folder {
    let root = FileManager.default.temporaryDirectory.appending(path: "StoreLaunchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var bundle: URL { root.appending(path: "TenFingers.app", directoryHint: .isDirectory) }
    var previous: URL { root.appending(path: "TenFingers.app.previous", directoryHint: .isDirectory) }

    init(withPrevious: Bool, marker: String = "new") throws {
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try marker.write(to: bundle.appending(path: "marker.txt"), atomically: true, encoding: .utf8)
        if withPrevious {
            try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
            try "old".write(to: previous.appending(path: "marker.txt"), atomically: true, encoding: .utf8)
        }
    }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
    func marker(_ url: URL) -> String? { try? String(contentsOf: url.appending(path: "marker.txt"), encoding: .utf8) }
}

private struct OpenFailure: Error, LocalizedError { var errorDescription: String? { "boom" } }

@MainActor @Test func successfulOpenCleansUpPreviousBundle() throws {
    let folder = try Folder(withPrevious: true)
    defer { folder.cleanUp() }
    let outcome = StoreLaunch.open({ try ModelStore.makeContainer(inMemory: true) }, bundleURL: folder.bundle)
    guard case .opened = outcome else { Issue.record("\(outcome)"); return }
    #expect(!FileManager.default.fileExists(atPath: folder.previous.path))
    #expect(folder.marker(folder.bundle) == "new")
}

@MainActor @Test func failedOpenKeepsPreviousAndOffersRollback() throws {
    let folder = try Folder(withPrevious: true)
    defer { folder.cleanUp() }
    let outcome = StoreLaunch.open({ throw OpenFailure() }, bundleURL: folder.bundle)
    guard case .failed(let message, let recovery) = outcome else { Issue.record("\(outcome)"); return }
    #expect(message.contains("boom"))
    #expect(FileManager.default.fileExists(atPath: folder.previous.path))
    #expect(recovery.canRollBack)
}

@MainActor @Test func failedOpenWithoutPreviousOffersNoRollback() throws {
    let folder = try Folder(withPrevious: false)
    defer { folder.cleanUp() }
    guard case .failed(_, let recovery) = StoreLaunch.open({ throw OpenFailure() }, bundleURL: folder.bundle) else {
        Issue.record("ожидалась ошибка"); return
    }
    #expect(!recovery.canRollBack)
}

@MainActor @Test func nonAppBundleOffersNoRollbackAndNoCleanUp() throws {
    let folder = try Folder(withPrevious: false)
    defer { folder.cleanUp() }
    let run = folder.root.appending(path: "debug", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folder.root.appending(path: "debug.previous"), withIntermediateDirectories: true)
    guard case .failed(_, let recovery) = StoreLaunch.open({ throw OpenFailure() }, bundleURL: run) else {
        Issue.record("ожидалась ошибка"); return
    }
    #expect(!recovery.canRollBack)
}

@MainActor @Test func storeErrorsKeepTheirMessages() throws {
    let folder = try Folder(withPrevious: false)
    defer { folder.cleanUp() }
    func message(_ error: any Error) -> String {
        guard case .failed(let text, _) = StoreLaunch.open({ throw error }, bundleURL: folder.bundle) else { return "" }
        return text
    }
    #expect(message(ModelStoreError.newerGeneration(stored: 9, current: 6)).contains("более новой версией"))
    #expect(message(ModelStoreError.newerStore(unknown: ["X"])).contains("более новой версией"))
    #expect(message(ModelStoreError.unreadableGeneration).contains("Не удалось прочитать версию базы"))
}

@MainActor @Test func rollBackRestoresPreviousAndRelaunches() throws {
    let folder = try Folder(withPrevious: true)
    defer { folder.cleanUp() }
    guard case .failed(_, let recovery) = StoreLaunch.open({ throw OpenFailure() }, bundleURL: folder.bundle) else {
        Issue.record("ожидалась ошибка"); return
    }
    var relaunched: URL?
    try recovery.rollBack(relauncher: { relaunched = $0 })
    #expect(folder.marker(folder.bundle) == "old")
    #expect(!FileManager.default.fileExists(atPath: folder.previous.path))
    #expect(relaunched == folder.bundle)
}

@MainActor @Test func rollBackFailureDoesNotRelaunch() throws {
    let folder = try Folder(withPrevious: false)
    defer { folder.cleanUp() }
    let recovery = StoreErrorRecovery(bundleURL: folder.bundle)
    var relaunched = false
    #expect(throws: (any Error).self) { try recovery.rollBack(relauncher: { _ in relaunched = true }) }
    #expect(!relaunched)
    #expect(folder.marker(folder.bundle) == "new")
}

@MainActor @Test func relaunchFailureAfterRollBackIsReported() throws {
    let folder = try Folder(withPrevious: true)
    defer { folder.cleanUp() }
    let recovery = StoreErrorRecovery(bundleURL: folder.bundle)
    #expect(throws: OpenFailure.self) { try recovery.rollBack(relauncher: { _ in throw OpenFailure() }) }
    // замена уже сделана: старая версия на месте, рядом с ней ничего лишнего
    #expect(folder.marker(folder.bundle) == "old")
}
