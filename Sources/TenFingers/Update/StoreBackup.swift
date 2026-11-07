import Foundation
import SQLite3

/// Резервная копия базы перед обновлением (спецификация фазы 7 §5.3, шаг 4): копия SQLite через Online Backup API
/// (то же, что `sqlite3 .backup` в `build-app.sh`), остальные файлы папки базы и архив прогресса.
/// Исходная база только читается.
enum StoreBackup {
    enum Failure: Error, Equatable {
        case sqlite(String)
        case integrity(String)
        case archiveMismatch
        case missingStore
    }

    static let storeFileName = "TenFingers.store"
    static let archiveFileName = "progress.tenfingers"
    /// `progress<суффикс>.tenfingers`: архив профиля, не основного, не лежит под именем корневого.
    static func archiveName(suffix: String) -> String {
        guard !suffix.isEmpty else { return archiveFileName }
        let url = URL(filePath: archiveFileName)
        return url.deletingPathExtension().lastPathComponent + suffix + "." + url.pathExtension
    }

    static let folderPrefix = "before-update-"
    static let keptFolders = 3

    /// Копирует базу (вместе с содержимым `-wal`) в один файл. Источник открыт только для чтения; приёмник после
    /// копирования переводится в журнал `DELETE`, чтобы копия не зависела от файлов `-wal` и `-shm`.
    static func copyDatabase(from store: URL, to destination: URL) throws {
        var source: OpaquePointer?
        guard sqlite3_open_v2(store.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let source else {
            let message = describe(source)
            sqlite3_close(source)
            throw Failure.sqlite("open source: \(message)")
        }
        defer { sqlite3_close(source) }
        var target: OpaquePointer?
        guard sqlite3_open_v2(destination.path, &target, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let target else {
            let message = describe(target)
            sqlite3_close(target)
            throw Failure.sqlite("open destination: \(message)")
        }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", source, "main") else {
            throw Failure.sqlite("backup init: \(describe(target))")
        }
        var result = SQLITE_OK
        for _ in 0..<100 {
            result = sqlite3_backup_step(backup, -1)
            guard result == SQLITE_BUSY || result == SQLITE_LOCKED else { break }
            sqlite3_sleep(100)
        }
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else {
            throw Failure.sqlite("backup step: \(result), finish: \(finished), \(describe(target))")
        }
        var mode: OpaquePointer?
        guard sqlite3_prepare_v2(target, "PRAGMA journal_mode=DELETE;", -1, &mode, nil) == SQLITE_OK else {
            throw Failure.sqlite("journal mode: \(describe(target))")
        }
        defer { sqlite3_finalize(mode) }
        guard sqlite3_step(mode) == SQLITE_ROW,
              mode.flatMap({ sqlite3_column_text($0, 0) }).map({ String(cString: $0) })?.lowercased() == "delete" else {
            throw Failure.sqlite("journal mode: \(describe(target))")
        }
    }

    /// `PRAGMA integrity_check`: бросает, если ответ не `ok`. База открывается только для чтения.
    static func integrityCheck(_ url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            let message = describe(db)
            sqlite3_close(db)
            throw Failure.sqlite("open: \(message)")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check;", -1, &statement, nil) == SQLITE_OK else {
            throw Failure.sqlite("prepare: \(describe(db))")
        }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
        }
        guard rows == ["ok"] else { throw Failure.integrity(rows.prefix(3).joined(separator: "; ")) }
    }

    /// Папка `before-update-<версия>-<дата_время>` в `backupsDirectory` с копией базы, остальными файлами папки базы
    /// (кроме `TenFingers.store`, `-wal`, `-shm`) и архивом прогресса. Архив перечитывается; совпасть должны
    /// байты, число записей по каждой модели и сводка. Ошибка любой части удаляет неполную папку и бросает.
    /// После успеха остаются три последние папки `before-update-*`.
    /// `profileStores` — базы неосновных профилей (`<storeDirectory>/Profiles/<uuid>/TenFingers.store`): каждая
    /// копируется так же, через Online Backup, в ту же относительную папку копии; несуществующие пропускаются.
    /// Сырой `Profiles/` в копию не попадает (там живые базы с `-wal`/`-shm`).
    static func backupBeforeUpdate(storeDirectory: URL, backupsDirectory: URL, version: String, now: Date,
                                   profileStores: [URL] = [], archiveNameSuffix: String = "",
                                   archive: () throws -> Data) throws -> URL {
        let fileManager = FileManager.default
        let store = storeDirectory.appending(path: storeFileName)
        guard fileManager.fileExists(atPath: store.path) else { throw Failure.missingStore }
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        let stem = "\(folderPrefix)\(version)-\(ProgressArchive.timestamp(now))"
        var folder = backupsDirectory.appending(path: stem, directoryHint: .isDirectory)
        var suffix = 2
        while fileManager.fileExists(atPath: folder.path) {
            folder = backupsDirectory.appending(path: "\(stem)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            let copy = folder.appending(path: storeFileName)
            try copyDatabase(from: store, to: copy)
            try integrityCheck(copy)
            // Переключение журнала в DELETE может оставить рядом `-shm`; все соединения с копией уже закрыты.
            for suffix in ["-wal", "-shm"] {
                let side = URL(filePath: copy.path + suffix)
                if fileManager.fileExists(atPath: side.path) { try fileManager.removeItem(at: side) }
            }

            for name in try fileManager.contentsOfDirectory(atPath: storeDirectory.path) {
                if name == storeFileName || name.hasSuffix("-wal") || name.hasSuffix("-shm") { continue }
                if name == profilesFolderName { continue }
                try fileManager.copyItem(at: storeDirectory.appending(path: name), to: folder.appending(path: name))
            }
            for profileStore in profileStores {
                try backupProfile(store: profileStore, storeDirectory: storeDirectory, into: folder)
            }

            let data = try archive()
            let expected = try ProgressArchive.decodeStructure(data)
            let archiveURL = folder.appending(path: archiveName(suffix: archiveNameSuffix))
            try data.write(to: archiveURL, options: .atomic)
            let written = try Data(contentsOf: archiveURL)
            let reread = try ProgressArchive.decodeStructure(written)
            guard written == data, reread.recordCounts == expected.recordCounts,
                  reread.recordCountsByModel == expected.recordCountsByModel,
                  ProgressArchive.summary(reread) == ProgressArchive.summary(expected) else {
                throw Failure.archiveMismatch
            }
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        rotate(backupsDirectory: backupsDirectory, keeping: folder)
        return folder
    }

    static let profilesFolderName = "Profiles"

    /// Копия одной базы профиля и остальных файлов её папки (по образцу корня). Нет папки или базы — пропуск.
    private static func backupProfile(store: URL, storeDirectory: URL, into folder: URL) throws {
        let fileManager = FileManager.default
        let source = store.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: store.path) else { return }
        let rootPath = storeDirectory.standardizedFileURL.path + "/"
        let sourcePath = source.standardizedFileURL.path
        let relative = sourcePath.hasPrefix(rootPath)
            ? String(sourcePath.dropFirst(rootPath.count))
            : "\(profilesFolderName)/\(source.lastPathComponent)"
        let target = folder.appending(path: relative, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        let copy = target.appending(path: store.lastPathComponent)
        try copyDatabase(from: store, to: copy)
        try integrityCheck(copy)
        for suffix in ["-wal", "-shm"] {
            let side = URL(filePath: copy.path + suffix)
            if fileManager.fileExists(atPath: side.path) { try fileManager.removeItem(at: side) }
        }
        for name in try fileManager.contentsOfDirectory(atPath: source.path) {
            if name == store.lastPathComponent || name.hasSuffix("-wal") || name.hasSuffix("-shm") { continue }
            try fileManager.copyItem(at: source.appending(path: name), to: target.appending(path: name))
        }
    }

    /// Оставляет `keptFolders` последних папок `before-update-*` (по дате изменения), текущая остаётся всегда.
    /// Ошибки удаления старых папок не отменяют обновление.
    private static func rotate(backupsDirectory: URL, keeping current: URL) {
        let fileManager = FileManager.default
        let items = (try? fileManager.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])) ?? []
        let others = items
            .filter { $0.lastPathComponent.hasPrefix(folderPrefix) && $0.lastPathComponent != current.lastPathComponent }
            .map { url -> (URL, Date) in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (url, date ?? .distantPast)
            }
            .sorted { ($0.1, $0.0.lastPathComponent) > ($1.1, $1.0.lastPathComponent) }
        for (url, _) in others.dropFirst(keptFolders - 1) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func describe(_ db: OpaquePointer?) -> String {
        db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
    }
}
