import CoreData
import Foundation
import SwiftData

/// Снимок текущей схемы — отправная точка для будущих миграций (`SchemaMigrationPlan`).
///
/// Две формы «1.0.0» существуют на практике, хеши сущностей у них разные:
/// - V0 — схема фазы 2 (без `AdaptiveUnlock` и `SessionRecord.source`; поколение 1). Задокументирована в тестах
///   как `LegacySchemaPhase2` (Tests/TenFingersTests/SchemaMigrationTests.swift) и служит «V0»
///   для будущего `SchemaMigrationPlan`;
/// - текущая (поколение 2 и выше) — `SchemaV1` ниже.
/// Базу V0 текущая схема открывает облегчённой миграцией; обратной дороги нет: после этого старая версия
/// приложения базу не прочтёт. Чтобы вернуть старую копию: закройте приложение, замените содержимое
/// ~/Library/Application Support/TenFingers файлами копии из ~/Library/Application Support/TenFingers.backups/<дата_время>
/// и удалите там `TenFingers.store.generation`, если в копии его не было (копии, сделанные до введения маркера, его не содержат).
///
/// Версия 1.0.0 совпадает с той, что SwiftData записывал в базу и без `VersionedSchema`,
/// а хеши сущностей от версии не зависят, поэтому существующая база открывается как есть.
/// `AdaptiveUnlock` и `SessionRecord.source` (поколение 2), `AchievementRecord` (поколение 3), необязательные
/// `SessionRecord.fingerPresses`, `fingerErrors`, `yoPresses` (поколение 4), необязательная `DayRecord.goalSeconds`
/// (поколение 5), `AchievementGrant` и необязательные `SessionRecord.stepIndex`, `planSlot`, `textTraits`
/// (поколение 6), `RhythmResult` (поколение 7), необязательное `SessionRecord.speedSegments` (поколение 8), `ErrorWord` (поколение 9), `SpeedMeasurement` (поколение 10) добавлены внутри той же версии: изменение аддитивное, SwiftData переносит базу облегчённой
/// миграцией (проверено тестами на базах прежних схем: `LegacySchemaPhase2`, `LegacySchemaGeneration2`,
/// `LegacySchemaGeneration3`, `LegacySchemaGeneration4`, `LegacySchemaGeneration5`, `LegacySchemaGeneration6`, `LegacySchemaGeneration7`, `LegacySchemaGeneration8`).
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            SessionRecord.self, LessonProgress.self, KeyStat.self, BigramStat.self, DayRecord.self,
            CounterRecord.self, AdaptiveState.self, CustomText.self, AdaptiveUnlock.self, AchievementRecord.self,
            AchievementGrant.self, RhythmResult.self, ErrorWord.self, SpeedMeasurement.self,
        ]
    }
}

enum ModelStoreError: Error, Equatable {
    /// В базе есть модели, которых эта версия не знает: базу записала более новая версия приложения.
    case newerStore(unknown: [String])
    /// Рядом с базой лежит маркер более нового поколения схемы: базу записала версия с новыми полями моделей.
    case newerGeneration(stored: Int, current: Int)
    /// Маркер поколения есть, но не читается: базу не открываем, чтобы не «понизить» базу более новой версии.
    case unreadableGeneration
}

enum ModelStore {
    static let schema = Schema(versionedSchema: SchemaV1.self)

    /// Хранилище в ~/Library/Application Support/TenFingers/TenFingers.store.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema,
                                      configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        let url = defaultStoreURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try makeContainer(at: url)
    }

    /// ~/Library/Application Support/TenFingers/TenFingers.store
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "TenFingers", directoryHint: .isDirectory)
            .appending(path: "TenFingers.store")
    }

    /// Открывает базу по адресу. Базу более новой версии не открывает и не трогает (иначе SwiftData
    /// «смигрировал» бы её к старой схеме и потерял данные новых моделей или полей).
    /// После успешного открытия записывает маркер поколения `max(хранимое, текущее)`.
    static func makeContainer(at url: URL) throws -> ModelContainer {
        try checkCompatibility(storeAt: url)
        let stored: Int?
        do { stored = try SchemaGeneration.read(at: url) } catch { throw ModelStoreError.unreadableGeneration }
        guard SchemaGeneration.canOpen(stored: stored, current: SchemaGeneration.current) else {
            throw ModelStoreError.newerGeneration(stored: stored ?? 0, current: SchemaGeneration.current)
        }
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        try SchemaGeneration.write(max(stored ?? 0, SchemaGeneration.current), at: url)
        return container
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
