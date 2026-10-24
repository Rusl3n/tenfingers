import Foundation
import os
import SwiftData
import TypingCore
import UniformTypeIdentifiers

private let archiveLog = Logger(subsystem: "local.tenfingers", category: "archive")

/// Ошибки чтения и загрузки файла прогресса. Тексты — для алерта на экране «Данные»: без технических
/// подробностей декодера, разделы названы по-человечески.
enum ArchiveError: Error, Equatable, LocalizedError {
    /// Не JSON или не файл прогресса «Десяти пальцев».
    case notAnArchive
    /// Формат файла новее, чем умеет читать эта версия.
    case unsupported(Int)
    /// Файл сохранён версией приложения с более новой схемой данных.
    case newerGeneration(Int)
    /// Файл прогресса, но поле не читается (нет обязательного поля, неверный тип): путь до поля,
    /// например `sessions.0.language`.
    case damaged(String)
    /// Запись с пустым ключевым полем: модель и номер записи в своём разделе.
    case invalidRecord(String, Int)
    /// Уникальный ключ повторяется: модель и ключ.
    case duplicate(String, String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            String(localized: "Это не файл прогресса «Десяти пальцев».")
        case .unsupported(let version):
            String(localized: "Файл сохранён в формате версии \(version), а это приложение понимает только версию 1. Установите последнюю версию приложения.")
        case .newerGeneration:
            String(localized: "Файл сохранён более новой версией приложения. Установите последнюю версию.")
        case .damaged(let path):
            Self.describeDamage(at: path)
        case .invalidRecord(let model, let index):
            Self.describeRecord(section: Self.sectionTitle(model: model), number: index + 1)
        case .duplicate(let model, let key):
            Self.describeDuplicate(section: Self.sectionTitle(model: model), key: key)
        }
    }

    private static func describeRecord(section: String, number: Int) -> String {
        String(localized: "Файл прогресса повреждён: раздел «\(section)», запись № \(number).")
    }

    private static func describeDuplicate(section: String, key: String) -> String {
        String(localized: "Файл прогресса повреждён: в разделе «\(section)» запись «\(key)» повторяется.")
    }

    /// «раздел «Упражнения», запись № 1, поле «language»» для `sessions.0.language`; иначе — просто путь.
    private static func describeDamage(at path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        if parts.count >= 2, let model = ProgressArchive.modelName(section: parts[0]), let index = Int(parts[1]) {
            let section = sectionTitle(model: model)
            let field = parts.dropFirst(2).joined(separator: "."), number = index + 1
            return field.isEmpty
                ? describeRecord(section: section, number: number)
                : String(localized: "Файл прогресса повреждён: раздел «\(section)», запись № \(number), поле «\(field)».")
        }
        return String(localized: "Файл прогресса повреждён: поле «\(path)».")
    }

    /// Название раздела архива для человека по имени модели.
    static func sectionTitle(model: String) -> String {
        switch model {
        case "SessionRecord": String(localized: "Упражнения")
        case "DayRecord": String(localized: "Дни с занятиями")
        case "KeyStat": String(localized: "Статистика клавиш")
        case "BigramStat": String(localized: "Статистика сочетаний букв")
        case "LessonProgress": String(localized: "Прогресс уроков")
        case "AdaptiveState": String(localized: "Адаптивная тренировка")
        case "AdaptiveUnlock": String(localized: "Открытые буквы")
        case "CounterRecord": String(localized: "Счётчики")
        case "CustomText": String(localized: "Свои тексты")
        default: model
        }
    }
}

/// Файл всего прогресса (`.tenfingers`, JSON): все модели базы, настройки, профиль и продолжения уроков.
///
/// Формат версии 1: `format`, `version`, `exportedAt`, `appVersion`, `schemaGeneration`, `profile`, `settings`,
/// `lessonResume` и разделы моделей. Даты — числа: секунды от 1 января 2001 года UTC (как `Date` в Foundation),
/// без потери точности; при чтении принимаются и строки ISO 8601 (так писали первые сборки). Ключи упорядочены,
/// записи разделов отсортированы: один и тот же прогресс всегда даёт один и тот же файл.
/// Чтение терпимо к старым файлам: отсутствующие разделы и поля, у которых в модели есть значение
/// по умолчанию, получают это значение. Файл более нового формата или поколения схемы не читается.
enum ProgressArchive {
    static let format = "tenfingers-progress"
    static let version = 1
    static let fileExtension = "tenfingers"

    /// Тип файла: объявлен в `Info.plist` (`local.tenfingers.progress`, подтип `public.json`).
    static var fileType: UTType { UTType(filenameExtension: fileExtension, conformingTo: .json) ?? .json }

    // MARK: Архив

    struct Archive: Codable, Equatable {
        var format: String
        var version: Int
        var exportedAt: Date?
        var appVersion: String
        var schemaGeneration: Int
        var profile: ProfileDTO
        var settings: [String: SettingValue]
        /// Продолжения уроков (`LessonResume`) по `lessonId`.
        var lessonResume: [String: LessonResumeState]
        var sessions: [SessionDTO]
        var days: [DayDTO]
        var keyStats: [KeyStatDTO]
        var bigramStats: [BigramStatDTO]
        var lessonProgress: [LessonProgressDTO]
        var adaptiveStates: [AdaptiveStateDTO]
        var adaptiveUnlocks: [AdaptiveUnlockDTO]
        var counters: [CounterDTO]
        var customTexts: [CustomTextDTO]

        init(format: String = ProgressArchive.format, version: Int = ProgressArchive.version, exportedAt: Date?,
             appVersion: String, schemaGeneration: Int = SchemaGeneration.current, profile: ProfileDTO,
             settings: [String: SettingValue], lessonResume: [String: LessonResumeState],
             sessions: [SessionDTO], days: [DayDTO], keyStats: [KeyStatDTO], bigramStats: [BigramStatDTO],
             lessonProgress: [LessonProgressDTO], adaptiveStates: [AdaptiveStateDTO],
             adaptiveUnlocks: [AdaptiveUnlockDTO], counters: [CounterDTO], customTexts: [CustomTextDTO]) {
            self.format = format
            self.version = version
            self.exportedAt = exportedAt
            self.appVersion = appVersion
            self.schemaGeneration = schemaGeneration
            self.profile = profile
            self.settings = settings
            self.lessonResume = lessonResume
            self.sessions = sessions
            self.days = days
            self.keyStats = keyStats
            self.bigramStats = bigramStats
            self.lessonProgress = lessonProgress
            self.adaptiveStates = adaptiveStates
            self.adaptiveUnlocks = adaptiveUnlocks
            self.counters = counters
            self.customTexts = customTexts
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            format = try c.decode(String.self, forKey: .format)
            version = try c.decode(Int.self, forKey: .version)
            exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt)
            appVersion = try c.value(.appVersion, default: "")
            schemaGeneration = try c.value(.schemaGeneration, default: 0)
            profile = try c.value(.profile, default: ProfileDTO(nickname: "", fullName: ""))
            settings = ArchivedSettings.sanitize(try c.value(.settings, default: [:]))
            lessonResume = try c.value(.lessonResume, default: [:])
            sessions = try c.value(.sessions, default: [])
            days = try c.value(.days, default: [])
            keyStats = try c.value(.keyStats, default: [])
            bigramStats = try c.value(.bigramStats, default: [])
            lessonProgress = try c.value(.lessonProgress, default: [])
            adaptiveStates = try c.value(.adaptiveStates, default: [])
            adaptiveUnlocks = try c.value(.adaptiveUnlocks, default: [])
            counters = try c.value(.counters, default: [])
            customTexts = try c.value(.customTexts, default: [])
        }

        /// Количество записей в каждом разделе (для проверки записанной резервной копии).
        var recordCounts: [Int] {
            [sessions.count, days.count, keyStats.count, bigramStats.count, lessonProgress.count,
             adaptiveStates.count, adaptiveUnlocks.count, counters.count, customTexts.count, lessonResume.count]
        }
    }

    /// Раздел файла → модель (для сообщений об ошибках).
    static func modelName(section: String) -> String? {
        switch section {
        case "sessions": SessionDTO.modelName
        case "days": DayDTO.modelName
        case "keyStats": KeyStatDTO.modelName
        case "bigramStats": BigramStatDTO.modelName
        case "lessonProgress": LessonProgressDTO.modelName
        case "adaptiveStates": AdaptiveStateDTO.modelName
        case "adaptiveUnlocks": AdaptiveUnlockDTO.modelName
        case "counters": CounterDTO.modelName
        case "customTexts": CustomTextDTO.modelName
        default: nil
        }
    }

    /// Начало файла: по нему решаем, наш ли это файл и можно ли его читать, до разбора записей.
    private struct Header: Decodable {
        let format: String?
        let version: Int?
        let schemaGeneration: Int?
    }

    // MARK: Экспорт

    /// Записи каждого раздела отсортированы по устойчивому ключу: порядок не зависит от порядка выборки из базы.
    @MainActor static func makeArchive(context: ModelContext, defaults: UserDefaults = .standard,
                                       now: Date = .now) throws -> Archive {
        func all<T: PersistentModel>(_ type: T.Type) throws -> [T] { try context.fetch(FetchDescriptor<T>()) }
        return Archive(
            exportedAt: now,
            appVersion: AppVersion.display(info: AppVersion.current),
            profile: ProfileDTO(defaults: defaults),
            settings: ArchivedSettings.read(defaults),
            lessonResume: ArchivedSettings.readLessonResume(defaults),
            sessions: try all(SessionRecord.self).map(SessionDTO.init)
                .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) },
            days: try all(DayRecord.self).map(DayDTO.init).sorted { $0.logicalDay < $1.logicalDay },
            keyStats: try all(KeyStat.self).map(KeyStatDTO.init)
                .sorted { ($0.language, $0.character) < ($1.language, $1.character) },
            bigramStats: try all(BigramStat.self).map(BigramStatDTO.init)
                .sorted { ($0.language, $0.bigram) < ($1.language, $1.bigram) },
            lessonProgress: try all(LessonProgress.self).map(LessonProgressDTO.init)
                .sorted { $0.lessonId < $1.lessonId },
            adaptiveStates: try all(AdaptiveState.self).map(AdaptiveStateDTO.init).sorted { $0.language < $1.language },
            adaptiveUnlocks: try all(AdaptiveUnlock.self).map(AdaptiveUnlockDTO.init)
                .sorted { ($0.unlockedAt, $0.language, $0.letter) < ($1.unlockedAt, $1.language, $1.letter) },
            counters: try all(CounterRecord.self).map(CounterDTO.init).sorted { $0.name < $1.name },
            customTexts: try all(CustomText.self).map(CustomTextDTO.init)
                .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) })
    }

    /// Весь прогресс (с несохранёнными изменениями контекста) в JSON.
    @MainActor static func export(context: ModelContext, defaults: UserDefaults = .standard,
                                  now: Date = .now) throws -> Data {
        try encode(makeArchive(context: context, defaults: defaults, now: now))
    }

    static func encode(_ archive: Archive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Число, а не строка ISO 8601: строка хранит только миллисекунды, и дата «уплывала» бы
        // при каждом круге экспорт → загрузка.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        encoder.nonConformingFloatEncodingStrategy = nonConforming
        return try encoder.encode(archive)
    }

    // MARK: Чтение

    /// Читает и проверяет файл: формат, версию, поколение схемы, записи и уникальные ключи.
    static func decode(_ data: Data) throws -> Archive {
        let archive = try decodeStructure(data)
        try validate(archive)
        return archive
    }

    /// Только устройство файла: формат, версия, поколение схемы и типы полей, без проверки записей
    /// (`validate`). Так перечитывается записанная резервная копия.
    static func decodeStructure(_ data: Data) throws -> Archive {
        let decoder = makeDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            throw ArchiveError.notAnArchive
        }
        guard let fileVersion = header.version else { throw ArchiveError.damaged("version") }
        guard fileVersion <= version else { throw ArchiveError.unsupported(fileVersion) }
        let generation = header.schemaGeneration ?? 0
        guard generation <= SchemaGeneration.current else { throw ArchiveError.newerGeneration(generation) }
        do {
            return try decoder.decode(Archive.self, from: data)
        } catch let error as DecodingError {
            throw ArchiveError.damaged(fieldPath(error))
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) }
            let text = try container.decode(String.self)
            if let date = try? isoWithFraction.parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a date: \(text)")
        }
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }

    private static let isoWithFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let nonConforming = JSONEncoder.NonConformingFloatEncodingStrategy.convertToString(
        positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")

    /// Путь до поля с ошибкой («sessions.0.language»); причину (`debugDescription`, по-английски) не показываем.
    private static func fieldPath(_ error: DecodingError) -> String {
        let path: [any CodingKey] = switch error {
        case .keyNotFound(let key, let context): context.codingPath + [key]
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            context.codingPath
        @unknown default: []
        }
        let text = path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        if !text.isEmpty { archiveLog.error("Progress file: unreadable field \(text, privacy: .public): \(String(describing: error), privacy: .public)") }
        return text.isEmpty ? "?" : text
    }

    /// Проверка всех записей без изменения базы (та же, что идёт по ходу `replaceAll`).
    static func validate(_ archive: Archive) throws {
        var keys = UniqueKeys()
        try forEachRecord(of: archive, keys: &keys) { _ in }
    }

    // MARK: Сводка

    struct ArchiveSummary: Equatable {
        var exportedAt: Date?
        var appVersion: String
        /// Начало первой и конец последней сессии; `nil`, если сессий нет.
        var firstDate: Date?
        var lastDate: Date?
        var sessionCount: Int
        /// Дни с занятиями (`DayRecord`).
        var dayCount: Int
        var nickname: String
        var fullName: String
    }

    static func summary(_ archive: Archive) -> ArchiveSummary {
        ArchiveSummary(
            exportedAt: archive.exportedAt, appVersion: archive.appVersion,
            firstDate: archive.sessions.map(\.startedAt).min(), lastDate: archive.sessions.map(\.endedAt).max(),
            sessionCount: archive.sessions.count, dayCount: archive.days.count,
            nickname: archive.profile.nickname, fullName: archive.profile.fullName)
    }

    // MARK: Замена

    /// Заменяет всё содержимое базы данными архива одной транзакцией: удаляет все объекты всех моделей,
    /// вставляет записи архива и сохраняет один раз. Любая ошибка (битая или повторяющаяся запись,
    /// отказ сохранения) откатывает контекст: база остаётся как была.
    /// Удаление и вставка с теми же уникальными ключами в одном сохранении проверены тестами
    /// (в памяти и на диске). `beforeSave` — шов для тестов: бросает ошибку перед сохранением.
    /// Несохранённые изменения контекста сначала сохраняются отдельно: откат неудачной замены их не теряет.
    @MainActor static func replaceAll(with archive: Archive, context: ModelContext,
                                      beforeSave: (() throws -> Void)? = nil) throws {
        if context.hasChanges { try context.save() }
        do {
            try deleteAll(SessionRecord.self, in: context)
            try deleteAll(DayRecord.self, in: context)
            try deleteAll(KeyStat.self, in: context)
            try deleteAll(BigramStat.self, in: context)
            try deleteAll(LessonProgress.self, in: context)
            try deleteAll(AdaptiveState.self, in: context)
            try deleteAll(AdaptiveUnlock.self, in: context)
            try deleteAll(CounterRecord.self, in: context)
            try deleteAll(CustomText.self, in: context)
            var keys = UniqueKeys()
            try forEachRecord(of: archive, keys: &keys) { context.insert($0) }
            try beforeSave?()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        // Удаление по одному объекту, а не `delete(model:)`: пакетное удаление идёт мимо контекста
        // и не откатывается вместе с остальными изменениями.
        for object in try context.fetch(FetchDescriptor<T>()) { context.delete(object) }
    }

    /// Уже встреченные уникальные ключи (`#Unique` моделей): повтор в архиве SwiftData молча слил бы в одну запись.
    private struct UniqueKeys {
        private var seen: [String: Set<String>] = [:]

        mutating func insert(_ key: String, model: String) throws {
            guard seen[model, default: []].insert(key).inserted else { throw ArchiveError.duplicate(model, key) }
        }
    }

    /// Проверяет записи по порядку разделов и отдаёт модели; первая плохая запись прерывает обход.
    private static func forEachRecord(of archive: Archive, keys: inout UniqueKeys,
                                      _ body: (any PersistentModel) throws -> Void) throws {
        func each<D: ArchiveRecord>(_ records: [D], _ body: (any PersistentModel) throws -> Void) throws {
            for (index, record) in records.enumerated() {
                guard record.isValid else { throw ArchiveError.invalidRecord(D.modelName, index) }
                if let key = record.uniqueKey { try keys.insert(key, model: D.modelName) }
                try body(record.makeModel())
            }
        }
        try each(archive.sessions, body)
        try each(archive.days, body)
        try each(archive.keyStats, body)
        try each(archive.bigramStats, body)
        try each(archive.lessonProgress, body)
        try each(archive.adaptiveStates, body)
        try each(archive.adaptiveUnlocks, body)
        try each(archive.counters, body)
        try each(archive.customTexts, body)
    }

    /// Настройки, профиль и продолжения уроков из архива (после успешной замены базы).
    static func applyPreferences(of archive: Archive, to defaults: UserDefaults = .standard) {
        ArchivedSettings.apply(archive.settings, to: defaults)
        archive.profile.apply(to: defaults)
        ArchivedSettings.applyLessonResume(archive.lessonResume, to: defaults)
    }

    // MARK: Имена файлов

    /// «2026-10-24_21-05-03» по местному времени (как папки резервных копий `build-app.sh`).
    static func timestamp(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d_%02d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// Имя по умолчанию в окне сохранения: «TenFingers-progress-2026-10-24.tenfingers».
    static func defaultFileName(now: Date) -> String {
        "TenFingers-progress-\(timestamp(now).prefix(10)).\(fileExtension)"
    }

    /// Папка резервных копий (та же, куда `build-app.sh` кладёт копии базы).
    static var backupsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TenFingers.backups", directoryHint: .isDirectory)
    }
}

// MARK: - Загрузка с резервной копией

enum ProgressImportError: Error, LocalizedError {
    /// Резервную копию текущего прогресса записать не удалось: загрузка не начиналась.
    case backupFailed(String)
    /// Записанная резервная копия читается не полностью (другое число записей).
    case backupIncomplete

    var errorDescription: String? {
        switch self {
        case .backupFailed(let details):
            String(localized: "Не удалось сохранить резервную копию текущего прогресса, загрузка отменена: \(details)")
        case .backupIncomplete:
            String(localized: "резервная копия записалась не полностью.")
        }
    }
}

/// Загрузка прогресса из архива: резервная копия текущего → замена базы → настройки.
@MainActor
struct ProgressImporter {
    let context: ModelContext
    let defaults: UserDefaults
    let backupDirectory: URL
    /// Шов для тестов (см. `ProgressArchive.replaceAll`).
    var beforeSave: (() throws -> Void)?

    init(context: ModelContext, defaults: UserDefaults = .standard,
         backupDirectory: URL = ProgressArchive.backupsDirectory) {
        self.context = context
        self.defaults = defaults
        self.backupDirectory = backupDirectory
    }

    /// Возвращает адрес резервной копии прежнего прогресса. Если копию записать не удалось — бросает
    /// `ProgressImportError.backupFailed`, ничего не меняя. Если не удалась замена — база откатывается,
    /// настройки не трогаются, копия остаётся.
    func importArchive(_ archive: ProgressArchive.Archive, now: Date = .now) throws -> URL {
        let backup: URL
        do { backup = try writeBackup(now: now) } catch {
            throw ProgressImportError.backupFailed(error.localizedDescription)
        }
        try ProgressArchive.replaceAll(with: archive, context: context, beforeSave: beforeSave)
        ProgressArchive.applyPreferences(of: archive, to: defaults)
        return backup
    }

    /// `pre-import-<дата_время>.tenfingers` в папке копий; существующие файлы не перезаписываются.
    /// Копия перечитывается, прежде чем что-то менять: проверяется устройство файла и число записей
    /// в каждом разделе. Строгая проверка записей (`validate`) здесь не нужна: странная запись в текущей
    /// базе не должна запрещать любую загрузку, а в копию она попадает как есть.
    func writeBackup(now: Date) throws -> URL {
        let archive = try ProgressArchive.makeArchive(context: context, defaults: defaults, now: now)
        let data = try ProgressArchive.encode(archive)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stem = "pre-import-\(ProgressArchive.timestamp(now))"
        var url = backupDirectory.appending(path: "\(stem).\(ProgressArchive.fileExtension)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = backupDirectory.appending(path: "\(stem)-\(suffix).\(ProgressArchive.fileExtension)")
            suffix += 1
        }
        try data.write(to: url, options: .atomic)
        let written = try ProgressArchive.decodeStructure(Data(contentsOf: url))
        guard written.format == ProgressArchive.format, written.version == ProgressArchive.version,
              written.recordCounts == archive.recordCounts else { throw ProgressImportError.backupIncomplete }
        return url
    }
}

// MARK: - Записи архива

/// Запись раздела архива: проверка и превращение в модель.
private protocol ArchiveRecord {
    static var modelName: String { get }
    /// Ключевые поля не пустые.
    var isValid: Bool { get }
    /// Значение `#Unique` модели; `nil`, если ограничения нет.
    var uniqueKey: String? { get }
    func makeModel() -> any PersistentModel
}

extension ProgressArchive {
    struct ProfileDTO: Codable, Equatable {
        var nickname: String
        var fullName: String

        init(nickname: String, fullName: String) {
            self.nickname = nickname
            self.fullName = fullName
        }

        init(defaults: UserDefaults) {
            nickname = defaults.string(forKey: SettingsKey.profileNickname) ?? ""
            fullName = defaults.string(forKey: SettingsKey.profileFullName) ?? ""
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nickname = try c.value(.nickname, default: "")
            fullName = try c.value(.fullName, default: "")
        }

        /// Пустое значение — ключ удаляется (как у нового пользователя).
        func apply(to defaults: UserDefaults) {
            for (key, value) in [(SettingsKey.profileNickname, nickname), (SettingsKey.profileFullName, fullName)] {
                if value.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(value, forKey: key) }
            }
        }
    }

    struct SessionDTO: Codable, Equatable, ArchiveRecord {
        var id: UUID
        var mode: String
        var language: String
        var lessonId: String?
        var startedAt: Date
        var endedAt: Date
        var logicalDay: String
        var activeSeconds: Double
        var chars: Int
        var errorCount: Int
        var cpm: Double
        var accuracy: Double
        var completed: Bool
        var hintLevel: String
        var maxErrorStreak: Int
        var wrongKeystrokes: Int
        var exerciseKind: String?
        var pinkyPresses: Int
        var pinkyErrors: Int
        var source: String?

        init(_ m: SessionRecord) {
            id = m.id; mode = m.mode; language = m.language; lessonId = m.lessonId
            startedAt = m.startedAt; endedAt = m.endedAt; logicalDay = m.logicalDay
            activeSeconds = m.activeSeconds; chars = m.chars; errorCount = m.errorCount; cpm = m.cpm
            accuracy = m.accuracy; completed = m.completed; hintLevel = m.hintLevel
            maxErrorStreak = m.maxErrorStreak; wrongKeystrokes = m.wrongKeystrokes; exerciseKind = m.exerciseKind
            pinkyPresses = m.pinkyPresses; pinkyErrors = m.pinkyErrors; source = m.source
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.value(.id, default: UUID())
            mode = try c.decode(String.self, forKey: .mode)
            language = try c.decode(String.self, forKey: .language)
            lessonId = try c.decodeIfPresent(String.self, forKey: .lessonId)
            startedAt = try c.decode(Date.self, forKey: .startedAt)
            endedAt = try c.decode(Date.self, forKey: .endedAt)
            logicalDay = try c.decode(String.self, forKey: .logicalDay)
            activeSeconds = try c.decode(Double.self, forKey: .activeSeconds)
            chars = try c.decode(Int.self, forKey: .chars)
            errorCount = try c.decode(Int.self, forKey: .errorCount)
            cpm = try c.decode(Double.self, forKey: .cpm)
            accuracy = try c.decode(Double.self, forKey: .accuracy)
            completed = try c.decode(Bool.self, forKey: .completed)
            hintLevel = try c.decode(String.self, forKey: .hintLevel)
            maxErrorStreak = try c.value(.maxErrorStreak, default: 0)
            wrongKeystrokes = try c.value(.wrongKeystrokes, default: 0)
            exerciseKind = try c.decodeIfPresent(String.self, forKey: .exerciseKind)
            pinkyPresses = try c.value(.pinkyPresses, default: 0)
            pinkyErrors = try c.value(.pinkyErrors, default: 0)
            source = try c.decodeIfPresent(String.self, forKey: .source)
        }

        static let modelName = "SessionRecord"
        var isValid: Bool { !mode.isEmpty && !language.isEmpty && !logicalDay.isEmpty }
        var uniqueKey: String? { nil }

        func makeModel() -> any PersistentModel {
            let m = SessionRecord(
                mode: mode, language: language, lessonId: lessonId, startedAt: startedAt, endedAt: endedAt,
                logicalDay: logicalDay, activeSeconds: activeSeconds, chars: chars, errorCount: errorCount, cpm: cpm,
                accuracy: accuracy, completed: completed, hintLevel: hintLevel, maxErrorStreak: maxErrorStreak,
                wrongKeystrokes: wrongKeystrokes, exerciseKind: exerciseKind, pinkyPresses: pinkyPresses,
                pinkyErrors: pinkyErrors, source: source)
            m.id = id
            return m
        }
    }

    struct DayDTO: Codable, Equatable, ArchiveRecord {
        var logicalDay: String
        var activeSeconds: Double
        var completedExercises: Int
        var abandonedExercises: Int
        var languages: [String]

        init(_ m: DayRecord) {
            logicalDay = m.logicalDay; activeSeconds = m.activeSeconds; completedExercises = m.completedExercises
            abandonedExercises = m.abandonedExercises; languages = m.languages
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            logicalDay = try c.decode(String.self, forKey: .logicalDay)
            activeSeconds = try c.value(.activeSeconds, default: 0)
            completedExercises = try c.value(.completedExercises, default: 0)
            abandonedExercises = try c.value(.abandonedExercises, default: 0)
            languages = try c.value(.languages, default: [])
        }

        static let modelName = "DayRecord"
        var isValid: Bool { !logicalDay.isEmpty }
        var uniqueKey: String? { logicalDay }

        func makeModel() -> any PersistentModel {
            let m = DayRecord(logicalDay: logicalDay)
            m.activeSeconds = activeSeconds; m.completedExercises = completedExercises
            m.abandonedExercises = abandonedExercises; m.languages = languages
            return m
        }
    }

    struct KeyStatDTO: Codable, Equatable, ArchiveRecord {
        var language: String
        var character: String
        var keyCode: Int
        var presses: Int
        var errors: Int
        var ewmaMs: Double?
        var recent: [Bool]

        init(_ m: KeyStat) {
            language = m.language; character = m.character; keyCode = m.keyCode; presses = m.presses
            errors = m.errors; ewmaMs = m.ewmaMs; recent = m.recent
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            language = try c.decode(String.self, forKey: .language)
            character = try c.decode(String.self, forKey: .character)
            keyCode = try c.value(.keyCode, default: 0)
            presses = try c.value(.presses, default: 0)
            errors = try c.value(.errors, default: 0)
            ewmaMs = try c.decodeIfPresent(Double.self, forKey: .ewmaMs)
            recent = try c.value(.recent, default: [])
        }

        static let modelName = "KeyStat"
        var isValid: Bool { !language.isEmpty && !character.isEmpty }
        var uniqueKey: String? { "\(language)/\(character)" }

        func makeModel() -> any PersistentModel {
            let m = KeyStat(language: language, character: character)
            m.keyCode = keyCode; m.presses = presses; m.errors = errors; m.ewmaMs = ewmaMs; m.recent = recent
            return m
        }
    }

    struct BigramStatDTO: Codable, Equatable, ArchiveRecord {
        var language: String
        var bigram: String
        var count: Int
        var errors: Int
        var ewmaMs: Double?
        var recent: [Bool]

        init(_ m: BigramStat) {
            language = m.language; bigram = m.bigram; count = m.count; errors = m.errors
            ewmaMs = m.ewmaMs; recent = m.recent
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            language = try c.decode(String.self, forKey: .language)
            bigram = try c.decode(String.self, forKey: .bigram)
            count = try c.value(.count, default: 0)
            errors = try c.value(.errors, default: 0)
            ewmaMs = try c.decodeIfPresent(Double.self, forKey: .ewmaMs)
            recent = try c.value(.recent, default: [])
        }

        static let modelName = "BigramStat"
        var isValid: Bool { !language.isEmpty && !bigram.isEmpty }
        var uniqueKey: String? { "\(language)/\(bigram)" }

        func makeModel() -> any PersistentModel {
            let m = BigramStat(language: language, bigram: bigram)
            m.count = count; m.errors = errors; m.ewmaMs = ewmaMs; m.recent = recent
            return m
        }
    }

    struct LessonProgressDTO: Codable, Equatable, ArchiveRecord {
        var lessonId: String
        var language: String
        var attempts: Int
        var bestStars: Int
        var bestCpm: Double
        var bestAccuracy: Double
        var passedAt: Date?

        init(_ m: LessonProgress) {
            lessonId = m.lessonId; language = m.language; attempts = m.attempts; bestStars = m.bestStars
            bestCpm = m.bestCpm; bestAccuracy = m.bestAccuracy; passedAt = m.passedAt
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lessonId = try c.decode(String.self, forKey: .lessonId)
            language = try c.decode(String.self, forKey: .language)
            attempts = try c.value(.attempts, default: 0)
            bestStars = try c.value(.bestStars, default: 0)
            bestCpm = try c.value(.bestCpm, default: 0)
            bestAccuracy = try c.value(.bestAccuracy, default: 0)
            passedAt = try c.decodeIfPresent(Date.self, forKey: .passedAt)
        }

        static let modelName = "LessonProgress"
        var isValid: Bool { !lessonId.isEmpty && !language.isEmpty }
        var uniqueKey: String? { lessonId }

        func makeModel() -> any PersistentModel {
            let m = LessonProgress(lessonId: lessonId, language: language)
            m.attempts = attempts; m.bestStars = bestStars; m.bestCpm = bestCpm; m.bestAccuracy = bestAccuracy
            m.passedAt = passedAt
            return m
        }
    }

    struct AdaptiveStateDTO: Codable, Equatable, ArchiveRecord {
        var language: String
        var unlockedCount: Int

        init(_ m: AdaptiveState) {
            language = m.language; unlockedCount = m.unlockedCount
        }

        static let modelName = "AdaptiveState"
        var isValid: Bool { !language.isEmpty }
        var uniqueKey: String? { language }
        func makeModel() -> any PersistentModel { AdaptiveState(language: language, unlockedCount: unlockedCount) }
    }

    struct AdaptiveUnlockDTO: Codable, Equatable, ArchiveRecord {
        var language: String
        var letter: String
        var unlockedAt: Date

        init(_ m: AdaptiveUnlock) {
            language = m.language; letter = m.letter; unlockedAt = m.unlockedAt
        }

        static let modelName = "AdaptiveUnlock"
        var isValid: Bool { !language.isEmpty && !letter.isEmpty }
        var uniqueKey: String? { nil }
        func makeModel() -> any PersistentModel { AdaptiveUnlock(language: language, letter: letter, unlockedAt: unlockedAt) }
    }

    struct CounterDTO: Codable, Equatable, ArchiveRecord {
        var name: String
        var value: Int

        init(_ m: CounterRecord) {
            name = m.name; value = m.value
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            value = try c.value(.value, default: 0)
        }

        static let modelName = "CounterRecord"
        var isValid: Bool { !name.isEmpty }
        var uniqueKey: String? { name }

        func makeModel() -> any PersistentModel {
            let m = CounterRecord(name: name)
            m.value = value
            return m
        }
    }

    struct CustomTextDTO: Codable, Equatable, ArchiveRecord {
        var id: UUID
        var title: String
        var body: String
        var language: String
        var offset: Int
        var createdAt: Date

        init(_ m: CustomText) {
            id = m.id; title = m.title; body = m.body; language = m.language; offset = m.offset; createdAt = m.createdAt
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.value(.id, default: UUID())
            title = try c.value(.title, default: "")
            body = try c.decode(String.self, forKey: .body)
            language = try c.decode(String.self, forKey: .language)
            offset = try c.value(.offset, default: 0)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
        }

        static let modelName = "CustomText"
        var isValid: Bool { !language.isEmpty }
        var uniqueKey: String? { nil }

        func makeModel() -> any PersistentModel {
            let m = CustomText(title: title, body: body, language: language, createdAt: createdAt)
            m.id = id
            m.offset = min(max(offset, 0), body.count)
            return m
        }
    }
}

// MARK: - Настройки

/// Значение настройки в архиве: JSON-скаляр. Тип при загрузке определяется ключом (`ArchivedSettings`).
enum SettingValue: Codable, Equatable {
    case bool(Bool), int(Int), double(Double), string(String)

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Int.self) { self = .int(value) }
        else if let value = try? c.decode(Double.self) { self = .double(value) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try c.encode(value)
        case .int(let value): try c.encode(value)
        case .double(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        }
    }
}

/// Настройка при чтении файла: значение, которое не читается как `SettingValue`, становится `nil`,
/// а не ошибкой всего файла.
struct LenientSetting: Decodable {
    let value: SettingValue?

    init(from decoder: any Decoder) throws {
        value = try? SettingValue(from: decoder)
    }
}

/// Какие настройки попадают в архив. Только известные ключи; профиль — отдельным разделом `profile`.
/// Не попадают: открытый раздел настроек (состояние окна) и прежний ключ темы.
enum ArchivedSettings {
    enum Kind { case bool, int, double, string }

    static var entries: [(key: String, kind: Kind)] {
        [
            (SettingsKey.themeMode, .string), (SettingsKey.lightPalette, .string), (SettingsKey.darkPalette, .string),
            (SettingsKey.darkFromHour, .int), (SettingsKey.darkToHour, .int), (SettingsKey.uiScale, .double),
            (SettingsKey.activeLanguage, .string), (SettingsKey.hintMode, .string), (SettingsKey.speedUnit, .string),
            (SettingsKey.dayStartHour, .int), (SettingsKey.dailyGoalMinutes, .int),
            (SettingsKey.adaptiveTargetCpm, .int), (SettingsKey.spaceThumbHint, .bool),
            (SettingsKey.quitOnWindowClose, .bool),
            (SettingsKey.keyboardUnit, .double), (SettingsKey.keyboardOffset, .double),
            (SettingsKey.remindersEnabled, .bool), (SettingsKey.reminderHour, .int), (SettingsKey.reminderMinute, .int),
        ] + SoundEvent.allCases.flatMap { event -> [(key: String, kind: Kind)] in
            [(SoundSettings.enabledKey(event), .bool), (SoundSettings.volumeKey(event), .double)]
        }
    }

    /// Из файла остаются только известные ключи; незнакомые (например, из более новой версии) пропускаются
    /// и записываются в журнал. Значения, которые не читаются как скаляр (массив, объект, `null`),
    /// отбрасываются ещё при разборе (`LenientSetting`): файл из-за них не отвергается.
    static func sanitize(_ values: [String: LenientSetting]) -> [String: SettingValue] {
        let known = Set(entries.map(\.key))
        var result: [String: SettingValue] = [:]
        for (key, entry) in values {
            guard known.contains(key) else {
                archiveLog.notice("Progress file: unknown setting \(key, privacy: .public) skipped")
                continue
            }
            guard let value = entry.value else {
                archiveLog.notice("Progress file: setting \(key, privacy: .public) is not a scalar, skipped")
                continue
            }
            result[key] = value
        }
        return result
    }

    /// Только заданные пользователем значения (не заданные — значения по умолчанию, их не пишем).
    static func read(_ defaults: UserDefaults) -> [String: SettingValue] {
        var result: [String: SettingValue] = [:]
        for (key, kind) in entries {
            guard let object = defaults.object(forKey: key) else { continue }
            let value: SettingValue? = switch kind {
            case .bool: (object as? Bool).map(SettingValue.bool)
            case .int: (object as? Int).map(SettingValue.int)
            case .double: (object as? Double).map(SettingValue.double)
            case .string: (object as? String).map(SettingValue.string)
            }
            if let value { result[key] = value }
        }
        return result
    }

    /// Ключа нет в архиве — настройка возвращается к значению по умолчанию; значение не того типа пропускается.
    static func apply(_ values: [String: SettingValue], to defaults: UserDefaults) {
        for (key, kind) in entries {
            guard let value = values[key] else {
                defaults.removeObject(forKey: key)
                continue
            }
            switch (kind, value) {
            case (.bool, .bool(let v)): defaults.set(v, forKey: key)
            case (.int, .int(let v)): defaults.set(v, forKey: key)
            case (.double, .double(let v)): defaults.set(v, forKey: key)
            case (.double, .int(let v)): defaults.set(Double(v), forKey: key)
            case (.string, .string(let v)): defaults.set(v, forKey: key)
            default: archiveLog.notice("Progress file: setting \(key, privacy: .public) has another type, current value kept")
            }
        }
    }

    private static let resumePrefix = LessonResume.key(lessonId: "")

    static func readLessonResume(_ defaults: UserDefaults) -> [String: LessonResumeState] {
        let resume = LessonResume(defaults: defaults)
        var result: [String: LessonResumeState] = [:]
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(resumePrefix) {
            let lessonId = String(key.dropFirst(resumePrefix.count))
            if let state = resume.load(lessonId: lessonId) { result[lessonId] = state }
        }
        return result
    }

    /// Продолжения уроков заменяются целиком.
    static func applyLessonResume(_ states: [String: LessonResumeState], to defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(resumePrefix) {
            defaults.removeObject(forKey: key)
        }
        for (lessonId, state) in states where !lessonId.isEmpty {
            if let data = try? JSONEncoder().encode(state) {
                defaults.set(data, forKey: LessonResume.key(lessonId: lessonId))
            }
        }
    }
}

private extension KeyedDecodingContainer {
    /// Значение поля или `fallback`, если поля нет (файл старой версии).
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}
