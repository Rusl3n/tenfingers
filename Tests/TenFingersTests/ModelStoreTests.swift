import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import TenFingers

/// Модель «из будущей версии»: её нет в текущей схеме.
@Model final class FutureRecord {
    var name: String

    init(name: String) {
        self.name = name
    }
}

private func temporaryStoreURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersStore-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("TenFingers.store")
}

/// Размер, дата изменения и содержимое файлов базы. `-shm` (общая память индекса WAL) пропускаем:
/// SQLite обновляет её при любом открытии, данных в ней нет.
private func fingerprint(_ directory: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where !name.hasSuffix("-shm") {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        let content = SHA256.hash(data: try Data(contentsOf: directory.appendingPathComponent(name))).description
        result[name] = "\(size)@\(modified)#\(content)"
    }
    return result
}

@Test func storeWithKnownEntitiesIsCompatible() {
    #expect(ModelStore.unknownEntities(store: ["SessionRecord", "KeyStat"],
                                       known: ["SessionRecord", "KeyStat", "DayRecord"]).isEmpty)
    #expect(ModelStore.unknownEntities(store: [], known: ["SessionRecord"]).isEmpty)
}

@Test func storeWithExtraEntityIsNewer() {
    #expect(ModelStore.unknownEntities(store: ["SessionRecord", "Zeta", "Achievement"],
                                       known: ["SessionRecord", "KeyStat"]) == ["Achievement", "Zeta"])
}

@Test func currentSchemaIsVersionOne() {
    #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    let names = Set(ModelStore.schema.entities.map(\.name))
    #expect(names.isSuperset(of: ["SessionRecord", "LessonProgress", "KeyStat", "BigramStat", "DayRecord",
                                  "CounterRecord", "AdaptiveState", "CustomText"]))
}

/// Хранилище более новой версии (с моделью, которой текущая схема не знает) не открывается и не меняется.
@MainActor @Test func newerStoreIsRefusedAndLeftUntouched() throws {
    let url = try temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    do {
        let newer = Schema(SchemaV1.models + [FutureRecord.self])
        let container = try ModelContainer(for: newer, configurations: ModelConfiguration(schema: newer, url: url))
        container.mainContext.insert(FutureRecord(name: "из будущего"))
        try container.mainContext.save()
    }
    let before = try fingerprint(url.deletingLastPathComponent())
    #expect(before["TenFingers.store"] != nil)

    #expect(throws: ModelStoreError.newerStore(unknown: ["FutureRecord"])) {
        _ = try ModelStore.makeContainer(at: url)
    }
    #expect(try fingerprint(url.deletingLastPathComponent()) == before)
}

/// Хранилище текущей версии открывается повторно, данные на месте.
@MainActor @Test func currentStoreReopensWithData() throws {
    let url = try temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    do {
        let container = try ModelStore.makeContainer(at: url)
        container.mainContext.insert(CounterRecord(name: "probe"))
        try container.mainContext.save()
    }
    let container = try ModelStore.makeContainer(at: url)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<CounterRecord>()) == 1)
}

/// Проверка на копии настоящей базы: `TENFINGERS_PROBE_STORE=<папка с TenFingers.store> swift test`.
/// Папка копируется во временную, исходные файлы не открываются.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["TENFINGERS_PROBE_STORE"] != nil))
func probeStoreCopyOpens() throws {
    let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TENFINGERS_PROBE_STORE"]))
    let url = try temporaryStoreURL()
    let directory = url.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: directory) }
    for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
        try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: directory.appendingPathComponent(name))
    }
    let container = try ModelStore.makeContainer(at: url)
    let context = container.mainContext
    let sessions = try context.fetchCount(FetchDescriptor<SessionRecord>())
    let lessons = try context.fetchCount(FetchDescriptor<LessonProgress>())
    let keys = try context.fetchCount(FetchDescriptor<KeyStat>())
    let days = try context.fetchCount(FetchDescriptor<DayRecord>())
    print("probe: sessions=\(sessions) lessons=\(lessons) keyStats=\(keys) days=\(days)")
    #expect(sessions > 0)
}

/// База, созданная прежним кодом (схема без версии), открывается схемой `SchemaV1` без потери данных.
@MainActor @Test func storeFromUnversionedSchemaOpens() throws {
    let url = try temporaryStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    do {
        let old = Schema([
            SessionRecord.self, LessonProgress.self, KeyStat.self, BigramStat.self, DayRecord.self,
            CounterRecord.self, AdaptiveState.self, CustomText.self,
        ])
        let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url))
        container.mainContext.insert(CounterRecord(name: "old"))
        container.mainContext.insert(AdaptiveState(language: "ru", unlockedCount: 9))
        try container.mainContext.save()
    }
    let container = try ModelStore.makeContainer(at: url)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<CounterRecord>()) == 1)
    #expect(try container.mainContext.fetch(FetchDescriptor<AdaptiveState>()).first?.unlockedCount == 9)
}
