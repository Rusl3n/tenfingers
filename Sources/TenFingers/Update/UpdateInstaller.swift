import AppKit
import CryptoKit
import Foundation
import TypingCore

/// Причины, по которым установка отменена (спецификация фазы 7 §5.3). До замены бандла любая из них оставляет
/// и приложение, и базу как были.
enum UpdateError: Error, Equatable {
    /// Приложение запущено из временного пути App Translocation.
    case translocated
    /// Родительская папка бандла недоступна для записи.
    case notWritable
    /// База записана более новой схемой, чем та, что в обновлении.
    case olderGeneration(stored: Int, update: Int)
    case checksum
    case size
    case badBundle(String)
    case signature
    case backupFailed(String)
    case replaceFailed(String)
    case cancelled
    /// Маркер поколения рядом с базой нечитаем: неизвестно, какая версия писала базу.
    case unreadableGeneration
    /// Проверка перед установкой не удалась по другой причине (описание системы).
    case preflightFailed(String)
    /// Скачивание не удалось (сеть, ответ сервера).
    case downloadFailed(String)
    /// Бандл уже заменён, но помощник перезапуска не запустился.
    case relaunchFailed(String)

    /// Для этих ошибок объяснение — «перенесите приложение» или «скачайте .dmg»: нужна кнопка «Открыть страницу релиза».
    var suggestsReleasePage: Bool { self == .translocated || self == .notWritable }
}

/// Шаги установки, как их видит `UpdateChecker`; в тестах подменяется поддельным.
@MainActor protocol UpdateInstalling: AnyObject {
    func preflight(manifest: ReleaseManifest) throws
    func download(_ manifest: ReleaseManifest, zipURL: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> URL
    func backup(version: String) throws -> URL
    func replace(with newApp: URL) throws
    /// Убирает временную папку со скачанным бандлом (сбой замены, отмена после скачивания).
    func discardDownload(_ newApp: URL)
    func relaunch() throws
}

/// Установка обновления по шагам §5.3. Порядок вызовов (`preflight`, `download`, `backup`, `replace`, `relaunch`)
/// задаёт вызывающий; каждый метод при ошибке ничего не меняет, кроме своей временной папки, которую чистит.
@MainActor final class UpdateInstaller: UpdateInstalling {
    typealias Relauncher = @MainActor (_ bundleURL: URL) throws -> Void

    static let previousSuffix = ".previous"
    static let workFolderPrefix = ".TenFingers-update-"
    static let helperResourceName = "update-relaunch"
    static let expectedBundleIdentifier = "local.tenfingers"

    let bundleURL: URL
    let storeURL: URL
    let backupsDirectory: URL
    private let downloader: UpdateDownloading
    private let fileSystem: UpdateFileSystem
    private let now: () -> Date
    private let saveContext: () throws -> Void
    private let makeArchive: () throws -> Data
    private let relauncher: Relauncher

    init(bundleURL: URL, storeURL: URL, backupsDirectory: URL, downloader: UpdateDownloading,
         now: @escaping () -> Date, saveContext: @escaping () throws -> Void,
         makeArchive: @escaping () throws -> Data, fileSystem: UpdateFileSystem = LiveUpdateFileSystem(),
         relauncher: @escaping Relauncher = UpdateInstaller.launchHelperAndTerminate) {
        self.bundleURL = bundleURL
        self.storeURL = storeURL
        self.backupsDirectory = backupsDirectory
        self.downloader = downloader
        self.fileSystem = fileSystem
        self.now = now
        self.saveContext = saveContext
        self.makeArchive = makeArchive
        self.relauncher = relauncher
    }

    var parentDirectory: URL { bundleURL.deletingLastPathComponent() }
    var previousURL: URL { Self.previousURL(for: bundleURL) }

    static func previousURL(for bundleURL: URL) -> URL {
        bundleURL.deletingLastPathComponent().appending(path: bundleURL.lastPathComponent + previousSuffix)
    }

    // MARK: Шаги 1–2

    func preflight(manifest: ReleaseManifest) throws {
        if bundleURL.pathComponents.contains("AppTranslocation") { throw UpdateError.translocated }
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else { throw UpdateError.notWritable }
        if let stored = try SchemaGeneration.read(at: storeURL), stored > manifest.schemaGeneration {
            throw UpdateError.olderGeneration(stored: stored, update: manifest.schemaGeneration)
        }
    }

    // MARK: Шаг 3

    /// Скачивает, проверяет и распаковывает архив рядом с приложением; возвращает путь к новому `.app`
    /// (внутри `<родитель>/.TenFingers-update-<uuid>`). При любой ошибке временная папка удаляется.
    func download(_ manifest: ReleaseManifest, zipURL: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let work = parentDirectory.appending(path: Self.workFolderPrefix + UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
            let app = try await fetchAndVerify(manifest, zipURL: zipURL, work: work, progress: progress)
            return app
        } catch {
            try? FileManager.default.removeItem(at: work)
            // Отмена приходит и как `CancellationError`, и как `URLError(.cancelled)` из сессии; при отменённой
            // задаче любая ошибка — следствие отмены.
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw UpdateError.cancelled
            }
            throw error
        }
    }

    /// Убирает `<родитель>/.TenFingers-update-<uuid>` скачанного бандла. Чужой путь не трогает; если бандл на месте
    /// не стоит (замена не откатилась), папку оставляет: в ней единственная копия новой версии.
    func discardDownload(_ newApp: URL) {
        let work = newApp.deletingLastPathComponent().deletingLastPathComponent()
        guard work.lastPathComponent.hasPrefix(Self.workFolderPrefix),
              work.deletingLastPathComponent().standardizedFileURL.path == parentDirectory.standardizedFileURL.path,
              FileManager.default.fileExists(atPath: bundleURL.path) else { return }
        try? fileSystem.removeItem(at: work)
    }

    private func fetchAndVerify(_ manifest: ReleaseManifest, zipURL: URL, work: URL,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let downloaded = try await downloader.download(zipURL, progress: progress)
        let zip = work.appending(path: "update.zip")
        do { try FileManager.default.moveItem(at: downloaded, to: zip) } catch {
            try FileManager.default.copyItem(at: downloaded, to: zip)
            try? FileManager.default.removeItem(at: downloaded)
        }
        try Task.checkCancellation()

        let size = (try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? NSNumber)?.intValue
        guard size == manifest.zip.size else { throw UpdateError.size }
        let digest = try await Task.detached { try UpdateTools.sha256Hex(of: zip) }.value
        guard digest.lowercased() == manifest.zip.sha256.lowercased() else { throw UpdateError.checksum }
        try Task.checkCancellation()

        let extracted = work.appending(path: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
        let unpack = try await Task.detached {
            try UpdateTools.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
        }.value
        guard unpack.status == 0 else { throw UpdateError.badBundle("ditto: \(unpack.output)") }
        try? FileManager.default.removeItem(at: zip)
        try Task.checkCancellation()

        let names = try FileManager.default.contentsOfDirectory(atPath: extracted.path)
            .filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
        guard names == ["TenFingers.app"] else { throw UpdateError.badBundle("content: \(names.sorted())") }
        let app = extracted.appending(path: "TenFingers.app", directoryHint: .isDirectory)
        try Self.verifyInfo(of: app, against: manifest)

        let verify = try await Task.detached {
            try UpdateTools.run("/usr/bin/codesign", ["--verify", "--strict", app.path])
        }.value
        guard verify.status == 0 else { throw UpdateError.signature }
        try Task.checkCancellation()
        return app
    }

    /// `Info.plist` нового бандла должен совпасть с `release.json`.
    private static func verifyInfo(of app: URL, against manifest: ReleaseManifest) throws {
        let plistURL = app.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw UpdateError.badBundle("Info.plist")
        }
        guard info["CFBundleIdentifier"] as? String == expectedBundleIdentifier else {
            throw UpdateError.badBundle("CFBundleIdentifier")
        }
        guard info["CFBundleShortVersionString"] as? String == manifest.version else {
            throw UpdateError.badBundle("CFBundleShortVersionString")
        }
        let generation = (info["TFSchemaGeneration"] as? NSNumber)?.intValue
            ?? (info["TFSchemaGeneration"] as? String).flatMap { Int($0) }
        guard generation == manifest.schemaGeneration else { throw UpdateError.badBundle("TFSchemaGeneration") }
    }

    // MARK: Шаг 4

    /// Сохраняет контекст и делает обе копии. Ошибка любого шага — `.backupFailed`, неполной папки не остаётся.
    func backup(version: String) throws -> URL {
        do {
            try saveContext()
            return try StoreBackup.backupBeforeUpdate(
                storeDirectory: storeURL.deletingLastPathComponent(), backupsDirectory: backupsDirectory,
                version: version, now: now(), archive: makeArchive)
        } catch {
            throw UpdateError.backupFailed(String(describing: error))
        }
    }

    // MARK: Шаг 6

    /// `<бандл>.previous` (если есть — от прошлой попытки) удаляется, бандл уходит в `.previous`, новый встаёт на место.
    /// Если второе перемещение не удалось, `.previous` возвращается обратно.
    func replace(with newApp: URL) throws {
        let previous = previousURL
        if FileManager.default.fileExists(atPath: previous.path) {
            do { try fileSystem.removeItem(at: previous) } catch {
                throw UpdateError.replaceFailed("remove previous: \(error.localizedDescription)")
            }
        }
        do { try fileSystem.moveItem(at: bundleURL, to: previous) } catch {
            throw UpdateError.replaceFailed("move current: \(error.localizedDescription)")
        }
        do { try fileSystem.moveItem(at: newApp, to: bundleURL) } catch {
            let reason = error.localizedDescription
            do { try fileSystem.moveItem(at: previous, to: bundleURL) } catch {
                throw UpdateError.replaceFailed("move new: \(reason); restore failed: \(error.localizedDescription)")
            }
            throw UpdateError.replaceFailed("move new: \(reason)")
        }
    }

    // MARK: Шаг 7

    /// Запускает помощник и завершает приложение. Если помощник не запустился, приложение продолжает работать.
    func relaunch() throws {
        try relauncher(bundleURL)
    }

    /// Живой путь (решение 7): копия скрипта из ресурсов нового бандла во временной папке запускается через
    /// `/usr/bin/nohup /bin/sh <копия> <pid> <путь .app>` с выводом в `/dev/null`, затем `NSApp.terminate`.
    static func launchHelperAndTerminate(bundleURL: URL) throws {
        let script = bundleURL.appending(path: "Contents/Resources/\(helperResourceName).sh")
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "TenFingers-relaunch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: "\(helperResourceName).sh")
        do {
            try FileManager.default.copyItem(at: script, to: copy)
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/nohup")
            process.arguments = ["/bin/sh", copy.path, String(ProcessInfo.processInfo.processIdentifier), bundleURL.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        NSApp.terminate(nil)
    }

    // MARK: Шаг 8 и откат

    /// Новая версия открыла базу: `.previous` и временные папки обновления больше не нужны.
    /// Только для настоящего `.app`: при `swift run` «бандл» — папка сборки, рядом с ней ничего не трогаем.
    static func cleanUpAfterSuccessfulLaunch(bundleURL: URL, fileSystem: UpdateFileSystem = LiveUpdateFileSystem()) {
        guard bundleURL.pathExtension == "app" else { return }
        let previous = previousURL(for: bundleURL)
        if FileManager.default.fileExists(atPath: previous.path) { try? fileSystem.removeItem(at: previous) }
        let parent = bundleURL.deletingLastPathComponent()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        where name.hasPrefix(workFolderPrefix) {
            try? fileSystem.removeItem(at: parent.appending(path: name))
        }
    }

    /// Обратная замена (решение 9): `.previous` встаёт на место бандла, а неудавшаяся версия убирается в
    /// временную папку обновления. Нет `.previous` — ошибка; база не затрагивается.
    static func rollBack(bundleURL: URL, fileSystem: UpdateFileSystem = LiveUpdateFileSystem()) throws {
        let previous = previousURL(for: bundleURL)
        guard FileManager.default.fileExists(atPath: previous.path) else {
            throw UpdateError.replaceFailed("no previous version")
        }
        let parent = bundleURL.deletingLastPathComponent()
        let aside = parent.appending(path: "\(workFolderPrefix)rollback-\(UUID().uuidString)")
        let hadCurrent = FileManager.default.fileExists(atPath: bundleURL.path)
        if hadCurrent {
            do { try fileSystem.moveItem(at: bundleURL, to: aside) } catch {
                throw UpdateError.replaceFailed("move current: \(error.localizedDescription)")
            }
        }
        do { try fileSystem.moveItem(at: previous, to: bundleURL) } catch {
            let reason = error.localizedDescription
            if hadCurrent { try? fileSystem.moveItem(at: aside, to: bundleURL) }
            throw UpdateError.replaceFailed("move previous: \(reason)")
        }
        if hadCurrent { try? fileSystem.removeItem(at: aside) }
    }
}

/// Внешние команды и хэш; выполняются вне главного потока.
enum UpdateTools {
    struct Result: Sendable { let status: Int32; let output: String }

    static func run(_ path: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
