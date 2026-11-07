import Foundation
import SQLite3
import SwiftData
import Testing
@testable import TenFingers

private func makeFolder(_ name: String = "StoreBackupTests") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Число строк таблицы в базе (только чтение).
func rowCount(_ table: String, in url: URL) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw StoreBackup.Failure.sqlite("open") }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table);", -1, &statement, nil) == SQLITE_OK else {
        throw StoreBackup.Failure.sqlite("prepare")
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreBackup.Failure.sqlite("step") }
    return Int(sqlite3_column_int64(statement, 0))
}

@MainActor private func insertSessions(_ count: Int, into context: ModelContext) throws {
    let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    for index in 0..<count {
        context.insert(SessionRecord(
            mode: "course", language: "ru", lessonId: "ru.1.\(index)", startedAt: base, endedAt: base.addingTimeInterval(60),
            logicalDay: "2026-09-21", activeSeconds: 60, chars: 100, errorCount: 1, cpm: 100, accuracy: 0.99,
            completed: true, hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 1, exerciseKind: "check",
            pinkyPresses: 1, pinkyErrors: 0, source: nil))
    }
    try context.save()
}

@MainActor @Test func backupOfOpenWalStoreIsConsistent() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appending(path: "TenFingers.store")
    let container = try ModelStore.makeContainer(at: storeURL)   // остаётся открытой: база в режиме WAL
    try insertSessions(7, into: container.mainContext)

    let copy = root.appending(path: "copy.store")
    try StoreBackup.copyDatabase(from: storeURL, to: copy)
    try StoreBackup.integrityCheck(copy)
    #expect(try rowCount("ZSESSIONRECORD", in: copy) == 7)
    #expect(try rowCount("ZSESSIONRECORD", in: storeURL) == 7)
    withExtendedLifetime(container) {}
}

@Test func integrityCheckRejectsGarbage() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "bad.store")
    try Data(repeating: 0x41, count: 8192).write(to: file)
    #expect(throws: (any Error).self) { try StoreBackup.integrityCheck(file) }
}

@Test func copyDatabaseFailsForMissingStore() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(throws: (any Error).self) {
        try StoreBackup.copyDatabase(from: root.appending(path: "none.store"), to: root.appending(path: "out.store"))
    }
}

@MainActor @Test func backupBeforeUpdateWritesAllPartsAndKeepsThree() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let storeDirectory = root.appending(path: "TenFingers", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    let storeURL = storeDirectory.appending(path: "TenFingers.store")
    let container = try ModelStore.makeContainer(at: storeURL)
    try insertSessions(4, into: container.mainContext)
    try "extra".write(to: storeDirectory.appending(path: "note.txt"), atomically: true, encoding: .utf8)
    let (defaults, name) = makeTestDefaults("StoreBackupTests-")
    defer { removeTestDefaults(name) }
    let backups = root.appending(path: "TenFingers.backups", directoryHint: .isDirectory)
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var folders: [URL] = []
    for index in 0..<4 {
        let folder = try StoreBackup.backupBeforeUpdate(
            storeDirectory: storeDirectory, backupsDirectory: backups, version: "2.\(9 - index).0",
            now: start.addingTimeInterval(Double(index) * 60)) {
                try ProgressArchive.export(context: container.mainContext, defaults: defaults)
            }
        folders.append(folder)
        // разные даты изменения: порядок по времени, а не по имени
        try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(Double(index) * 60)],
                                              ofItemAtPath: folder.path)
    }
    let last = folders[3]
    #expect(last.lastPathComponent.hasPrefix("before-update-2.6.0-"))
    #expect(try rowCount("ZSESSIONRECORD", in: last.appending(path: "TenFingers.store")) == 4)
    try StoreBackup.integrityCheck(last.appending(path: "TenFingers.store"))
    #expect(FileManager.default.fileExists(atPath: last.appending(path: "TenFingers.store.generation").path))
    #expect(FileManager.default.fileExists(atPath: last.appending(path: "note.txt").path))
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: last.path)) ==
            ["TenFingers.store", "TenFingers.store.generation", "note.txt", "progress.tenfingers"])
    let archive = try ProgressArchive.decode(Data(contentsOf: last.appending(path: "progress.tenfingers")))
    #expect(archive.sessions.count == 4)
    let present = try FileManager.default.contentsOfDirectory(atPath: backups.path).filter { $0.hasPrefix("before-update-") }
    #expect(Set(present) == Set(folders.dropFirst().map(\.lastPathComponent)))
    // исходная база не тронута
    #expect(try rowCount("ZSESSIONRECORD", in: storeURL) == 4)
}

@MainActor @Test func failedArchiveRemovesFolderAndKeepsOlderOnes() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let storeDirectory = root.appending(path: "TenFingers", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    let container = try ModelStore.makeContainer(at: storeDirectory.appending(path: "TenFingers.store"))
    try insertSessions(1, into: container.mainContext)
    let backups = root.appending(path: "backups", directoryHint: .isDirectory)
    struct Boom: Error {}
    #expect(throws: Boom.self) {
        _ = try StoreBackup.backupBeforeUpdate(storeDirectory: storeDirectory, backupsDirectory: backups,
                                               version: "2.0.0", now: .now) { throw Boom() }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path).isEmpty)
    // архив, не являющийся архивом прогресса, тоже отменяет копию
    #expect(throws: (any Error).self) {
        _ = try StoreBackup.backupBeforeUpdate(storeDirectory: storeDirectory, backupsDirectory: backups,
                                               version: "2.0.0", now: .now) { Data("{}".utf8) }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path).isEmpty)
    withExtendedLifetime(container) {}
}

@Test func missingStoreIsAnError() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(throws: StoreBackup.Failure.missingStore) {
        _ = try StoreBackup.backupBeforeUpdate(storeDirectory: root, backupsDirectory: root.appending(path: "b"),
                                               version: "2.0.0", now: .now) { Data() }
    }
}

/// Базы профилей копируются через Online Backup в ту же относительную папку; сырого `Profiles/` в копии нет.
@MainActor @Test func backupBeforeUpdateCopiesProfileStoresConsistently() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let storeDirectory = root.appending(path: "TenFingers", directoryHint: .isDirectory)
    let profile = Profile(id: UUID(), name: "Второй", createdAt: .now, isPrimary: false)
    let profileStore = ProfilePaths.storeURL(for: profile, root: storeDirectory)
    let missing = ProfilePaths.storeURL(for: Profile(id: UUID(), name: "Нет", createdAt: .now, isPrimary: false),
                                        root: storeDirectory)
    try FileManager.default.createDirectory(at: profileStore.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rootContainer = try ModelStore.makeContainer(at: storeDirectory.appending(path: "TenFingers.store"))
    let profileContainer = try ModelStore.makeContainer(at: profileStore)   // открыта: WAL
    try insertSessions(2, into: rootContainer.mainContext)
    try insertSessions(5, into: profileContainer.mainContext)
    try "x".write(to: profileStore.deletingLastPathComponent().appending(path: "note.txt"), atomically: true, encoding: .utf8)
    let (defaults, name) = makeTestDefaults("StoreBackupTests-")
    defer { removeTestDefaults(name) }
    let backups = root.appending(path: "backups", directoryHint: .isDirectory)

    let folder = try StoreBackup.backupBeforeUpdate(
        storeDirectory: storeDirectory, backupsDirectory: backups, version: "3.0.0", now: .now,
        profileStores: [profileStore, missing]) {
            try ProgressArchive.export(context: rootContainer.mainContext, defaults: defaults)
        }
    let relative = "Profiles/\(profile.id.uuidString)"
    let copy = folder.appending(path: "\(relative)/TenFingers.store")
    #expect(try rowCount("ZSESSIONRECORD", in: copy) == 5)
    try StoreBackup.integrityCheck(copy)
    #expect(try rowCount("ZSESSIONRECORD", in: folder.appending(path: "TenFingers.store")) == 2)
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "\(relative)/TenFingers.store.generation").path))
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "\(relative)/note.txt").path))
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: relative).path))
            == ["TenFingers.store", "TenFingers.store.generation", "note.txt"])
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Profiles").path))
            == [profile.id.uuidString])
    #expect(try rowCount("ZSESSIONRECORD", in: profileStore) == 5)
    withExtendedLifetime([rootContainer, profileContainer]) {}
}

/// Архив профиля не лежит в копии под именем корневого.
@Test func archiveNameCarriesProfileSuffix() {
    #expect(StoreBackup.archiveName(suffix: "") == "progress.tenfingers")
    #expect(StoreBackup.archiveName(suffix: "-1a2b3c4d") == "progress-1a2b3c4d.tenfingers")
}

@MainActor @Test func backupBeforeUpdateNamesArchiveWithSuffix() throws {
    let root = try makeFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let storeDirectory = root.appending(path: "TenFingers", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    let container = try ModelStore.makeContainer(at: storeDirectory.appending(path: "TenFingers.store"))
    let (defaults, name) = makeTestDefaults("StoreBackupSuffix-")
    defer { removeTestDefaults(name) }
    let folder = try StoreBackup.backupBeforeUpdate(
        storeDirectory: storeDirectory, backupsDirectory: root.appending(path: "b"), version: "3.0.0", now: .now,
        archiveNameSuffix: "-1a2b3c4d") {
            try ProgressArchive.export(context: container.mainContext, defaults: defaults)
        }
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "progress-1a2b3c4d.tenfingers").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "progress.tenfingers").path))
    withExtendedLifetime(container) {}
}
