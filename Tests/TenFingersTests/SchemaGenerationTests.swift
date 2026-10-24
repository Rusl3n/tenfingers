import Foundation
import SwiftData
import Testing
@testable import TenFingers

extension SchemaGeneration {
    /// Только для тестов: `nil` и при отсутствии, и при нечитаемом маркере.
    /// Решения об открытии базы принимаются только через `read(at:)`.
    static func stored(at storeURL: URL) -> Int? { (try? read(at: storeURL)) ?? nil }
}

private func temporaryStoreURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersGen-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("TenFingers.store")
}

/// Содержимое файлов базы (кроме `-shm`, который SQLite обновляет при любом открытии): имя -> данные.
private func contents(_ directory: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where !name.hasSuffix("-shm") {
        result[name] = try Data(contentsOf: directory.appendingPathComponent(name))
    }
    return result
}

@Test func canOpenDecision() {
    #expect(SchemaGeneration.canOpen(stored: nil, current: 2))
    #expect(SchemaGeneration.canOpen(stored: 2, current: 2))
    #expect(SchemaGeneration.canOpen(stored: 1, current: 2))
    #expect(!SchemaGeneration.canOpen(stored: 3, current: 2))
}

@Test func markerLivesNextToStore() {
    let store = URL(fileURLWithPath: "/tmp/x/TenFingers.store")
    #expect(SchemaGeneration.markerURL(forStore: store).path == "/tmp/x/TenFingers.store.generation")
}

@Test func markerRoundTrips() throws {
    let url = try temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(SchemaGeneration.stored(at: url) == nil)
    try SchemaGeneration.write(5, at: url)
    #expect(SchemaGeneration.stored(at: url) == 5)
    try SchemaGeneration.write(7, at: url)
    #expect(SchemaGeneration.stored(at: url) == 7)
}

/// База без маркера (существующая база пользователя) открывается, маркер создаётся.
@MainActor @Test func storeWithoutMarkerOpensAndGetsMarker() throws {
    let url = try temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    do {
        let old = Schema(LegacySchemaPhase2.models)
        let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url))
        container.mainContext.insert(LegacySchemaPhase2.CounterRecord(name: "old"))
        try container.mainContext.save()
    }
    #expect(SchemaGeneration.stored(at: url) == nil)
    let container = try ModelStore.makeContainer(at: url)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<CounterRecord>()) == 1)
    #expect(SchemaGeneration.stored(at: url) == SchemaGeneration.current)
}

/// Маркер не уменьшается: при открытии записывается максимум из хранимого и текущего.
@MainActor @Test func markerNeverDecreases() throws {
    let url = try temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try SchemaGeneration.write(SchemaGeneration.current - 1, at: url)
    _ = try ModelStore.makeContainer(at: url)
    #expect(SchemaGeneration.stored(at: url) == SchemaGeneration.current)
}

/// База с маркером новее текущего поколения не открывается и не меняется, маркер остаётся прежним.
/// Снимки снимаются только после закрытия всех файлов базы (см. `waitUntilStoreFilesClosed`).
@MainActor @Test func newerGenerationIsRefusedAndLeftUntouched() async throws {
    let url = try temporaryStoreURL()
    let directory = url.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let container = try ModelStore.makeContainer(at: url)
        container.mainContext.insert(CounterRecord(name: "probe"))
        try container.mainContext.save()
    }
    try SchemaGeneration.write(SchemaGeneration.current + 1, at: url)
    try await waitUntilStoreFilesClosed(in: directory)
    let before = try contents(directory)
    #expect(before["TenFingers.store"] != nil)

    #expect(throws: ModelStoreError.newerGeneration(stored: SchemaGeneration.current + 1,
                                                    current: SchemaGeneration.current)) {
        _ = try ModelStore.makeContainer(at: url)
    }
    try await waitUntilStoreFilesClosed(in: directory)
    #expect(try contents(directory) == before)
    #expect(SchemaGeneration.stored(at: url) == SchemaGeneration.current + 1)
    try expectNoSideFiles(directory, before: before)
}

/// База не открывалась: набор файлов тот же, журнала отката нет.
private func expectNoSideFiles(_ directory: URL, before: [String: Data]) throws {
    let names = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { !$0.hasSuffix("-shm") })
    #expect(names == Set(before.keys))
    #expect(!names.contains { $0.hasSuffix("-journal") })
}

/// Маркер есть, но нечитаем (мусор, пусто, отрицательное число, переполнение, папка): база не открывается и не меняется.
@MainActor @Test(arguments: ["мусор", "", "-1", "99999999999999999999999", "2abc"])
func unreadableMarkerIsRefusedAndLeftUntouched(garbage: String) async throws {
    let url = try temporaryStoreURL()
    let directory = url.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let container = try ModelStore.makeContainer(at: url)
        container.mainContext.insert(CounterRecord(name: "probe"))
        try container.mainContext.save()
    }
    try garbage.write(to: SchemaGeneration.markerURL(forStore: url), atomically: true, encoding: .utf8)
    try await waitUntilStoreFilesClosed(in: directory)
    let before = try contents(directory)

    #expect(throws: ModelStoreError.unreadableGeneration) {
        _ = try ModelStore.makeContainer(at: url)
    }
    try await waitUntilStoreFilesClosed(in: directory)
    #expect(try contents(directory) == before)
    try expectNoSideFiles(directory, before: before)
}

@MainActor @Test func markerThatIsADirectoryIsRefused() throws {
    let url = try temporaryStoreURL()
    let directory = url.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try ModelStore.makeContainer(at: url)
    let marker = SchemaGeneration.markerURL(forStore: url)
    try FileManager.default.removeItem(at: marker)
    try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
    #expect(throws: ModelStoreError.unreadableGeneration) {
        _ = try ModelStore.makeContainer(at: url)
    }
}

@Test func readDistinguishesAbsentFromUnreadable() throws {
    let url = try temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(try SchemaGeneration.read(at: url) == nil)
    try "x".write(to: SchemaGeneration.markerURL(forStore: url), atomically: true, encoding: .utf8)
    #expect(throws: SchemaGeneration.UnreadableMarker()) { _ = try SchemaGeneration.read(at: url) }
    try SchemaGeneration.write(3, at: url)
    #expect(try SchemaGeneration.read(at: url) == 3)
}
