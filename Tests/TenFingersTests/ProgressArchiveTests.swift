import Foundation
import SwiftData
import Testing
import TypingCore
import UniformTypeIdentifiers
@testable import TenFingers

// MARK: - Помощники

private let base = Date(timeIntervalSince1970: 1_790_000_000.25)

/// Отдельный домен настроек на тест; удаляется в `defer` через `removeTestDefaults`.
private func makeDefaults() -> (UserDefaults, String) {
    makeTestDefaults("ProgressArchiveTests-")
}

private func temporaryDirectory(_ prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Заполняет все модели (по одной-две записи), так чтобы были и необязательные, и заданные по умолчанию поля.
@MainActor private func populate(_ context: ModelContext, tag: String = "a") throws {
    context.insert(SessionRecord(
        mode: "course", language: "ru", lessonId: "ru.1.1", startedAt: base, endedAt: base.addingTimeInterval(61.5),
        logicalDay: "2026-09-21", activeSeconds: 60.75, chars: 120, errorCount: 3, cpm: 118.123456789,
        accuracy: 0.975, completed: true, hintLevel: "full", maxErrorStreak: 2, wrongKeystrokes: 4,
        exerciseKind: "check", pinkyPresses: 9, pinkyErrors: 1, source: nil))
    context.insert(SessionRecord(
        mode: "practice", language: "en", lessonId: nil, startedAt: base.addingTimeInterval(86_400),
        endedAt: base.addingTimeInterval(86_400 + 300), logicalDay: "2026-09-22", activeSeconds: 290,
        chars: 900, errorCount: 10, cpm: 186.2, accuracy: 0.989, completed: false, hintLevel: "hidden",
        maxErrorStreak: 1, wrongKeystrokes: 10, exerciseKind: nil, pinkyPresses: 0, pinkyErrors: 0,
        source: "library:\(tag)"))

    let lesson = LessonProgress(lessonId: "ru.1.1", language: "ru")
    lesson.attempts = 3
    lesson.bestStars = 2
    lesson.bestCpm = 140.5
    lesson.bestAccuracy = 0.99
    lesson.passedAt = base.addingTimeInterval(62)
    context.insert(lesson)
    context.insert(LessonProgress(lessonId: "ru.1.2", language: "ru"))

    let key = KeyStat(language: "ru", character: "о")
    key.keyCode = 38
    key.presses = 50
    key.errors = 2
    key.ewmaMs = 212.25
    key.recent = [false, true, false]
    context.insert(key)
    context.insert(KeyStat(language: "en", character: "q"))

    let bigram = BigramStat(language: "ru", bigram: "ов")
    bigram.count = 7
    bigram.errors = 1
    bigram.ewmaMs = 301
    bigram.recent = [true, false]
    context.insert(bigram)

    let day = DayRecord(logicalDay: "2026-09-21")
    day.activeSeconds = 60.75
    day.completedExercises = 1
    day.abandonedExercises = 0
    day.languages = ["ru"]
    context.insert(day)
    let day2 = DayRecord(logicalDay: "2026-09-22")
    day2.activeSeconds = 290
    day2.abandonedExercises = 1
    day2.languages = ["en", "ru"]
    context.insert(day2)

    let counter = CounterRecord(name: CounterName.capsLockPresses)
    counter.value = 5
    context.insert(counter)
    context.insert(AdaptiveState(language: "ru", unlockedCount: 9))
    context.insert(AdaptiveUnlock(language: "ru", letter: "к", unlockedAt: base.addingTimeInterval(100)))
    let text = CustomText(title: "Заметка \(tag)", body: "Привет, мир", language: "ru", createdAt: base)
    text.offset = 7
    context.insert(text)
    context.insert(AchievementRecord(achievementId: "course.first_lesson", unlockedAt: base.addingTimeInterval(62),
                                     seen: true))
    try context.save()
}

@MainActor private func count<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> Int {
    try context.fetchCount(FetchDescriptor<T>())
}

/// Количества всех моделей по порядку `SchemaV1.models` (для сравнения «до/после»).
@MainActor private func counts(_ context: ModelContext) throws -> [Int] {
    [try count(SessionRecord.self, context), try count(LessonProgress.self, context), try count(KeyStat.self, context),
     try count(BigramStat.self, context), try count(DayRecord.self, context), try count(CounterRecord.self, context),
     try count(AdaptiveState.self, context), try count(CustomText.self, context), try count(AdaptiveUnlock.self, context),
     try count(AchievementRecord.self, context)]
}

private func archiveJSON(_ fields: String) -> Data {
    Data("{ \(fields) }".utf8)
}

// MARK: - Экспорт и импорт туда-обратно

@MainActor @Test func exportThenImportRestoresEveryModel() throws {
    let sourceContainer = try ModelStore.makeContainer(inMemory: true)
    let source = sourceContainer.mainContext
    let (sourceDefaults, sourceName) = makeDefaults()
    defer { removeTestDefaults(sourceName) }
    try populate(source)
    let originalSessionIds = Set(try source.fetch(FetchDescriptor<SessionRecord>()).map(\.id))
    let originalTextId = try #require(try source.fetch(FetchDescriptor<CustomText>()).first?.id)

    let data = try ProgressArchive.export(context: source, defaults: sourceDefaults, now: base)
    let archive = try ProgressArchive.decode(data)
    #expect(archive.format == "tenfingers-progress")
    #expect(archive.version == 1)
    #expect(archive.schemaGeneration == SchemaGeneration.current)

    let targetContainer = try ModelStore.makeContainer(inMemory: true)
    let target = targetContainer.mainContext
    try ProgressArchive.replaceAll(with: archive, context: target)
    #expect(try counts(target) == counts(source))
    #expect(try counts(target) == [2, 2, 2, 1, 2, 1, 1, 1, 1, 1])

    let sessions = try target.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt)]))
    #expect(Set(sessions.map(\.id)) == originalSessionIds)
    let course = sessions[0], practice = sessions[1]
    #expect(abs(course.startedAt.timeIntervalSince(base)) < 0.001)
    #expect(abs(course.endedAt.timeIntervalSince(base.addingTimeInterval(61.5))) < 0.001)
    #expect(course.cpm == 118.123456789)
    #expect(course.accuracy == 0.975)
    #expect(course.lessonId == "ru.1.1")
    #expect(course.exerciseKind == "check")
    #expect(course.source == nil)
    #expect(course.pinkyPresses == 9 && course.pinkyErrors == 1)
    #expect(course.maxErrorStreak == 2 && course.wrongKeystrokes == 4 && course.errorCount == 3)
    #expect(course.completed && course.hintLevel == "full" && course.logicalDay == "2026-09-21")
    #expect(practice.source == "library:a")
    #expect(practice.lessonId == nil && practice.exerciseKind == nil && !practice.completed)

    let lesson = try #require(try target.fetch(FetchDescriptor<LessonProgress>(
        predicate: #Predicate { $0.lessonId == "ru.1.1" })).first)
    #expect(lesson.attempts == 3 && lesson.bestStars == 2 && lesson.bestCpm == 140.5 && lesson.bestAccuracy == 0.99)
    #expect(abs((lesson.passedAt ?? .distantPast).timeIntervalSince(base.addingTimeInterval(62))) < 0.001)
    let fresh = try #require(try target.fetch(FetchDescriptor<LessonProgress>(
        predicate: #Predicate { $0.lessonId == "ru.1.2" })).first)
    #expect(fresh.passedAt == nil && fresh.attempts == 0)

    let key = try #require(try target.fetch(FetchDescriptor<KeyStat>(predicate: #Predicate { $0.character == "о" })).first)
    #expect(key.language == "ru" && key.keyCode == 38 && key.presses == 50 && key.errors == 2)
    #expect(key.ewmaMs == 212.25)
    #expect(key.recent == [false, true, false])
    let q = try #require(try target.fetch(FetchDescriptor<KeyStat>(predicate: #Predicate { $0.character == "q" })).first)
    #expect(q.ewmaMs == nil && q.recent.isEmpty)

    let bigram = try #require(try target.fetch(FetchDescriptor<BigramStat>()).first)
    #expect(bigram.bigram == "ов" && bigram.count == 7 && bigram.errors == 1 && bigram.ewmaMs == 301)
    #expect(bigram.recent == [true, false])

    let days = try target.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.logicalDay)]))
    #expect(days.map(\.logicalDay) == ["2026-09-21", "2026-09-22"])
    #expect(days[1].languages == ["en", "ru"] && days[1].abandonedExercises == 1 && days[1].activeSeconds == 290)
    #expect(days[0].completedExercises == 1 && days[0].activeSeconds == 60.75)

    #expect(try target.fetch(FetchDescriptor<CounterRecord>()).first?.value == 5)
    #expect(try target.fetch(FetchDescriptor<AdaptiveState>()).first?.unlockedCount == 9)
    let unlock = try #require(try target.fetch(FetchDescriptor<AdaptiveUnlock>()).first)
    #expect(unlock.letter == "к" && unlock.language == "ru")
    #expect(abs(unlock.unlockedAt.timeIntervalSince(base.addingTimeInterval(100))) < 0.001)

    let text = try #require(try target.fetch(FetchDescriptor<CustomText>()).first)
    #expect(text.id == originalTextId)
    #expect(text.title == "Заметка a" && text.body == "Привет, мир" && text.language == "ru")
    #expect(text.offset == 7)
    #expect(abs(text.createdAt.timeIntervalSince(base)) < 0.001)

    let achievement = try #require(try target.fetch(FetchDescriptor<AchievementRecord>()).first)
    #expect(achievement.achievementId == "course.first_lesson" && achievement.seen)
    #expect(abs(achievement.unlockedAt.timeIntervalSince(base.addingTimeInterval(62))) < 0.001)
}

/// Набор моделей и полей архива совпадает со схемой: новая модель или поле без поддержки в архиве ломает тест.
@MainActor @Test func archiveCoversEverySchemaEntityAndField() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populate(context)
    // Необязательные поля, которые в `populate` где-то пустые, заполняем, чтобы они попали в JSON.
    for session in try context.fetch(FetchDescriptor<SessionRecord>()) {
        session.source = session.source ?? "words"
        session.lessonId = session.lessonId ?? "x"
        session.exerciseKind = session.exerciseKind ?? "check"
        session.fingerPresses = session.fingerPresses ?? FingerCounts.data([.leftPinky: 5, .thumb: 7])
        session.fingerErrors = session.fingerErrors ?? FingerCounts.data([.leftPinky: 1, .thumb: 0])
        session.yoPresses = session.yoPresses ?? 2
    }
    for stat in try context.fetch(FetchDescriptor<KeyStat>()) { stat.ewmaMs = stat.ewmaMs ?? 1 }
    for lesson in try context.fetch(FetchDescriptor<LessonProgress>()) { lesson.passedAt = lesson.passedAt ?? base }
    for day in try context.fetch(FetchDescriptor<DayRecord>()) { day.goalSeconds = day.goalSeconds ?? 600 }
    try context.save()
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }

    let data = try ProgressArchive.export(context: context, defaults: defaults, now: base)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let sections: [String: String] = [
        "SessionRecord": "sessions", "LessonProgress": "lessonProgress", "KeyStat": "keyStats",
        "BigramStat": "bigramStats", "DayRecord": "days", "CounterRecord": "counters",
        "AdaptiveState": "adaptiveStates", "AdaptiveUnlock": "adaptiveUnlocks", "CustomText": "customTexts",
        "AchievementRecord": "achievements",
    ]
    #expect(Set(ModelStore.schema.entities.map(\.name)) == Set(sections.keys))
    for entity in ModelStore.schema.entities {
        let section = try #require(sections[entity.name], "модель \(entity.name) не попадает в архив")
        let records = try #require(json[section] as? [[String: Any]])
        let first = try #require(records.first, "в архиве нет записей \(section)")
        let fields = Set(records.flatMap(\.keys))
        #expect(fields == Set(entity.properties.map(\.name)), "\(entity.name): \(fields) ≠ схема")
        #expect(!first.isEmpty)
    }
}

// MARK: - Формат и версии

@Test func newerFormatVersionIsUnsupported() throws {
    let data = archiveJSON(#""format": "tenfingers-progress", "version": 2, "schemaGeneration": 2"#)
    #expect(throws: ArchiveError.unsupported(2)) { _ = try ProgressArchive.decode(data) }
    #expect(ArchiveError.unsupported(2).errorDescription?.isEmpty == false)
}

@Test func archiveFromNewerSchemaGenerationIsRefused() throws {
    let next = SchemaGeneration.current + 1
    let data = archiveJSON(#""format": "tenfingers-progress", "version": 1, "schemaGeneration": \#(next)"#)
    #expect(throws: ArchiveError.newerGeneration(next)) { _ = try ProgressArchive.decode(data) }
    #expect(ArchiveError.newerGeneration(next).errorDescription?.isEmpty == false)
}

@Test func foreignOrDamagedFilesAreRejected() throws {
    #expect(throws: ArchiveError.notAnArchive) {
        _ = try ProgressArchive.decode(archiveJSON(#""format": "something-else", "version": 1"#))
    }
    #expect(throws: ArchiveError.notAnArchive) { _ = try ProgressArchive.decode(Data("не json".utf8)) }
    #expect(throws: ArchiveError.notAnArchive) { _ = try ProgressArchive.decode(Data("[1, 2]".utf8)) }
    // Формат верный, но запись сессии без обязательного поля.
    let damaged = archiveJSON(#""format": "tenfingers-progress", "version": 1, "schemaGeneration": 2, "sessions": [{"mode": "course"}]"#)
    #expect {
        _ = try ProgressArchive.decode(damaged)
    } throws: { error in
        if case .damaged = error as? ArchiveError { return true }
        return false
    }
}

/// Архив более старого поколения: нет новых полей и разделов — подставляются значения по умолчанию.
@MainActor @Test func olderArchiveWithMissingFieldsImportsWithDefaults() throws {
    let data = archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 1,
        "sessions": [{
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "mode": "course", "language": "ru", "lessonId": "ru.1.1",
            "startedAt": "2026-09-21T10:00:00Z", "endedAt": "2026-09-21T10:01:00.5Z", "logicalDay": "2026-09-21",
            "activeSeconds": 60, "chars": 100, "errorCount": 1, "cpm": 100, "accuracy": 0.99, "completed": true,
            "hintLevel": "full", "maxErrorStreak": 1, "wrongKeystrokes": 1
        }],
        "keyStats": [{ "language": "ru", "character": "а" }],
        "customTexts": [{ "title": "Т", "body": "Текст", "language": "ru", "createdAt": "2026-09-21T10:00:00Z" }]
        """#)
    let archive = try ProgressArchive.decode(data)
    #expect(archive.adaptiveUnlocks.isEmpty && archive.days.isEmpty && archive.settings.isEmpty)
    #expect(archive.profile == ProgressArchive.ProfileDTO(nickname: "", fullName: ""))
    #expect(archive.exportedAt == nil)

    let contextContainer = try ModelStore.makeContainer(inMemory: true)
    let context = contextContainer.mainContext
    try ProgressArchive.replaceAll(with: archive, context: context)
    let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.id == UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
    #expect(session.source == nil && session.exerciseKind == nil && session.pinkyPresses == 0)
    #expect(session.fingerPresses == nil && session.fingerErrors == nil && session.yoPresses == nil)
    #expect(abs(session.endedAt.timeIntervalSince(session.startedAt) - 60.5) < 0.001)
    let key = try #require(try context.fetch(FetchDescriptor<KeyStat>()).first)
    #expect(key.presses == 0 && key.recent.isEmpty && key.ewmaMs == nil && key.keyCode == 0)
    let text = try #require(try context.fetch(FetchDescriptor<CustomText>()).first)
    #expect(text.offset == 0)
}

// MARK: - Замена прогресса

/// Число объектов сущности по имени из `ModelStore.schema` (тип берётся из `SchemaV1.models`).
@MainActor private func objectCount(entity name: String, _ context: ModelContext) throws -> Int? {
    guard let type = SchemaV1.models.first(where: { String(describing: $0) == name }) else { return nil }
    return try count(type, context)
}

/// Защитный тест: каждая сущность схемы должна поддерживаться архивом и заменой. Новая модель без поддержки
/// в архиве (нет раздела, не удаляется при замене) или без заполнения в `populate` роняет этот тест.
@MainActor @Test func replaceAllHandlesEverySchemaEntity() throws {
    let entities = ModelStore.schema.entities.map(\.name)
    #expect(Set(entities) == Set(SchemaV1.models.map { String(describing: $0) }))

    let sourceContainer = try ModelStore.makeContainer(inMemory: true)
    let source = sourceContainer.mainContext
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    try populate(source, tag: "new")
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: source, defaults: defaults, now: base))
    let archived = archive.recordCountsByModel

    // В базе до замены есть объекты каждой сущности, и они не совпадают с архивом ни числом, ни ключами.
    let targetContainer = try ModelStore.makeContainer(inMemory: true)
    let target = targetContainer.mainContext
    try populate(target, tag: "old")
    target.insert(SessionRecord(mode: "words", language: "ru", lessonId: nil, startedAt: base, endedAt: base,
                                logicalDay: "2026-01-01", activeSeconds: 1, chars: 1, errorCount: 0, cpm: 1,
                                accuracy: 1, completed: true, hintLevel: "full", maxErrorStreak: 0,
                                wrongKeystrokes: 0))
    try target.save()

    for entity in entities {
        #expect(try (objectCount(entity: entity, source) ?? 0) > 0, "populate не заполняет \(entity)")
        #expect(try (objectCount(entity: entity, target) ?? 0) > 0, "populate не заполняет \(entity)")
        #expect(archived[entity] != nil, "в архиве нет раздела для \(entity)")
    }
    try ProgressArchive.replaceAll(with: archive, context: target)
    for entity in entities {
        #expect(try objectCount(entity: entity, target) == archived[entity], "после замены число \(entity) не как в архиве")
    }
    #expect(Set(archived.keys) == Set(entities))
}

@MainActor @Test func replaceAllOverExistingDataReplacesEverything() throws {
    let sourceContainer = try ModelStore.makeContainer(inMemory: true)
    let source = sourceContainer.mainContext
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    try populate(source, tag: "new")
    // В архиве меняем значения при тех же уникальных ключах (урок, день, клавиша, счётчик, язык).
    for lesson in try source.fetch(FetchDescriptor<LessonProgress>()) { lesson.attempts = 42 }
    try source.save()
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: source, defaults: defaults, now: base))

    let targetContainer = try ModelStore.makeContainer(inMemory: true)
    let target = targetContainer.mainContext
    try populate(target, tag: "old")
    target.insert(SessionRecord(mode: "words", language: "ru", lessonId: nil, startedAt: base, endedAt: base,
                                logicalDay: "2026-01-01", activeSeconds: 1, chars: 1, errorCount: 0, cpm: 1,
                                accuracy: 1, completed: true, hintLevel: "full", maxErrorStreak: 0,
                                wrongKeystrokes: 0))
    target.insert(DayRecord(logicalDay: "2026-01-01"))
    target.insert(CounterRecord(name: CounterName.wrongLayoutStarts))
    target.insert(AdaptiveState(language: "en", unlockedCount: 12))
    try target.save()

    try ProgressArchive.replaceAll(with: archive, context: target)
    #expect(!target.hasChanges)
    #expect(try counts(target) == [2, 2, 2, 1, 2, 1, 1, 1, 1, 1])
    let sources = Set(try target.fetch(FetchDescriptor<SessionRecord>()).compactMap(\.source))
    #expect(sources == ["library:new"])
    #expect(try target.fetch(FetchDescriptor<LessonProgress>()).allSatisfy { $0.attempts == 42 })
    #expect(try target.fetch(FetchDescriptor<CustomText>()).map(\.title) == ["Заметка new"])
    #expect(try target.fetch(FetchDescriptor<DayRecord>()).map(\.logicalDay).sorted() == ["2026-09-21", "2026-09-22"])
    #expect(try target.fetch(FetchDescriptor<CounterRecord>()).map(\.name) == [CounterName.capsLockPresses])
    #expect(try target.fetch(FetchDescriptor<AdaptiveState>()).map(\.language) == ["ru"])
}

/// Битая запись посреди импорта: всё откатывается, исходные данные целы.
@MainActor @Test func brokenRecordMidImportLeavesOriginalDataIntact() throws {
    let sourceContainer = try ModelStore.makeContainer(inMemory: true)
    let source = sourceContainer.mainContext
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    try populate(source, tag: "new")
    var archive = try ProgressArchive.decode(ProgressArchive.export(context: source, defaults: defaults, now: base))
    // Битая запись — в середине: перед ней уже удалены старые данные и вставлены новые сессии.
    var broken = archive.days[0]
    broken.logicalDay = ""
    archive.days.insert(broken, at: 1)

    let targetContainer = try ModelStore.makeContainer(inMemory: true)
    let target = targetContainer.mainContext
    try populate(target, tag: "old")
    let before = try counts(target)

    #expect(throws: ArchiveError.invalidRecord("DayRecord", 1)) {
        try ProgressArchive.replaceAll(with: archive, context: target)
    }
    #expect(!target.hasChanges)
    #expect(try counts(target) == before)
    #expect(try target.fetch(FetchDescriptor<SessionRecord>()).compactMap(\.source) == ["library:old"])
    #expect(try target.fetch(FetchDescriptor<CustomText>()).map(\.title) == ["Заметка old"])
}

@MainActor @Test func duplicateUniqueKeyInArchiveIsRejected() throws {
    let sourceContainer = try ModelStore.makeContainer(inMemory: true)
    let source = sourceContainer.mainContext
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    try populate(source)
    var archive = try ProgressArchive.decode(ProgressArchive.export(context: source, defaults: defaults, now: base))
    archive.lessonProgress.append(archive.lessonProgress[0])

    let targetContainer = try ModelStore.makeContainer(inMemory: true)
    let target = targetContainer.mainContext
    try populate(target, tag: "old")
    let before = try counts(target)
    #expect(throws: ArchiveError.duplicate("LessonProgress", "ru.1.1")) {
        try ProgressArchive.replaceAll(with: archive, context: target)
    }
    #expect(try counts(target) == before)
    // Та же проверка срабатывает уже при чтении файла — до резервной копии и замены.
    let data = try ProgressArchive.encode(archive)
    #expect(throws: ArchiveError.duplicate("LessonProgress", "ru.1.1")) { _ = try ProgressArchive.decode(data) }
}

// MARK: - Сводка

@MainActor @Test func summaryDescribesArchive() throws {
    let contextContainer = try ModelStore.makeContainer(inMemory: true)
    let context = contextContainer.mainContext
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    try populate(context)
    defaults.set("rusl3n", forKey: SettingsKey.profileNickname)
    defaults.set("Руслан", forKey: SettingsKey.profileFullName)
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: context, defaults: defaults, now: base))

    let summary = ProgressArchive.summary(archive)
    #expect(summary.sessionCount == 2)
    #expect(summary.dayCount == 2)
    #expect(summary.nickname == "rusl3n" && summary.fullName == "Руслан")
    #expect(abs((summary.firstDate ?? .distantFuture).timeIntervalSince(base)) < 0.001)
    #expect(abs((summary.lastDate ?? .distantPast).timeIntervalSince(base.addingTimeInterval(86_700))) < 0.001)
    #expect(abs((summary.exportedAt ?? .distantPast).timeIntervalSince(base)) < 0.001)

    let empty = ProgressArchive.summary(try ProgressArchive.decode(
        archiveJSON(#""format": "tenfingers-progress", "version": 1, "schemaGeneration": 2"#)))
    #expect(empty.sessionCount == 0 && empty.firstDate == nil && empty.lastDate == nil)
}

// MARK: - Настройки и профиль

@MainActor @Test func settingsProfileAndLessonResumeTravelWithArchive() throws {
    let contextContainer = try ModelStore.makeContainer(inMemory: true)
    let context = contextContainer.mainContext
    let (source, sourceName) = makeDefaults()
    let (target, targetName) = makeDefaults()
    defer {
        removeTestDefaults(sourceName)
        removeTestDefaults(targetName)
    }
    source.set("dark", forKey: SettingsKey.themeMode)
    source.set(15, forKey: SettingsKey.dailyGoalMinutes)
    source.set(40.0, forKey: SettingsKey.keyboardUnit)
    source.set(-12.5, forKey: SettingsKey.keyboardOffset)
    source.set(1.25, forKey: SettingsKey.uiScale)
    source.set(true, forKey: SettingsKey.remindersEnabled)
    source.set(false, forKey: SoundSettings.enabledKey(.keyClick))
    source.set(0.45, forKey: SoundSettings.volumeKey(.error))
    source.set("ник", forKey: SettingsKey.profileNickname)
    source.set("general", forKey: SettingsKey.settingsSection)
    LessonResume(defaults: source).stepFinished(lessonId: "ru.2.1", index: 1, totalSteps: 4, now: base)

    // В целевом — другие значения, ключ, которого нет в архиве, и чужое продолжение урока.
    target.set("light", forKey: SettingsKey.themeMode)
    target.set(7, forKey: SettingsKey.dayStartHour)
    target.set("Старое имя", forKey: SettingsKey.profileFullName)
    target.set("keyboard", forKey: SettingsKey.settingsSection)
    LessonResume(defaults: target).stepFinished(lessonId: "ru.9.9", index: 0, totalSteps: 3, now: base)

    let archive = try ProgressArchive.decode(ProgressArchive.export(context: context, defaults: source, now: base))
    #expect(archive.settings[SettingsKey.settingsSection] == nil)
    #expect(archive.settings[SettingsKey.profileNickname] == nil)
    #expect(archive.profile.nickname == "ник")

    ProgressArchive.applyPreferences(of: archive, to: target)
    #expect(target.string(forKey: SettingsKey.themeMode) == "dark")
    #expect(target.object(forKey: SettingsKey.dailyGoalMinutes) as? Int == 15)
    #expect(target.object(forKey: SettingsKey.keyboardUnit) as? Double == 40)
    #expect(target.object(forKey: SettingsKey.keyboardOffset) as? Double == -12.5)
    #expect(target.object(forKey: SettingsKey.uiScale) as? Double == 1.25)
    #expect(target.object(forKey: SettingsKey.remindersEnabled) as? Bool == true)
    #expect(SoundSettings.isEnabled(.keyClick, defaults: target) == false)
    #expect(SoundSettings.volume(.error, defaults: target) == 0.45)
    // Ключа нет в архиве — значение по умолчанию.
    #expect(target.object(forKey: SettingsKey.dayStartHour) == nil)
    #expect(target.string(forKey: SettingsKey.profileNickname) == "ник")
    #expect(target.object(forKey: SettingsKey.profileFullName) == nil)
    // Открытый раздел настроек — состояние окна, а не настройка: не меняется.
    #expect(target.string(forKey: SettingsKey.settingsSection) == "keyboard")
    #expect(LessonResume(defaults: target).load(lessonId: "ru.2.1")?.completedSteps == 2)
    #expect(LessonResume(defaults: target).load(lessonId: "ru.9.9") == nil)
}

@Test func settingValuesOfWrongTypeOrUnknownKeysAreIgnored() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    defaults.set(5, forKey: SettingsKey.dailyGoalMinutes)
    let archive = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 2,
        "settings": { "dailyGoalMinutes": "много", "uiScale": 1, "unknownKey": true, "dayStartHour": 5.5 }
        """#))
    ProgressArchive.applyPreferences(of: archive, to: defaults)
    #expect(defaults.object(forKey: SettingsKey.dailyGoalMinutes) as? Int == 5)
    #expect(defaults.object(forKey: SettingsKey.uiScale) as? Double == 1)
    #expect(defaults.object(forKey: "unknownKey") == nil)
    #expect(defaults.object(forKey: SettingsKey.dayStartHour) == nil)
}

/// В архиве поколения 2 нет настроек фазы 4 («Взрослый юмор», опции карточки): текущие значения сохраняются,
/// а не сбрасываются к значениям по умолчанию. В архиве поколения 3 отсутствие ключа — значение по умолчанию.
@Test func settingsNewerThanArchiveGenerationKeepCurrentValues() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    defaults.set(false, forKey: SettingsKey.adultHumor)
    defaults.set("dark", forKey: SettingsKey.shareTheme)
    defaults.set(15, forKey: SettingsKey.dailyGoalMinutes)
    defaults.set(true, forKey: SettingsKey.shareQR)
    defaults.set("year", forKey: SettingsKey.shareProgressPeriod)
    let old = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 2, "settings": {}
        """#))
    ProgressArchive.applyPreferences(of: old, to: defaults)
    #expect(defaults.object(forKey: SettingsKey.adultHumor) as? Bool == false)
    #expect(defaults.string(forKey: SettingsKey.shareTheme) == "dark")
    #expect(defaults.object(forKey: SettingsKey.dailyGoalMinutes) == nil)
    #expect(defaults.object(forKey: SettingsKey.shareQR) as? Bool == true)
    #expect(defaults.string(forKey: SettingsKey.shareProgressPeriod) == "year")

    let current = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 3, "settings": {}
        """#))
    ProgressArchive.applyPreferences(of: current, to: defaults)
    #expect(defaults.object(forKey: SettingsKey.adultHumor) == nil)
    #expect(defaults.object(forKey: SettingsKey.shareTheme) == nil)
    // Поколение 3 ещё не знает «QR-код» (поколение 4): значение остаётся.
    #expect(defaults.object(forKey: SettingsKey.shareQR) as? Bool == true)
    #expect(defaults.string(forKey: SettingsKey.shareProgressPeriod) == "year")

    let latest = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 4, "settings": {}
        """#))
    ProgressArchive.applyPreferences(of: latest, to: defaults)
    #expect(defaults.object(forKey: SettingsKey.shareQR) == nil)
    #expect(defaults.object(forKey: SettingsKey.shareProgressPeriod) == nil)
}

/// Период карточки «Мой прогресс» попадает в архив строкой и возвращается из него.
@Test func progressPeriodSettingRoundTripsThroughArchive() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    defaults.set("year", forKey: SettingsKey.shareProgressPeriod)
    #expect(ArchivedSettings.read(defaults)[SettingsKey.shareProgressPeriod] == .string("year"))
    #expect(ArchivedSettings.introducedIn[SettingsKey.shareProgressPeriod] == 4)
}

private let progressContentKeys = [
    SettingsKey.shareProgressShowStreak, SettingsKey.shareProgressShowFullDays, SettingsKey.shareProgressShowTime,
    SettingsKey.shareProgressShowSpeed, SettingsKey.shareProgressShowAccuracy,
    SettingsKey.shareAchievementShowJoke, SettingsKey.shareAchievementShowReason,
]

/// Содержимое карточек «Мой прогресс» и ачивки и значение «all» периода переезжают в архив и обратно; ключи введены в поколении 5.
@Test func progressCardContentSettingsRoundTripThroughArchive() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    defaults.set("all", forKey: SettingsKey.shareProgressPeriod)
    for (index, key) in progressContentKeys.enumerated() { defaults.set(index.isMultiple(of: 2), forKey: key) }
    let read = ArchivedSettings.read(defaults)
    #expect(read[SettingsKey.shareProgressPeriod] == .string("all"))
    for (index, key) in progressContentKeys.enumerated() {
        #expect(read[key] == .bool(index.isMultiple(of: 2)))
        #expect(ArchivedSettings.introducedIn[key] == 5)
        #expect(ArchivedSettings.entries.contains { $0.key == key && $0.kind == .bool })
    }
    // В файле: «all» и переключатели проходят через архив.
    let (target, targetName) = makeDefaults()
    defer { removeTestDefaults(targetName) }
    ArchivedSettings.apply(read, generation: 5, to: target)
    #expect(target.string(forKey: SettingsKey.shareProgressPeriod) == "all")
    for (index, key) in progressContentKeys.enumerated() {
        #expect(target.object(forKey: key) as? Bool == index.isMultiple(of: 2))
    }
}

/// Архивы поколений 3 и 4 не знают этих ключей: текущие значения остаются; архив поколения 5 без них — значения по умолчанию.
@Test func progressCardContentSettingsSurviveGenerationThreeArchive() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    for key in progressContentKeys { defaults.set(false, forKey: key) }
    let old = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 3, "settings": {}
        """#))
    ProgressArchive.applyPreferences(of: old, to: defaults)
    for key in progressContentKeys { #expect(defaults.object(forKey: key) as? Bool == false, "\(key)") }
    let previous = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 4, "settings": {}
        """#))
    ProgressArchive.applyPreferences(of: previous, to: defaults)
    for key in progressContentKeys { #expect(defaults.object(forKey: key) as? Bool == false, "\(key)") }
    let latest = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 5, "settings": {}
        """#))
    ProgressArchive.applyPreferences(of: latest, to: defaults)
    for key in progressContentKeys { #expect(defaults.object(forKey: key) == nil, "\(key)") }
}

private let reminderScheduleKeys = [
    SettingsKey.reminderSchedule, SettingsKey.reminderTime1, SettingsKey.reminderTime2, SettingsKey.reminderTime3,
    SettingsKey.reminderFromHour, SettingsKey.reminderToHour, SettingsKey.reminderIntervalHours,
    SettingsKey.reminderTone, SettingsKey.reminderEscalating,
]

/// Расписание, тон и нарастание напоминаний переезжают в архив и обратно; ключи введены в поколении 4.
@MainActor @Test func reminderScheduleSettingsTravelWithArchive() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let (source, sourceName) = makeDefaults()
    let (target, targetName) = makeDefaults()
    defer {
        removeTestDefaults(sourceName)
        removeTestDefaults(targetName)
    }
    source.set("interval", forKey: SettingsKey.reminderSchedule)
    source.set(540, forKey: SettingsKey.reminderTime1)
    source.set(800, forKey: SettingsKey.reminderTime2)
    source.set(1100, forKey: SettingsKey.reminderTime3)
    source.set(8, forKey: SettingsKey.reminderFromHour)
    source.set(22, forKey: SettingsKey.reminderToHour)
    source.set(2, forKey: SettingsKey.reminderIntervalHours)
    source.set("funny", forKey: SettingsKey.reminderTone)
    source.set(true, forKey: SettingsKey.reminderEscalating)
    let read = ArchivedSettings.read(source)
    for key in reminderScheduleKeys {
        #expect(read[key] != nil, "\(key) не попал в архив")
        #expect(ArchivedSettings.introducedIn[key] == 4)
    }
    let archive = try ProgressArchive.decode(ProgressArchive.export(
        context: container.mainContext, defaults: source, now: base))
    ProgressArchive.applyPreferences(of: archive, to: target)
    #expect(StoredSettings.reminders(target) == StoredSettings.reminders(source))
    #expect(target.string(forKey: SettingsKey.reminderSchedule) == "interval")
    #expect(target.object(forKey: SettingsKey.reminderTime2) as? Int == 800)
    #expect(target.object(forKey: SettingsKey.reminderEscalating) as? Bool == true)
}

/// Архив поколения 3 не знает новых ключей напоминаний: настроенное расписание не сбрасывается,
/// а прежние время и включённость применяются.
@Test func generationThreeArchiveKeepsReminderSchedule() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    defaults.set("thrice", forKey: SettingsKey.reminderSchedule)
    defaults.set(777, forKey: SettingsKey.reminderTime1)
    defaults.set(2, forKey: SettingsKey.reminderIntervalHours)
    defaults.set("funny", forKey: SettingsKey.reminderTone)
    defaults.set(true, forKey: SettingsKey.reminderEscalating)
    let archive = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 3,
        "settings": {"remindersEnabled": true, "reminderHour": 7, "reminderMinute": 30}
        """#))
    ProgressArchive.applyPreferences(of: archive, to: defaults)
    #expect(defaults.string(forKey: SettingsKey.reminderSchedule) == "thrice")
    #expect(defaults.object(forKey: SettingsKey.reminderTime1) as? Int == 777)
    #expect(defaults.object(forKey: SettingsKey.reminderIntervalHours) as? Int == 2)
    #expect(defaults.string(forKey: SettingsKey.reminderTone) == "funny")
    #expect(defaults.object(forKey: SettingsKey.reminderEscalating) as? Bool == true)
    #expect(defaults.object(forKey: SettingsKey.reminderHour) as? Int == 7)
    #expect(defaults.object(forKey: SettingsKey.remindersEnabled) as? Bool == true)
    // Поколение 4 без ключей — возврат к умолчаниям.
    let current = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 4, "settings": {}
        """#))
    ProgressArchive.applyPreferences(of: current, to: defaults)
    for key in reminderScheduleKeys { #expect(defaults.object(forKey: key) == nil, "\(key)") }
}

@Test func settingNumbersOutsideValidRangesAreClampedOnApply() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    let archive = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 2,
        "settings": {
            "dayStartHour": 99, "dailyGoalMinutes": 12, "adaptiveTargetCpm": 9999,
            "keyboardUnit": 500, "keyboardOffset": -9000, "uiScale": 7,
            "darkFromHour": -3, "darkToHour": 40, "reminderHour": 24, "reminderMinute": 75,
            "reminderTime1": -10, "reminderTime2": 5000, "reminderTime3": 700, "reminderFromHour": 40,
            "reminderToHour": -2, "reminderIntervalHours": 9,
            "sound.keyClick.volume": 5
        }
        """#))
    ProgressArchive.applyPreferences(of: archive, to: defaults)
    #expect(defaults.object(forKey: SettingsKey.dayStartHour) as? Int == 6)
    #expect(defaults.object(forKey: SettingsKey.dailyGoalMinutes) as? Int == 10) // ближайшее из списка
    #expect(defaults.object(forKey: SettingsKey.adaptiveTargetCpm) as? Int == 250)
    #expect(defaults.object(forKey: SettingsKey.keyboardUnit) as? Double == KeyboardSizing.unitRange.upperBound)
    #expect(defaults.object(forKey: SettingsKey.keyboardOffset) as? Double == KeyboardSizing.offsetRange.lowerBound)
    #expect(defaults.object(forKey: SettingsKey.uiScale) as? Double == 1.5)
    #expect(defaults.object(forKey: SettingsKey.darkFromHour) as? Int == 0)
    #expect(defaults.object(forKey: SettingsKey.darkToHour) as? Int == 23)
    #expect(defaults.object(forKey: SettingsKey.reminderHour) as? Int == 23)
    #expect(defaults.object(forKey: SettingsKey.reminderMinute) as? Int == 59)
    #expect(defaults.object(forKey: SettingsKey.reminderTime1) as? Int == 0)
    #expect(defaults.object(forKey: SettingsKey.reminderTime2) as? Int == 1439)
    #expect(defaults.object(forKey: SettingsKey.reminderTime3) as? Int == 700)
    #expect(defaults.object(forKey: SettingsKey.reminderFromHour) as? Int == 23)
    #expect(defaults.object(forKey: SettingsKey.reminderToHour) as? Int == 0)
    #expect(defaults.object(forKey: SettingsKey.reminderIntervalHours) as? Int == 4)
    #expect(defaults.object(forKey: SoundSettings.volumeKey(.keyClick)) as? Double == 1)
}

@Test func settingNumbersInsideValidRangesAreAppliedAsIs() throws {
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    let archive = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 2,
        "settings": {
            "dayStartHour": 0, "dailyGoalMinutes": 30, "adaptiveTargetCpm": 150, "keyboardUnit": 44,
            "keyboardOffset": 20.5, "uiScale": 1.1, "darkFromHour": 21, "darkToHour": 6,
            "reminderHour": 7, "reminderMinute": 30, "sound.error.volume": 0.25
        }
        """#))
    ProgressArchive.applyPreferences(of: archive, to: defaults)
    #expect(defaults.object(forKey: SettingsKey.dayStartHour) as? Int == 0)
    #expect(defaults.object(forKey: SettingsKey.dailyGoalMinutes) as? Int == 30)
    #expect(defaults.object(forKey: SettingsKey.adaptiveTargetCpm) as? Int == 150)
    #expect(defaults.object(forKey: SettingsKey.keyboardUnit) as? Double == 44)
    #expect(defaults.object(forKey: SettingsKey.keyboardOffset) as? Double == 20.5)
    #expect(defaults.object(forKey: SettingsKey.uiScale) as? Double == 1.1)
    #expect(defaults.object(forKey: SettingsKey.darkFromHour) as? Int == 21)
    #expect(defaults.object(forKey: SettingsKey.darkToHour) as? Int == 6)
    #expect(defaults.object(forKey: SettingsKey.reminderHour) as? Int == 7)
    #expect(defaults.object(forKey: SettingsKey.reminderMinute) as? Int == 30)
    #expect(defaults.object(forKey: SoundSettings.volumeKey(.error)) as? Double == 0.25)
}

// MARK: - Импорт целиком: резервная копия, база на диске, отказ посреди импорта

private struct SimulatedDiskFailure: Error {}

@MainActor @Test func importOnDiskBacksUpFirstAndSurvivesFailure() async throws {
    let directory = try temporaryDirectory("TenFingersImport")
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeDirectory = directory.appendingPathComponent("store", isDirectory: true)
    try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    let storeURL = storeDirectory.appendingPathComponent("TenFingers.store")
    let backups = directory.appendingPathComponent("TenFingers.backups", isDirectory: true)
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    defaults.set("старый", forKey: SettingsKey.profileNickname)

    // Архив для загрузки — из другого (в памяти) прогресса.
    let otherContainer = try ModelStore.makeContainer(inMemory: true)
    let other = otherContainer.mainContext
    let (otherDefaults, otherName) = makeDefaults()
    defer { removeTestDefaults(otherName) }
    try populate(other, tag: "new")
    // Те же уникальные ключи (урок, день), что и в базе на диске, но другие значения.
    for lesson in try other.fetch(FetchDescriptor<LessonProgress>()) { lesson.attempts = 42 }
    for day in try other.fetch(FetchDescriptor<DayRecord>()) { day.activeSeconds = 999 }
    try other.save()
    otherDefaults.set("новый", forKey: SettingsKey.profileNickname)
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: other, defaults: otherDefaults, now: base))

    var before: [Int] = []
    do {
        let container = try ModelStore.makeContainer(at: storeURL)
        try populate(container.mainContext, tag: "old")
        before = try counts(container.mainContext)

        // Отказ при сохранении (после удаления и вставки): резервная копия есть, база не изменилась.
        var failing = ProgressImporter(context: container.mainContext, defaults: defaults, backupDirectory: backups)
        failing.beforeSave = { throw SimulatedDiskFailure() }
        #expect(throws: SimulatedDiskFailure.self) { _ = try failing.importArchive(archive, now: base) }
        #expect(defaults.string(forKey: SettingsKey.profileNickname) == "старый")
        #expect(try counts(container.mainContext) == before)
    }
    try await waitUntilStoreFilesClosed(in: storeDirectory)

    let firstBackup = backups.appendingPathComponent("pre-import-\(ProgressArchive.timestamp(base)).tenfingers")
    let backedUp = try ProgressArchive.decode(Data(contentsOf: firstBackup))
    #expect(backedUp.sessions.compactMap(\.source) == ["library:old"])
    #expect(backedUp.profile.nickname == "старый")

    do {
        // Открытая заново база с диска — исходные данные на месте.
        let container = try ModelStore.makeContainer(at: storeURL)
        let context = container.mainContext
        #expect(try counts(context) == before)
        #expect(try context.fetch(FetchDescriptor<CustomText>()).map(\.title) == ["Заметка old"])

        // Теперь настоящий импорт.
        let importer = ProgressImporter(context: context, defaults: defaults, backupDirectory: backups)
        let backup = try importer.importArchive(archive, now: base)
        #expect(backup.lastPathComponent == "pre-import-\(ProgressArchive.timestamp(base))-2.tenfingers")
        // Диагностика для CI: при сбое видно, что лежит в постоянном домене и что читает свежий экземпляр.
        let nickname = defaults.string(forKey: SettingsKey.profileNickname)
        #expect(nickname == "новый", Comment(rawValue: "archive=\(archive.profile.nickname) persistent=\(String(describing: UserDefaults().persistentDomain(forName: name)?[SettingsKey.profileNickname])) fresh=\(String(describing: UserDefaults(suiteName: name)?.string(forKey: SettingsKey.profileNickname)))"))
    }
    try await waitUntilStoreFilesClosed(in: storeDirectory)

    do {
        let container = try ModelStore.makeContainer(at: storeURL)
        let context = container.mainContext
        #expect(try counts(context) == [2, 2, 2, 1, 2, 1, 1, 1, 1, 1])
        #expect(try context.fetch(FetchDescriptor<SessionRecord>()).compactMap(\.source) == ["library:new"])
        #expect(try context.fetch(FetchDescriptor<CustomText>()).map(\.title) == ["Заметка new"])
        #expect(try context.fetch(FetchDescriptor<CustomText>()).first?.offset == 7)
        #expect(try context.fetch(FetchDescriptor<LessonProgress>()).map(\.attempts) == [42, 42])
        #expect(try context.fetch(FetchDescriptor<DayRecord>()).map(\.activeSeconds) == [999, 999])
    }
    try await waitUntilStoreFilesClosed(in: storeDirectory)
}

/// Резервную копию записать нельзя — импорт не начинается.
@MainActor @Test func importIsAbortedWhenBackupCannotBeWritten() throws {
    let directory = try temporaryDirectory("TenFingersBackupFail")
    defer { try? FileManager.default.removeItem(at: directory) }
    // На месте папки резервных копий — файл.
    let backups = directory.appendingPathComponent("TenFingers.backups")
    try Data("файл".utf8).write(to: backups)
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }

    let otherContainer = try ModelStore.makeContainer(inMemory: true)
    let other = otherContainer.mainContext
    try populate(other, tag: "new")
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: other, defaults: defaults, now: base))

    let contextContainer = try ModelStore.makeContainer(inMemory: true)
    let context = contextContainer.mainContext
    try populate(context, tag: "old")
    let importer = ProgressImporter(context: context, defaults: defaults, backupDirectory: backups)
    #expect {
        _ = try importer.importArchive(archive, now: base)
    } throws: { error in
        if case .backupFailed = error as? ProgressImportError { return true }
        return false
    }
    #expect(try context.fetch(FetchDescriptor<CustomText>()).map(\.title) == ["Заметка old"])
}

@Test func fileNamesUseDateAndTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 5, second: 4))!
    #expect(ProgressArchive.timestamp(date) == "2026-03-07_09-05-04")
    #expect(ProgressArchive.defaultFileName(now: date) == "TenFingers-progress-2026-03-07.tenfingers")
    #expect(ProgressArchive.fileType.preferredFilenameExtension == "tenfingers")
    #expect(ProgressArchive.fileType.conforms(to: .json))
}

// MARK: - Фаза 3, доработки: точность дат, терпимые настройки, сохранение перед заменой, проверка копии

/// Все модели заполнены, необязательные поля заданы, даты — с долями миллисекунды.
@MainActor private func populateFully(_ context: ModelContext) throws {
    try populate(context)
    let odd = base.addingTimeInterval(0.000_456_7)
    for session in try context.fetch(FetchDescriptor<SessionRecord>()) {
        session.source = session.source ?? "words"
        session.lessonId = session.lessonId ?? "ru.1.2"
        session.exerciseKind = session.exerciseKind ?? "keys"
        session.startedAt = session.startedAt.addingTimeInterval(0.123_456_789)
        session.fingerPresses = session.fingerPresses ?? FingerCounts.data([.rightPinky: 11, .leftIndex: 40, .thumb: 20])
        session.fingerErrors = session.fingerErrors ?? FingerCounts.data([.rightPinky: 2, .leftIndex: 0, .thumb: 1])
        session.yoPresses = session.yoPresses ?? 4
    }
    for stat in try context.fetch(FetchDescriptor<KeyStat>()) { stat.ewmaMs = stat.ewmaMs ?? 99.125 }
    for stat in try context.fetch(FetchDescriptor<BigramStat>()) { stat.ewmaMs = stat.ewmaMs ?? 77.5 }
    for lesson in try context.fetch(FetchDescriptor<LessonProgress>()) { lesson.passedAt = lesson.passedAt ?? odd }
    for day in try context.fetch(FetchDescriptor<DayRecord>()) { day.goalSeconds = day.goalSeconds ?? 900 }
    context.insert(AdaptiveUnlock(language: "en", letter: "e", unlockedAt: odd.addingTimeInterval(1e-7)))
    context.insert(CustomText(title: "Второй", body: "Текст два", language: "en", createdAt: odd))
    try context.save()
}

/// Настройки (все известные ключи), профиль и продолжение урока в домене `defaults`.
private func fillPreferences(_ defaults: UserDefaults) {
    for (key, kind) in ArchivedSettings.entries {
        switch kind {
        case .bool: defaults.set(true, forKey: key)
        // Значения в допустимых пределах: при загрузке числа приводятся к ним (`ArchivedSettings.apply`)
        case .int: defaults.set(key == SettingsKey.adaptiveTargetCpm ? 150 : key == SettingsKey.dailyGoalMinutes ? 15
                                    : key == SettingsKey.reminderIntervalHours ? 3 : 5, forKey: key)
        case .double: defaults.set(key == SettingsKey.keyboardUnit ? 44.0 : key == SettingsKey.uiScale ? 1.25 : 0.625,
                                   forKey: key)
        case .string: defaults.set("value-\(key)", forKey: key)
        }
    }
    defaults.set("ник", forKey: SettingsKey.profileNickname)
    defaults.set("Имя Фамилия", forKey: SettingsKey.profileFullName)
    LessonResume(defaults: defaults).stepFinished(lessonId: "ru.2.1", index: 1, totalSteps: 4,
                                                  now: base.addingTimeInterval(0.000_000_3))
}

/// Экспорт → замена в чистой базе → экспорт: файлы совпадают байт в байт (никакого дрейфа дат и порядка).
@MainActor @Test func exportImportExportIsByteIdentical() throws {
    let sourceContainer = try ModelStore.makeContainer(inMemory: true)
    let source = sourceContainer.mainContext
    let (sourceDefaults, sourceName) = makeDefaults()
    let (targetDefaults, targetName) = makeDefaults()
    defer {
        removeTestDefaults(sourceName)
        removeTestDefaults(targetName)
    }
    try populateFully(source)
    fillPreferences(sourceDefaults)

    let first = try ProgressArchive.export(context: source, defaults: sourceDefaults, now: base)
    let archive = try ProgressArchive.decode(first)
    #expect(archive.settings.count == ArchivedSettings.entries.count)
    #expect(archive.lessonResume.count == 1)

    let targetContainer = try ModelStore.makeContainer(inMemory: true)
    let target = targetContainer.mainContext
    try ProgressArchive.replaceAll(with: archive, context: target)
    ProgressArchive.applyPreferences(of: archive, to: targetDefaults)
    let second = try ProgressArchive.export(context: target, defaults: targetDefaults, now: base)
    #expect(try ProgressArchive.decode(second) == archive)
    #expect(first == second, "\(String(decoding: first, as: UTF8.self))\n≠\n\(String(decoding: second, as: UTF8.self))")

    // Даты не теряют точности: значения в базе совпадают с исходными до бита.
    let sourceDates = try source.fetch(FetchDescriptor<SessionRecord>()).map(\.startedAt).sorted()
    let targetDates = try target.fetch(FetchDescriptor<SessionRecord>()).map(\.startedAt).sorted()
    #expect(sourceDates == targetDates)
}

/// Старые файлы с датами строками ISO 8601 читаются так же, как новые с числами.
@Test func datesAreReadFromNumbersAndIsoStrings() throws {
    let archive = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 2,
        "exportedAt": 800000000.125,
        "adaptiveUnlocks": [
            { "language": "ru", "letter": "а", "unlockedAt": "2026-09-21T10:00:00.250Z" },
            { "language": "ru", "letter": "б", "unlockedAt": 811677600.25 }
        ]
        """#))
    #expect(archive.exportedAt == Date(timeIntervalSinceReferenceDate: 800_000_000.125))
    #expect(archive.adaptiveUnlocks.map(\.unlockedAt) == [
        Date(timeIntervalSinceReferenceDate: 811_677_600.25), Date(timeIntervalSinceReferenceDate: 811_677_600.25),
    ])
}

/// Каждая пользовательская настройка (`SettingsKey`) попадает в архив; исключения перечислены явно.
@Test func everyPreferenceKeyIsArchived() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/TenFingers/Settings/Settings.swift")
    let source = try String(contentsOf: file, encoding: .utf8)
    let body = try #require(source.components(separatedBy: "enum SettingsKey {").dropFirst().first?
        .components(separatedBy: "\n}").first)
    let pattern = try NSRegularExpression(pattern: #"static let \w+ = "([^"]+)""#)
    let keys = Set(pattern.matches(in: body, range: NSRange(body.startIndex..., in: body))
        .map { String(body[Range($0.range(at: 1), in: body)!]) })
    #expect(keys.count > 15)
    // Не настройки: состояние окна или устройства (язык интерфейса), прежний ключ темы; профиль — отдельным разделом архива.
    let excluded: Set<String> = [SettingsKey.settingsSection, SettingsKey.legacyTheme, SettingsKey.interfaceLanguage,
                                 SettingsKey.onboardingCompleted, SettingsKey.achievementsFilter,
                                 SettingsKey.profileNickname, SettingsKey.profileFullName]
    let archived = Set(ArchivedSettings.entries.map(\.key))
    #expect(keys.subtracting(excluded).subtracting(archived).isEmpty,
            "не в архиве: \(keys.subtracting(excluded).subtracting(archived).sorted())")
    #expect(archived.isDisjoint(with: excluded))
}

/// Незнакомый ключ любого вида и значение не того вида пропускаются, файл читается.
@Test func unknownOrOddSettingsDoNotBreakTheFile() throws {
    let archive = try ProgressArchive.decode(archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 2,
        "settings": { "futureList": [1, 2, 3], "futureObject": { "a": 1 }, "themeMode": ["dark"],
                      "dailyGoalMinutes": 15, "nothing": null }
        """#))
    #expect(archive.settings == [SettingsKey.dailyGoalMinutes: .int(15)])
}

/// Несохранённые изменения контекста сохраняются до замены: откат неудачной замены их не теряет.
@MainActor @Test func failedReplaceKeepsEarlierPendingEdits() throws {
    let sourceContainer = try ModelStore.makeContainer(inMemory: true)
    let source = sourceContainer.mainContext
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    try populate(source, tag: "new")
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: source, defaults: defaults, now: base))

    let targetContainer = try ModelStore.makeContainer(inMemory: true)
    let target = targetContainer.mainContext
    try populate(target, tag: "old")
    // Правка, сделанная до импорта и ещё не сохранённая.
    target.insert(CounterRecord(name: CounterName.wrongLayoutStarts))
    #expect(target.hasChanges)

    #expect(throws: SimulatedDiskFailure.self) {
        try ProgressArchive.replaceAll(with: archive, context: target, beforeSave: { throw SimulatedDiskFailure() })
    }
    #expect(Set(try target.fetch(FetchDescriptor<CounterRecord>()).map(\.name))
        == [CounterName.capsLockPresses, CounterName.wrongLayoutStarts])
}

/// Сообщения об ошибках — без технического текста `DecodingError` и с человеческими названиями разделов.
@Test func archiveErrorsAreHumanReadable() throws {
    let data = archiveJSON(#""format": "tenfingers-progress", "version": 1, "schemaGeneration": 2, "sessions": [{"mode": "course"}]"#)
    #expect(throws: ArchiveError.damaged("sessions.0.language")) { _ = try ProgressArchive.decode(data) }
    let typeMismatch = archiveJSON(#""format": "tenfingers-progress", "version": 1, "schemaGeneration": 2, "days": [{"logicalDay": 5}]"#)
    #expect(throws: ArchiveError.damaged("days.0.logicalDay")) { _ = try ProgressArchive.decode(typeMismatch) }

    let damaged = try #require(ArchiveError.damaged("sessions.0.language").errorDescription)
    #expect(damaged.contains("№ 1") && damaged.contains("language") && !damaged.contains("sessions"))
    for model in ["SessionRecord", "DayRecord", "KeyStat", "BigramStat", "LessonProgress", "AdaptiveState",
                  "AdaptiveUnlock", "CounterRecord", "CustomText"] {
        let invalid = try #require(ArchiveError.invalidRecord(model, 1).errorDescription)
        #expect(!invalid.contains(model), "\(invalid)")
        #expect(invalid.contains("№ 2"))
        let duplicate = try #require(ArchiveError.duplicate(model, "k").errorDescription)
        #expect(!duplicate.contains(model), "\(duplicate)")
    }
}

/// Резервная копия проверяется по устройству файла, а не строгой проверкой записей:
/// странная запись в текущей базе не должна запрещать любую загрузку.
@MainActor @Test func backupOfStoreWithOddRecordIsWritten() throws {
    let directory = try temporaryDirectory("TenFingersOddBackup")
    defer { try? FileManager.default.removeItem(at: directory) }
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populate(context)
    context.insert(CustomText(title: "без языка", body: "текст", language: "", createdAt: base.addingTimeInterval(1)))
    try context.save()

    let importer = ProgressImporter(context: context, defaults: defaults, backupDirectory: directory)
    let backup = try importer.writeBackup(now: base)
    let data = try Data(contentsOf: backup)
    #expect(throws: ArchiveError.invalidRecord("CustomText", 1)) { _ = try ProgressArchive.decode(data) }
    #expect(try ProgressArchive.decodeStructure(data).customTexts.count == 2)
}

/// Поля поколения 4 (статистика пальцев и «ё»): в файле — словарь «палец → число» и число, при загрузке — как были.
@MainActor @Test func fingerAndYoFieldsRoundTripThroughArchive() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populate(context)
    let sessions = try context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt)]))
    sessions[0].fingerPresses = FingerCounts.data([.leftPinky: 9, .thumb: 20])
    sessions[0].fingerErrors = FingerCounts.data([.leftPinky: 1, .thumb: 0])
    sessions[0].yoPresses = 3
    try context.save()
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }

    let data = try ProgressArchive.export(context: context, defaults: defaults, now: base)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let records = try #require(json["sessions"] as? [[String: Any]])
    let withStats = try #require(records.first { $0["yoPresses"] != nil })
    #expect(withStats["fingerPresses"] as? [String: Int] == ["leftPinky": 9, "thumb": 20])
    #expect(withStats["fingerErrors"] as? [String: Int] == ["leftPinky": 1, "thumb": 0])
    #expect(withStats["yoPresses"] as? Int == 3)
    // Сессия без статистики (как до 1.1.0) — полей в файле нет.
    #expect(records.contains { $0["fingerPresses"] == nil && $0["yoPresses"] == nil })

    let target = try ModelStore.makeContainer(inMemory: true)
    try ProgressArchive.replaceAll(with: try ProgressArchive.decode(data), context: target.mainContext)
    let restored = try target.mainContext.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt)]))
    #expect(FingerCounts.counts(restored[0].fingerPresses) == [.leftPinky: 9, .thumb: 20])
    #expect(FingerCounts.counts(restored[0].fingerErrors) == [.leftPinky: 1, .thumb: 0])
    #expect(restored[0].yoPresses == 3)
    #expect(restored[1].fingerPresses == nil && restored[1].fingerErrors == nil && restored[1].yoPresses == nil)
}

/// Поле поколения 5 (цель дня): в файле — число секунд, при загрузке — как было; у дня без цели поля в файле нет.
@MainActor @Test func dayGoalRoundTripsThroughArchive() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populate(context)
    let days = try context.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.logicalDay)]))
    days[0].goalSeconds = 900
    try context.save()
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }

    let data = try ProgressArchive.export(context: context, defaults: defaults, now: base)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let records = try #require(json["days"] as? [[String: Any]])
    #expect(records.map { $0["goalSeconds"] as? Double } == [900, nil])

    let target = try ModelStore.makeContainer(inMemory: true)
    try ProgressArchive.replaceAll(with: try ProgressArchive.decode(data), context: target.mainContext)
    let restored = try target.mainContext.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.logicalDay)]))
    #expect(restored.map(\.goalSeconds) == [900, nil])
}

/// Файл поколения 4 (без цели дня) загружается: цель пустая, и после загрузки дням до сегодняшнего включительно
/// записывается дневная цель из загруженных настроек. Смена цели на следующий день (без перезапуска) их не меняет.
@MainActor @Test func generationFourArchiveGetsDayGoalsAfterImport() throws {
    let data = archiveJSON(#"""
        "format": "tenfingers-progress", "version": 1, "schemaGeneration": 4,
        "settings": { "dailyGoalMinutes": 15, "dayStartHour": 4 },
        "days": [
            { "logicalDay": "2026-09-20", "activeSeconds": 900, "completedExercises": 2, "languages": ["ru"] },
            { "logicalDay": "2026-09-21", "activeSeconds": 60, "completedExercises": 1, "languages": ["ru"] }
        ]
        """#)
    let archive = try ProgressArchive.decode(data)
    #expect(archive.days.map(\.goalSeconds) == [nil, nil])
    let directory = try temporaryDirectory("TenFingersDayGoalImport")
    defer { try? FileManager.default.removeItem(at: directory) }
    let (defaults, name) = makeDefaults()
    defer { removeTestDefaults(name) }
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let importer = ProgressImporter(context: context, defaults: defaults, backupDirectory: directory)
    // `base` — 21 сентября днём: логически сегодня 21-е.
    _ = try importer.importArchive(archive, now: base)
    let days = try context.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.logicalDay)]))
    #expect(days.map(\.goalSeconds) == [900, 900])
    #expect(days.map(\.activeSeconds) == [900, 60])

    defaults.set(30, forKey: SettingsKey.dailyGoalMinutes)
    DayGoals.goalChangedLogging(context: context, previousGoalSeconds: 900, defaults: defaults,
                                now: base.addingTimeInterval(86_400))
    #expect(try context.fetch(FetchDescriptor<DayRecord>()).map(\.goalSeconds) == [900, 900])
}
