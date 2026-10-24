import Darwin
import Foundation
import SwiftData
import Testing
@testable import TenFingers

/// Файлы в папке, которые этот процесс сейчас держит открытыми (имена файлов).
func openFileNames(in directory: URL) -> [String] {
    let folder = directory.lastPathComponent
    var names: [String] = []
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    for descriptor in 0..<getdtablesize() where fcntl(descriptor, F_GETPATH, &path) == 0 {
        let url = path.withUnsafeBufferPointer { URL(fileURLWithFileSystemRepresentation: $0.baseAddress!,
                                                     isDirectory: false, relativeTo: nil) }
        if url.deletingLastPathComponent().lastPathComponent == folder { names.append(url.lastPathComponent) }
    }
    return names.sorted()
}

struct StoreStillOpen: Error, CustomStringConvertible {
    let files: [String]
    var description: String { "база не закрылась за отведённое время, открыты: \(files)" }
}

/// Ждёт, пока процесс закроет все файлы базы в папке.
///
/// Core Data закрывает соединение SQLite контейнера не в момент его освобождения, а позже, на своём
/// фоновом потоке, и при закрытии переносит WAL в основной файл (checkpoint). Снимок файлов, снятый
/// раньше, ловит базу посреди этого и расходится с последующим. Ожидание делает снимок детерминированным.
func waitUntilStoreFilesClosed(in directory: URL, timeout: Duration = .seconds(10)) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while true {
        let open = openFileNames(in: directory)
        if open.isEmpty { return }
        if clock.now >= deadline { throw StoreStillOpen(files: open) }
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// Ожидание не пустое: открытую базу помощник видит, после освобождения контейнера — дожидается закрытия.
@MainActor @Test func openStoreFilesAreSeenUntilClosed() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersOpen-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let container = try ModelStore.makeContainer(at: directory.appendingPathComponent("TenFingers.store"))
        container.mainContext.insert(CounterRecord(name: "probe"))
        try container.mainContext.save()
        #expect(openFileNames(in: directory).contains("TenFingers.store"))
    }
    try await waitUntilStoreFilesClosed(in: directory)
    #expect(openFileNames(in: directory).isEmpty)
}
