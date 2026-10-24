import CoreData
import Foundation
import SwiftData

/// Снимок текущей схемы — отправная точка для будущих миграций (`SchemaMigrationPlan`).
/// Версия 1.0.0 совпадает с той, что SwiftData записывал в базу и без `VersionedSchema`,
/// а хеши сущностей от версии не зависят, поэтому существующая база открывается как есть.
/// `AdaptiveUnlock` и `SessionRecord.source` добавлены внутри той же версии: изменение аддитивное,
/// SwiftData переносит базу облегчённой миграцией (проверено тестом на базе прежней схемы).
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            SessionRecord.self, LessonProgress.self, KeyStat.self, BigramStat.self, DayRecord.self,
            CounterRecord.self, AdaptiveState.self, CustomText.self, AdaptiveUnlock.self,
        ]
    }
}

enum ModelStoreError: Error, Equatable {
    /// В базе есть модели, которых эта версия не знает: базу записала более новая версия приложения.
    case newerStore(unknown: [String])
}

enum ModelStore {
    static let schema = Schema(versionedSchema: SchemaV1.self)

    /// Хранилище в ~/Library/Application Support/TenFingers/TenFingers.store.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema,
                                      configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        let directory = URL.applicationSupportDirectory.appending(path: "TenFingers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try makeContainer(at: directory.appending(path: "TenFingers.store"))
    }

    /// Открывает базу по адресу. Базу более новой версии не открывает и не трогает (иначе SwiftData
    /// «смигрировал» бы её к старой схеме и потерял данные новых моделей).
    static func makeContainer(at url: URL) throws -> ModelContainer {
        try checkCompatibility(storeAt: url)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Читает только метаданные базы (файлы не меняются) и сравнивает список сущностей со схемой.
    static func checkCompatibility(storeAt url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] ?? [:]
        let unknown = unknownEntities(store: Set(hashes.keys), known: Set(schema.entities.map(\.name)))
        if !unknown.isEmpty { throw ModelStoreError.newerStore(unknown: unknown) }
    }

    /// Сущности базы, которых нет в схеме, по алфавиту. Пустой список — базу можно открывать.
    static func unknownEntities(store: Set<String>, known: Set<String>) -> [String] {
        store.subtracting(known).sorted()
    }
}
