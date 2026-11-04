import Foundation

/// Шов файловой системы установщика: только перемещение и удаление. В тестах подменяется, чтобы уронить
/// конкретное перемещение (сбой второго `rename` при замене бандла).
protocol UpdateFileSystem: Sendable {
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

/// Живая реализация: `FileManager`.
struct LiveUpdateFileSystem: UpdateFileSystem {
    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

/// Шов сети: скачивает один файл и отдаёт путь к локальной копии. Установщик забирает файл себе (перемещает).
protocol UpdateDownloading: Sendable {
    func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

/// Живая загрузка через `URLSession`; ход загрузки — доля от 0 до 1 (если размер известен).
struct URLSessionDownloader: UpdateDownloading {
    func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = ProgressDelegate(progress)
        let (file, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: file)
            throw URLError(.badServerResponse)
        }
        // Системный временный файл переносим под своё имя (без папки: пустой папки после переноса не остаётся).
        let target = FileManager.default.temporaryDirectory.appending(path: "TenFingers-download-\(UUID().uuidString).zip")
        do { try FileManager.default.moveItem(at: file, to: target) } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return target
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let report: @Sendable (Double) -> Void
        init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            report(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {}
    }
}
