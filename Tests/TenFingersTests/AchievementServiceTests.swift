import Foundation
import SwiftData
import SwiftUI
import Testing
import TypingCore
@testable import TenFingers

// MARK: - Помощники

private let msk = TimeZone(identifier: "Europe/Moscow")!

/// «2026-10-23 21:42:30» по Москве.
private func at(_ text: String) -> Date {
    let parts = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" }).compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = msk
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3],
                                              minute: parts[4], second: parts.count > 5 ? parts[5] : 0))!
}

@MainActor private func insertSession(_ context: ModelContext, ended: String, day: String, mode: String = "course",
                                      language: String = "ru", lessonId: String? = nil, kind: String? = nil,
                                      chars: Int = 80, seconds: Double = 30, accuracy: Double = 0.99,
                                      cpm: Double = 160, completed: Bool = true, hint: String = "full",
                                      maxErrorStreak: Int = 1, wrong: Int = 1, pinky: Int = 0, pinkyErrors: Int = 0,
                                      source: String? = nil, fingerPresses: [Finger: Int]? = nil,
                                      fingerErrors: [Finger: Int]? = nil, yo: Int? = nil, stepIndex: Int? = nil,
                                      planSlot: String? = nil, traits: Int? = nil) {
    let end = at(ended)
    context.insert(SessionRecord(
        mode: mode, language: language, lessonId: lessonId, startedAt: end.addingTimeInterval(-seconds), endedAt: end,
        logicalDay: day, activeSeconds: seconds, chars: chars, errorCount: wrong, cpm: cpm, accuracy: accuracy,
        completed: completed, hintLevel: hint, maxErrorStreak: maxErrorStreak, wrongKeystrokes: wrong,
        exerciseKind: kind, pinkyPresses: pinky, pinkyErrors: pinkyErrors, source: source,
        fingerPresses: fingerPresses.map(FingerCounts.data), fingerErrors: fingerErrors.map(FingerCounts.data),
        yoPresses: yo, stepIndex: stepIndex, planSlot: planSlot, textTraits: traits))
}

@MainActor private func makeService(_ context: ModelContext, now: Date = at("2026-10-24 07:00"),
                                    catalog: [Achievement] = AchievementCatalog.all,
                                    beforeSave: (() throws -> Void)? = nil) -> AchievementService {
    var recorder = ResultRecorder(context: context, dayStartHour: 4)
    recorder.beforeSave = beforeSave
    return AchievementService(recorder: recorder, goalSeconds: { 600 }, timeZone: msk, now: { now }, catalog: catalog)
}

/// Курсы издания 1 (`ru.1.1` …) для ожидаемых значений: архив, у языка без архива — текущий файл.
private let editionOneCourses: [Language: Course] = Dictionary(uniqueKeysWithValues: Language.allCases.compactMap {
    language in (try? CourseCatalog.legacy(language) ?? CourseCatalog.load(language)).map { (language, $0) }
})

/// История, похожая на настоящую: урок «ru.1.1» пройден вечером, ночью тренировка и брошенные шаги,
/// урок «ru.1.2» засчитан без истории проверок (до записи шагов), адаптивный режим открыл седьмую букву.
@MainActor private func populateHistory(_ context: ModelContext) throws {
    insertSession(context, ended: "2026-10-23 21:41:59", day: "2026-10-23", lessonId: "ru.1.1", kind: "words",
                  chars: 120, seconds: 36)
    insertSession(context, ended: "2026-10-23 21:42:30", day: "2026-10-23", lessonId: "ru.1.1", kind: "check",
                  chars: 89, seconds: 27.1, accuracy: 0.978, cpm: 197, maxErrorStreak: 1, wrong: 2)
    insertSession(context, ended: "2026-10-24 02:40:00", day: "2026-10-23", mode: "adaptive", chars: 4, seconds: 2,
                  completed: false)
    insertSession(context, ended: "2026-10-24 02:42:16", day: "2026-10-23", mode: "adaptive", chars: 241,
                  seconds: 91.9, accuracy: 0.996, cpm: 157, hint: "onError", pinky: 31, pinkyErrors: 0)
    insertSession(context, ended: "2026-10-24 02:43:00", day: "2026-10-23", mode: "future-mode", chars: 10)

    let first = LessonProgress(lessonId: "ru.1.1", language: "ru")
    first.attempts = 2
    first.bestStars = 3   // в базе 3, но по истории проверок — ★★ (197 зн/мин, точность 97,8%)
    first.passedAt = at("2026-10-23 21:42:30")
    context.insert(first)
    let second = LessonProgress(lessonId: "ru.1.2", language: "ru")
    second.attempts = 1
    second.bestStars = 2
    second.passedAt = at("2026-10-24 02:34:32")
    context.insert(second)

    let day = DayRecord(logicalDay: "2026-10-23")
    day.activeSeconds = 700
    day.completedExercises = 3
    day.abandonedExercises = 1
    day.languages = ["ru", "en", "xx"]
    context.insert(day)

    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 0
    context.insert(caps)
    context.insert(AdaptiveState(language: "ru", unlockedCount: 7))
    let seventh = Language.ru.adaptiveOrder[6]
    context.insert(AdaptiveUnlock(language: "ru", letter: String(seventh), unlockedAt: at("2026-10-24 02:42:16")))
    try context.save()
}

@MainActor private func records(_ context: ModelContext) throws -> [AchievementRecord] {
    try context.fetch(FetchDescriptor<AchievementRecord>(sortBy: [SortDescriptor(\.achievementId)]))
}

// MARK: - Каталог и счётчики

/// Имена счётчиков в каталоге совпадают с тем, что пишет приложение (`CounterName`).
@Test func catalogCountersAreAppCounterNames() {
    var names: [String] = []
    for achievement in AchievementCatalog.all {
        if case let .counter(name, _) = achievement.condition { names.append(name) }
    }
    #expect(!names.isEmpty)
    for name in names { #expect(CounterName.all.contains(name), "счётчик «\(name)» приложение не пишет") }
}

// MARK: - Факты из базы

@MainActor @Test func factsAreCollectedFromStore() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    let facts = try makeService(context).facts()

    // Сессия с неизвестным режимом пропущена; порядок — по времени конца.
    let known = try context.fetch(FetchDescriptor<SessionRecord>()).filter { ExerciseMode(rawValue: $0.mode) != nil }
    #expect(known.count < (try context.fetchCount(FetchDescriptor<SessionRecord>())))
    #expect(facts.exercises.count == known.count)
    #expect(facts.exercises.map(\.endedAt) == facts.exercises.map(\.endedAt).sorted())
    let check = try #require(facts.exercises.first { $0.exerciseKind == .check })
    #expect(check.lessonId == "ru.1.1" && check.mode == .course && check.language == .ru)
    #expect(check.chars == 89 && check.activeSeconds == 27.1 && check.accuracy == 0.978 && check.cpm == 197)
    #expect(check.maxErrorStreak == 1 && check.wrongKeystrokes == 2 && check.completed)
    #expect(check.logicalDay == "2026-10-23" && check.hintLevel == .full)
    let adaptive = try #require(facts.exercises.first { $0.chars == 241 })
    #expect(adaptive.hintLevel == .onError && adaptive.pinkyPresses == 31 && adaptive.pinkyErrors == 0)

    #expect(facts.days == ["2026-10-23": DayActivity(activeSeconds: 700, completedExercises: 3)])
    #expect(facts.abandonedByDay == ["2026-10-23": 1])
    #expect(facts.languagesByDay == ["2026-10-23": [.ru, .en]])
    #expect(facts.streakStatuses["2026-10-23"] == .full)
    #expect(facts.lessonPasses == ["ru.1.1": at("2026-10-23 21:42:30"), "ru.1.2": at("2026-10-24 02:34:32")])
    #expect(facts.lessonAttempts == ["ru.1.1": 2, "ru.1.2": 1])
    // Звёзды — только `LessonScoring.effectiveStars`: по истории проверок, а без неё — из базы.
    #expect(facts.starsByLesson["ru.1.1"] == 2)
    #expect(facts.starsByLesson["ru.1.2"] == 3)   // хранимые 2 (прежняя шкала) → ★★★
    #expect(facts.counters == [CounterName.capsLockPresses: 0])
    #expect(facts.courses[.ru] != nil && facts.courses[.en] != nil)
    #expect(facts.timeZone == msk)
    #expect(facts.now == at("2026-10-24 07:00"))
}

/// ★★★★★ — только за чистый урок: проверка на пятёрку, а «Слова» 93,4% — четыре звезды; после чистых «Слов» — пять.
/// Ачивки (`course.stars.*` — от четырёх звёзд) от этого не меняются, но звёзды идут тем же правилом, что на карте.
@MainActor @Test func starsOfLessonNeedCleanStepsForFifthStar() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let target = try #require(CourseCatalog.legacy(.ru)?.context(for: "ru.1.1")).targetCpm
    insertSession(context, ended: "2026-10-23 21:40:00", day: "2026-10-23", lessonId: "ru.1.1", kind: "words",
                  chars: 120, accuracy: 0.934, cpm: 100, wrong: 8)
    insertSession(context, ended: "2026-10-23 21:42:30", day: "2026-10-23", lessonId: "ru.1.1", kind: "check",
                  chars: 120, accuracy: 1, cpm: Double(target) * 2, wrong: 0)
    // Урок «ru.1.2»: проверка на пятёрку, шагов в истории нет — не мешает.
    insertSession(context, ended: "2026-10-23 21:50:00", day: "2026-10-23", lessonId: "ru.1.2", kind: "check",
                  chars: 120, accuracy: 1, cpm: Double(target) * 2, wrong: 0)
    for id in ["ru.1.1", "ru.1.2"] {
        let progress = LessonProgress(lessonId: id, language: "ru")
        progress.bestStars = 3
        progress.passedAt = at("2026-10-23 21:42:30")
        context.insert(progress)
    }
    try context.save()
    let before = try makeService(context).facts().starsByLesson
    #expect(before["ru.1.1"] == 4 && before["ru.1.2"] == 5)

    insertSession(context, ended: "2026-10-23 22:00:00", day: "2026-10-23", lessonId: "ru.1.1", kind: "words",
                  chars: 120, accuracy: 0.99, cpm: 100, wrong: 1)
    try context.save()
    #expect(try makeService(context).facts().starsByLesson["ru.1.1"] == 5)
}

/// Открытые буквы (§21): курс — до последнего засчитанного урока (дата — `passedAt`), адаптивный режим — только
/// при строке `AdaptiveState`; стартовые буквы — с конца первой завершённой адаптивной тренировки,
/// остальные — `AdaptiveUnlock.unlockedAt`.
@MainActor @Test func openLetterDatesCombineCourseAndAdaptive() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    let facts = try makeService(context).facts()
    let ru = try #require(facts.openLetterDates[.ru])
    let course = try #require(editionOneCourses[.ru])
    let lesson1 = Set(course.lessons[0].newCharacters.map { Character(String($0).lowercased()) })
    let lesson2 = Set(course.lessons[1].newCharacters.map { Character(String($0).lowercased()) })
        .subtracting(lesson1)
    let adaptiveStart = at("2026-10-24 02:42:16")
    for letter in lesson1 {
        #expect(ru[letter] == min(at("2026-10-23 21:42:30"), adaptiveStart), "\(letter)")
    }
    let startLetters = Set(Language.ru.adaptiveOrder.prefix(6))
    for letter in lesson2 {
        let expected = startLetters.contains(letter) ? min(at("2026-10-24 02:34:32"), adaptiveStart)
            : at("2026-10-24 02:34:32")
        #expect(ru[letter] == expected, "\(letter)")
    }
    for letter in startLetters where !lesson1.contains(letter) && !lesson2.contains(letter) {
        // Не первая (брошенная) адаптивная сессия, а первая завершённая.
        #expect(ru[letter] == adaptiveStart, "\(letter)")
    }
    let seventh = Language.ru.adaptiveOrder[6]
    // Седьмая и восьмая буквы адаптивного режима не входят в уроки 1–2: их дата — только из адаптивного режима.
    try #require(!lesson1.contains(seventh) && !lesson2.contains(seventh))
    #expect(ru[seventh] == adaptiveStart)
    #expect(ru[" "] == nil)
    // Восьмая буква адаптивного режима не открыта.
    let eighth = Language.ru.adaptiveOrder[7]
    try #require(!lesson1.contains(eighth) && !lesson2.contains(eighth))
    #expect(ru[eighth] == nil)
    // Английский: ни уроков, ни строки `AdaptiveState` — открытых букв нет.
    #expect(facts.openLetterDates[.en]?.isEmpty ?? true)
}

@Test func openLettersWithoutAdaptiveStateComeOnlyFromCourse() throws {
    let course = try CourseCatalog.load(.en)
    let passed = at("2026-10-20 10:00")
    let dates = AchievementService.openLetterDates(
        language: .en, course: course, passes: [course.lessons[1].id: passed], adaptiveCount: nil,
        unlocks: [:], firstAdaptive: at("2026-10-01 10:00"), now: at("2026-10-24 07:00"))
    let expected = Set((course.lessons[0].newCharacters + course.lessons[1].newCharacters)
        .map { Character(String($0).lowercased()) }).subtracting([" "])
    #expect(Set(dates.keys) == expected)
    #expect(dates.values.allSatisfy { $0 == passed })
}

@Test func adaptiveLettersWithoutDatesFallBackToNow() {
    let now = at("2026-10-24 07:00")
    let order = Language.en.adaptiveOrder
    // Строка `AdaptiveState` есть, адаптивных сессий в истории нет; восьмая буква открыта без `AdaptiveUnlock`.
    let dates = AchievementService.openLetterDates(
        language: .en, course: nil, passes: [:], adaptiveCount: 9, unlocks: [order[8]: at("2026-10-22 10:00")],
        firstAdaptive: nil, now: now)
    #expect(Set(dates.keys) == Set(order.prefix(9)))
    for letter in order.prefix(8) { #expect(dates[letter] == now) }
    #expect(dates[order[8]] == at("2026-10-22 10:00"))
}

// MARK: - Два издания курса (решение 17)

/// По умолчанию служба знает оба издания: текущий курс (издание 2) и архив (издание 1).
@MainActor @Test func serviceUsesCurrentAndLegacyCourses() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let service = makeService(container.mainContext)
    #expect(service.courses[.ru]?.edition == 2 && service.courses[.en]?.edition == 2)
    #expect(service.legacyCourses[.ru]?.edition == 1 && service.legacyCourses[.en]?.edition == 1)
    let facts = try service.facts()
    #expect(facts.legacyCourses[.ru]?.lessons.first?.id == "ru.1.1")
}

/// Обновление на издание 2: прежние ачивки и строки `LessonProgress` издания 1 остаются как были (даты, просмотр),
/// а прежние уроки (этап не закрыт) не дают ни «Курс пройден», ни «Первый этап».
@MainActor @Test func launchAfterNewCourseKeepsEarnedAndGrantsNothingWrong() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    context.insert(AchievementRecord(achievementId: "course.first_lesson", unlockedAt: at("2026-10-23 21:42:30"), seen: true))
    context.insert(AchievementRecord(achievementId: "letters.ru.alphabet", unlockedAt: at("2026-10-20 10:00"), seen: false))
    try context.save()
    let before = try records(context).map { ($0.achievementId, $0.unlockedAt, $0.seen) }
    let progressBefore = try context.fetch(FetchDescriptor<LessonProgress>()).map { ($0.lessonId, $0.passedAt, $0.bestStars) }
        .sorted { $0.0 < $1.0 }

    let result = try makeService(context).check(reason: .launch)
    #expect(!result.isBackfill)
    let after = try records(context)
    for (id, date, seen) in before {
        let record = after.first { $0.achievementId == id }
        #expect(record?.unlockedAt == date && record?.seen == seen, "\(id)")
    }
    let ids = Set(after.map(\.achievementId))
    #expect(!ids.contains("course.ru") && !ids.contains("course.first_stage") && !ids.contains("course.polyglot"))
    let progressAfter = try context.fetch(FetchDescriptor<LessonProgress>()).map { ($0.lessonId, $0.passedAt, $0.bestStars) }
        .sorted { $0.0 < $1.0 }
    #expect(progressAfter.map(\.0) == progressBefore.map(\.0))
    #expect(progressAfter.map(\.1) == progressBefore.map(\.1) && progressAfter.map(\.2) == progressBefore.map(\.2))
}

/// Открытые буквы — объединение изданий: засчитан «ru.4.check» издания 1 — весь алфавит (и «э») открыт с датой
/// зачёта, хотя прогресса издания 2 нет.
@MainActor @Test func openLetterDatesKeepEditionOneLetters() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let passed = LessonProgress(lessonId: "ru.4.check", language: "ru")
    passed.passedAt = at("2026-10-20 10:00")
    context.insert(passed)
    try context.save()
    let facts = try makeService(context).facts()
    let ru = try #require(facts.openLetterDates[.ru])
    #expect(ru["э"] == at("2026-10-20 10:00"))
    #expect(Language.ru.letters.allSatisfy { ru[$0] == at("2026-10-20 10:00") })
    #expect(AchievementEngine.evaluate(facts).contains { $0.id == "letters.ru.alphabet" })
}

/// Звёзды урока издания 2 — по цели урока (`Course.targetCpm(for:)`): у проверки этапа 1 это «до» (80), а не «от» (60);
/// 80 зн/мин без ошибок — ★★★ (при цели 60 было бы ★★★★). Факты несут номер шага.
@MainActor @Test func editionTwoLessonStarsUseLessonTarget() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let course = try CourseCatalog.load(.ru)
    let check = try #require(course.stages[0].checkLesson)
    try #require(course.targetCpm(for: check.id) == 80 && course.stages[0].targetCpm == 60)
    insertSession(context, ended: "2026-10-25 10:00", day: "2026-10-25", lessonId: check.id, kind: "check",
                  chars: 200, accuracy: 1, cpm: 80, wrong: 0, stepIndex: 2)
    let progress = LessonProgress(lessonId: check.id, language: "ru")
    progress.bestStars = 3
    progress.passedAt = at("2026-10-25 10:00")
    context.insert(progress)
    try context.save()
    let facts = try makeService(context, now: at("2026-10-25 12:00")).facts()
    #expect(facts.starsByLesson[check.id] == 3)
    #expect(facts.exercises.first?.stepIndex == 2)
}

// MARK: - Выдача

/// Первый запуск версии с ачивками: всё заработанное выдаётся с датами из истории, помечается просмотренным,
/// и это «задним числом» (один тост-сводка). Повторная проверка ничего не добавляет.
@MainActor @Test func firstLaunchBackfillsHistoryAsSeen() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    let service = makeService(context)
    let result = try service.check(reason: .launch)
    #expect(result.isBackfill)
    let ids = result.new.map(\.id)
    #expect(ids.contains("course.first_lesson"))
    #expect(ids.contains("special.night_owl"))
    #expect(ids.contains("special.steel_pinkies"))
    let stored = try records(context)
    #expect(stored.map(\.achievementId) == ids.sorted())
    #expect(stored.allSatisfy { $0.seen })
    #expect(stored.first { $0.achievementId == "course.first_lesson" }?.unlockedAt == at("2026-10-23 21:42:30"))
    #expect(stored.first { $0.achievementId == "special.night_owl" }?.unlockedAt == at("2026-10-24 02:42:16"))
    #expect(!context.hasChanges)

    let again = try service.check(reason: .launch)
    #expect(again.new.isEmpty && !again.isBackfill)
    #expect(try records(context).count == stored.count)
}

/// После сохранения новые ачивки не просмотрены; дата счётчика — момент проверки.
@MainActor @Test func afterSaveAddsOnlyNewUnseenAchievements() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    _ = try makeService(context).check(reason: .launch)
    let before = try records(context).count

    let caps = try #require(try context.fetch(FetchDescriptor<CounterRecord>()).first)
    caps.value = 1
    try context.save()
    let now = at("2026-10-24 08:15")
    let result = try makeService(context, now: now).check(reason: .afterSave)
    #expect(!result.isBackfill)
    #expect(result.new.map(\.id) == ["fun.oy_vsyo"])
    let record = try #require(try records(context).first { $0.achievementId == "fun.oy_vsyo" })
    #expect(!record.seen && record.unlockedAt == now)
    #expect(try records(context).count == before + 1)
}

/// Новый пользователь: первая ачивка после упражнения — обычная, не «задним числом».
@MainActor @Test func afterSaveWithoutRecordsIsNotBackfill() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    insertSession(context, ended: "2026-10-24 02:10:00", day: "2026-10-23", mode: "practice")
    try context.save()
    let result = try makeService(context).check(reason: .afterSave)
    #expect(!result.isBackfill)
    #expect(result.new.map(\.id) == ["special.night_owl"])
    #expect(try records(context).allSatisfy { !$0.seen })
}

/// Нечего выдавать при пустой истории: «задним числом» тоже ничего, базу не трогаем.
@MainActor @Test func emptyHistoryEarnsNothing() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let result = try makeService(context).check(reason: .launch)
    #expect(result.new.isEmpty)
    #expect(try records(context).isEmpty)
}

/// Все новые записи — одна транзакция: ошибка сохранения не оставляет ни одной, проверку можно повторить.
@MainActor @Test func failedCheckLeavesNothingAndCanBeRetried() throws {
    struct Boom: Error {}
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    #expect(throws: Boom.self) { _ = try makeService(context, beforeSave: { throw Boom() }).check(reason: .launch) }
    #expect(try records(context).isEmpty)
    #expect(!context.hasChanges)
    let retry = try makeService(context).check(reason: .launch)
    #expect(retry.isBackfill && !retry.new.isEmpty)
}

/// Записи с id, которых нет в каталоге (из более новой версии), не мешают и не трогаются.
@MainActor @Test func unknownStoredAchievementsAreKept() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(AchievementRecord(achievementId: "future.thing", unlockedAt: at("2026-10-01 10:00"), seen: true))
    try populateHistory(context)
    let result = try makeService(context).check(reason: .launch)
    #expect(!result.isBackfill)   // записи уже были: это не первый запуск
    #expect(try records(context).contains { $0.achievementId == "future.thing" })
}

/// Архив поколения 2 (без раздела ачивок) загружается, ачивки затем выдаются проверкой заново.
@MainActor @Test func generationTwoArchiveImportsAndAchievementsAreReissued() throws {
    let data = Data(#"""
        { "format": "tenfingers-progress", "version": 1, "schemaGeneration": 2,
          "sessions": [{ "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "mode": "course", "language": "ru",
            "lessonId": "ru.1.1", "exerciseKind": "check", "startedAt": 783000000, "endedAt": 783000060,
            "logicalDay": "2025-10-23", "activeSeconds": 60, "chars": 90, "errorCount": 1, "cpm": 90,
            "accuracy": 0.99, "completed": true, "hintLevel": "full", "maxErrorStreak": 1, "wrongKeystrokes": 1 }],
          "lessonProgress": [{ "lessonId": "ru.1.1", "language": "ru", "attempts": 1, "bestStars": 1,
            "passedAt": 783000060 }] }
        """#.utf8)
    let archive = try ProgressArchive.decode(data)
    #expect(archive.achievements.isEmpty)

    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(AchievementRecord(achievementId: "streak.3", unlockedAt: at("2026-10-01 10:00"), seen: true))
    try context.save()
    try ProgressArchive.replaceAll(with: archive, context: context)
    #expect(try records(context).isEmpty)

    let result = try makeService(context).check(reason: .launch)
    #expect(result.isBackfill)
    #expect(result.new.map(\.id).contains("course.first_lesson"))
    let record = try #require(try records(context).first { $0.achievementId == "course.first_lesson" })
    #expect(record.unlockedAt == Date(timeIntervalSinceReferenceDate: 783_000_060))
}

// MARK: - Тосты и «Взрослый юмор»

@MainActor @Test func adultAchievementsAreHiddenWhenAdultHumorIsOff() throws {
    let adult = try #require(AchievementCatalog.all.first { $0.adult })
    let plain = try #require(AchievementCatalog.all.first { !$0.adult })
    #expect(AchievementVisibility.visible([adult, plain], adultHumor: true).map(\.id) == [adult.id, plain.id])
    #expect(AchievementVisibility.visible([adult, plain], adultHumor: false).map(\.id) == [plain.id])
}

@Test func adultHumorIsOnByDefault() {
    let (defaults, name) = makeTestDefaults("AchievementServiceTests-")
    defer { removeTestDefaults(name) }
    #expect(StoredSettings.adultHumor(defaults))
    defaults.set(false, forKey: SettingsKey.adultHumor)
    #expect(!StoredSettings.adultHumor(defaults))
    #expect(ArchivedSettings.entries.contains { $0.key == SettingsKey.adultHumor })
}

@Test func achievementSoundIsActive() {
    #expect(SoundSettings.activeEvents.contains(.achievement))
}

@Test func achievementsHaveTheirSidebarItem() {
    #expect(SidebarItem.achievements.icon == "trophy")
    #expect(SidebarItem.allCases.firstIndex(of: .achievements) == SidebarItem.allCases.firstIndex(of: .analytics)! + 1)
}

// MARK: - Координатор: проверка после сохранения

@MainActor private final class Heard {
    var sounds: [SoundEvent] = []
    var delayed: [(Duration, @MainActor () -> Void)] = []
}

private let spec = ExerciseSpec(id: 0, kind: .words, title: "Слова", text: "ао")

@MainActor private func finishExercise(_ coordinator: ExerciseCoordinator) {
    let session = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { s, r in
        coordinator.recordFinish(s, r)
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
}

@MainActor private func makeCoordinator(goalSeconds: Double) throws -> (ExerciseCoordinator, ModelContainer, Heard) {
    let container = try ModelStore.makeContainer(inMemory: true)
    let heard = Heard()
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    let coordinator = ExerciseCoordinator(recorder: recorder, playSound: { heard.sounds.append($0) },
                                          goalSeconds: { goalSeconds },
                                          afterDelay: { delay, action in heard.delayed.append((delay, action)) })
    // Только «ОЙ ВСЁ»: остальные условия зависят от времени запуска теста.
    let oops = AchievementCatalog.all.filter { $0.id == "fun.oy_vsyo" }
    coordinator.achievements = AchievementService(recorder: recorder, goalSeconds: { goalSeconds }, timeZone: msk,
                                                  now: { Date() }, catalog: oops)
    return (coordinator, container, heard)
}

@MainActor @Test func savedExerciseAnnouncesNewAchievementsWithSound() throws {
    let (coordinator, container, heard) = try makeCoordinator(goalSeconds: 1e9)
    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 1
    container.mainContext.insert(caps)
    try container.mainContext.save()

    finishExercise(coordinator)
    #expect(coordinator.newAchievements.map(\.id) == ["fun.oy_vsyo"])
    // Звук ачивки — после звука результата, с паузой.
    #expect(heard.delayed.map(\.0) == [ExerciseCoordinator.streakDelay])
    #expect(!heard.sounds.contains(.achievement))
    heard.delayed.forEach { $0.1() }
    #expect(heard.sounds.last == .achievement)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<AchievementRecord>()) == 1)

    // Следующее сохранение: ничего нового — ни карточек, ни второго звука.
    finishExercise(coordinator)
    #expect(coordinator.newAchievements.isEmpty)
    #expect(heard.delayed.count == 1)
}

/// Упражнение начато, но не закончено: одно нажатие из двух.
@MainActor private func startUnfinishedExercise(_ coordinator: ExerciseCoordinator) {
    let session = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { s, r in
        coordinator.recordFinish(s, r)
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
}

/// «Выйти» без итога: ачивка записана и попадает в копилку, но звука нет — карточку показать негде.
/// С итогом после выхода (`announce: true`, «Слабые места») звук есть.
@MainActor @Test func exitWithoutSummaryRecordsAchievementsSilently() throws {
    let (coordinator, container, heard) = try makeCoordinator(goalSeconds: 1e9)
    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 1
    container.mainContext.insert(caps)
    try container.mainContext.save()

    startUnfinishedExercise(coordinator)
    #expect(coordinator.exit())
    #expect(try container.mainContext.fetchCount(FetchDescriptor<AchievementRecord>()) == 1)
    #expect(coordinator.runAchievements.map(\.id) == ["fun.oy_vsyo"])
    #expect(heard.delayed.isEmpty)
}

@MainActor @Test func exitIntoSummaryAnnouncesAchievementsWithSound() throws {
    let (coordinator, container, heard) = try makeCoordinator(goalSeconds: 1e9)
    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 1
    container.mainContext.insert(caps)
    try container.mainContext.save()

    startUnfinishedExercise(coordinator)
    #expect(coordinator.exit(announce: true))
    #expect(heard.delayed.map(\.0) == [ExerciseCoordinator.streakDelay])
}

/// «Шаг заново» (`recordAbandonIfNeeded(announce: true)`): у брошенной попытки карточки не будет,
/// поэтому и звука ачивки нет.
@MainActor @Test func restartRecordsAchievementsWithoutSound() throws {
    let (coordinator, container, heard) = try makeCoordinator(goalSeconds: 1e9)
    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 1
    container.mainContext.insert(caps)
    try container.mainContext.save()

    startUnfinishedExercise(coordinator)
    coordinator.recordAbandonIfNeeded(announce: true)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<AchievementRecord>()) == 1)
    #expect(heard.delayed.isEmpty)
    #expect(!heard.sounds.contains(.achievement))
}

/// Ачивки всего урока копятся от `resetRunAchievements()` до следующего сброса: итог урока показывает и ачивки
/// промежуточных шагов, а итог шага — только свои (`newAchievements`).
@MainActor @Test func runAchievementsAccumulateAcrossSavesUntilReset() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    let coordinator = ExerciseCoordinator(recorder: recorder, playSound: { _ in }, goalSeconds: { 1e9 },
                                          afterDelay: { _, _ in })
    let catalog = AchievementCatalog.all.filter { ["fun.oy_vsyo", "fun.ghbdtn"].contains($0.id) }
    coordinator.achievements = AchievementService(recorder: recorder, goalSeconds: { 1e9 }, timeZone: msk,
                                                  now: { Date() }, catalog: catalog)
    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 1
    container.mainContext.insert(caps)
    try container.mainContext.save()

    coordinator.resetRunAchievements()
    finishExercise(coordinator)
    #expect(coordinator.runAchievements.map(\.id) == ["fun.oy_vsyo"])

    let layout = CounterRecord(name: CounterName.wrongLayoutStarts)
    layout.value = 10
    container.mainContext.insert(layout)
    try container.mainContext.save()
    finishExercise(coordinator)
    #expect(coordinator.newAchievements.map(\.id) == ["fun.ghbdtn"])
    #expect(coordinator.runAchievements.map(\.id) == ["fun.oy_vsyo", "fun.ghbdtn"])

    finishExercise(coordinator)
    #expect(coordinator.newAchievements.isEmpty)
    #expect(coordinator.runAchievements.count == 2)
    coordinator.resetRunAchievements()
    #expect(coordinator.runAchievements.isEmpty)
}

/// День стал полным в том же сохранении: «Полный огонь» и звук серии первыми, звук ачивки — после них.
@MainActor @Test func achievementSoundFollowsStreakSound() throws {
    let (coordinator, container, heard) = try makeCoordinator(goalSeconds: 0)
    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 1
    container.mainContext.insert(caps)
    try container.mainContext.save()

    finishExercise(coordinator)
    #expect(heard.delayed.map(\.0) == [ExerciseCoordinator.streakDelay, ExerciseCoordinator.streakDelay * 2])
    heard.delayed.forEach { $0.1() }
    #expect(Array(heard.sounds.suffix(2)) == [.streak, .achievement])
}

/// Нет нового — нет ни карточек, ни звука.
@MainActor @Test func nothingNewMeansNoAnnouncement() throws {
    let (coordinator, container, heard) = try makeCoordinator(goalSeconds: 1e9)
    finishExercise(coordinator)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 1)
    #expect(coordinator.newAchievements.isEmpty)
    #expect(heard.delayed.isEmpty)
}

// MARK: - Проверка на копии настоящей базы

/// `TENFINGERS_PROBE_ACHIEVEMENTS=<папка с TenFingers.store> swift test --filter probeAchievementsOnStoreCopy`:
/// папка копируется во временную, проверка выдачи идёт на копии; печатает, что получит пользователь.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["TENFINGERS_PROBE_ACHIEVEMENTS"] != nil))
func probeAchievementsOnStoreCopy() throws {
    let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TENFINGERS_PROBE_ACHIEVEMENTS"]))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersProbe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
        try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: directory.appendingPathComponent(name))
    }
    let container = try ModelStore.makeContainer(at: directory.appendingPathComponent("TenFingers.store"))
    let context = container.mainContext
    let service = AchievementService(recorder: ResultRecorder(context: context, dayStartHour: StoredSettings.dayStartHour()),
                                     goalSeconds: { StoredSettings.dailyGoalSeconds() })
    let sessions = try context.fetchCount(FetchDescriptor<SessionRecord>())
    let result = try service.check(reason: .launch)
    let dates = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AchievementRecord>())
        .map { ($0.achievementId, $0.unlockedAt) })
    print("probe: sessions=\(sessions) backfill=\(result.isBackfill) earned=\(result.new.count)")
    for achievement in result.new {
        print("probe: \(achievement.id) \(dates[achievement.id].map { "\($0)" } ?? "?") adult=\(achievement.adult)")
    }
    #expect(sessions > 0)
}

// MARK: - Ревью: скрытые ачивки, кэш фактов, отдельные записи, замена прогресса

/// Ачивка с `adult` при выключенном «Взрослом юморе»: запись создаётся, но без звука (и без карточки).
@MainActor @Test func hiddenAdultAchievementIsRecordedSilently() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let heard = Heard()
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    let coordinator = ExerciseCoordinator(recorder: recorder, playSound: { heard.sounds.append($0) },
                                          goalSeconds: { 1e9 },
                                          afterDelay: { delay, action in heard.delayed.append((delay, action)) })
    let adult = try #require(AchievementCatalog.all.first { $0.id == "letters.ru.b_word" })
    #expect(adult.adult)
    coordinator.achievements = AchievementService(recorder: recorder, goalSeconds: { 1e9 }, timeZone: msk,
                                                  now: { Date() }, catalog: [adult])
    coordinator.adultHumor = { false }
    // Весь алфавит открыт в адаптивном режиме — «бля» открыто.
    container.mainContext.insert(AdaptiveState(language: "ru", unlockedCount: Language.ru.adaptiveOrder.count))
    try container.mainContext.save()

    finishExercise(coordinator)
    #expect(try container.mainContext.fetch(FetchDescriptor<AchievementRecord>()).map(\.achievementId) == [adult.id])
    #expect(heard.delayed.isEmpty)
    #expect(!heard.sounds.contains(.achievement))
}

/// Запись вне упражнения без новой сессии (сброс позиции своего текста) ачивки не проверяет.
@MainActor @Test func standaloneCommitWithoutSessionSkipsAchievementCheck() throws {
    let (coordinator, container, heard) = try makeCoordinator(goalSeconds: 1e9)
    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 1
    container.mainContext.insert(caps)
    try container.mainContext.save()

    #expect(coordinator.commitStandalone { recorder in try recorder.increment("unrelated") })
    #expect(try container.mainContext.fetchCount(FetchDescriptor<AchievementRecord>()) == 0)
    #expect(heard.delayed.isEmpty)
    finishExercise(coordinator)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<AchievementRecord>()) == 1)
}

/// Кэш фактов строится один раз и дальше дополняется новыми сессиями; результат совпадает с полным проходом.
@MainActor @Test func factsCacheAppendsNewSessions() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    let cache = AchievementFactsCache()
    var recorder = ResultRecorder(context: context, dayStartHour: 4)
    recorder.beforeSave = nil
    let service = AchievementService(recorder: recorder, goalSeconds: { 600 }, timeZone: msk,
                                     now: { at("2026-10-24 07:00") }, cache: cache)
    _ = try service.check(reason: .launch)
    #expect(cache.rebuilds == 1)

    insertSession(context, ended: "2026-10-24 05:10:00", day: "2026-10-24", mode: "practice", chars: 400, cpm: 90)
    try context.save()
    let cached = try service.facts()
    #expect(cache.rebuilds == 1)
    let fresh = try makeService(context).facts()
    #expect(cached.exercises == fresh.exercises)
    #expect(cached.exercises.last?.chars == 400)
    // Новое упражнение даёт новые ачивки («Без кофе» — с 5 до 6 утра; 5:10 — ещё и утро, `time.morning`, 6d).
    let result = try service.check(reason: .afterSave)
    #expect(result.new.map(\.id) == ["time.morning", "fun.no_coffee"])
    #expect(cache.rebuilds == 1)

    // Замена прогресса: кэш сбрасывается и строится заново.
    let archive = try ProgressArchive.decode(Data(#"{ "format": "tenfingers-progress", "version": 1, "schemaGeneration": 2 }"#.utf8))
    try ProgressArchive.replaceAll(with: archive, context: context)
    cache.invalidate()
    #expect(try service.facts().exercises.isEmpty)
    #expect(cache.rebuilds == 2)
}

/// Сессия «из будущего» (сбитые часы) не мешает дополнять кэш: новые сессии догружаются без полного прохода.
@MainActor @Test func factsCacheAppendsDespiteASessionFromTheFuture() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    insertSession(context, ended: "2026-12-31 10:00:00", day: "2026-12-31", mode: "practice", chars: 300, cpm: 80)
    try context.save()
    let cache = AchievementFactsCache(now: { at("2026-10-24 07:00") })
    let service = AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4), goalSeconds: { 600 },
                                     timeZone: msk, now: { at("2026-10-24 07:00") }, cache: cache)
    _ = try service.facts()
    insertSession(context, ended: "2026-10-24 07:30:00", day: "2026-10-24", mode: "practice", chars: 400, cpm: 90)
    try context.save()
    #expect(try service.facts().exercises.contains { $0.chars == 400 })
    #expect(cache.rebuilds == 1)
}

/// Если сессий в базе стало не столько, сколько известно кэшу (другая база, загрузка без сброса), он строится заново.
@MainActor @Test func factsCacheRebuildsWhenStoreChangesUnderIt() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    let cache = AchievementFactsCache()
    let service = AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4), goalSeconds: { 600 },
                                     timeZone: msk, now: { at("2026-10-24 07:00") }, cache: cache)
    let before = try service.facts().exercises.count
    for record in try context.fetch(FetchDescriptor<SessionRecord>()) where record.mode == "adaptive" {
        context.delete(record)
    }
    try context.save()
    let after = try service.facts().exercises
    #expect(after.count < before)
    #expect(after.allSatisfy { $0.mode != .adaptive })
    #expect(cache.rebuilds == 2)
}

/// Большая история (20 000 сессий): факты строятся без квадратичного роста; длительность — в журнал теста.
@MainActor @Test func factsForLargeHistory() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let start = at("2024-01-01 10:00")
    let total = 20_000
    // Статистика пальцев у каждой сессии (как после 1.1.0); большой палец ошибается — «Десять из десяти» не выдаётся,
    // и окно по пальцам проходит всю историю при каждой проверке.
    let fingerPresses = FingerCounts.data(Dictionary(uniqueKeysWithValues: Finger.allCases.map { ($0, 20) }))
    let fingerErrors = FingerCounts.data(Dictionary(uniqueKeysWithValues: Finger.allCases.map { ($0, $0 == .thumb ? 5 : 0) }))
    for index in 0..<total {
        let end = start.addingTimeInterval(Double(index) * 3_600)
        context.insert(SessionRecord(
            mode: index % 3 == 0 ? "adaptive" : "course", language: index % 2 == 0 ? "ru" : "en",
            lessonId: index % 3 == 0 ? nil : "ru.1.1", startedAt: end.addingTimeInterval(-60), endedAt: end,
            logicalDay: LogicalDay.key(for: end, dayStartHour: 4), activeSeconds: 60, chars: 300, errorCount: 2,
            cpm: 200, accuracy: 0.99, completed: index % 7 != 0, hintLevel: "full", maxErrorStreak: 1,
            wrongKeystrokes: 2, exerciseKind: index % 3 == 0 ? nil : "check", fingerPresses: fingerPresses,
            fingerErrors: fingerErrors, yoPresses: 0))
    }
    try context.save()
    let cache = AchievementFactsCache()
    let service = AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4), goalSeconds: { 600 },
                                     timeZone: msk, now: { start.addingTimeInterval(Double(total) * 3_600) },
                                     cache: cache)
    let clock = ContinuousClock()
    var facts: AchievementFacts?
    let cold = try clock.measure { facts = try service.facts() }
    #expect(facts?.exercises.count == total)
    var outcome: AchievementService.Outcome?
    let launch = try clock.measure { outcome = try service.check(reason: .launch) }
    #expect(outcome?.isBackfill == true)
    insertSession(context, ended: "2026-10-24 05:10:00", day: "2026-10-24", mode: "practice")
    try context.save()
    let warm = try clock.measure { _ = try service.check(reason: .afterSave) }
    #expect(cache.rebuilds == 1)
    print("benchmark: \(total) sessions — facts cold \(cold), launch check \(launch), check after save \(warm)")
}

/// Загрузка прогресса сообщает о замене (`.progressReplaced`); по ней кэш сбрасывается и ачивки выдаются заново —
/// одной сводкой с кнопкой.
@MainActor @Test func progressReplacementReissuesAchievementsWithSummary() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateHistory(context)
    let (defaults, name) = makeTestDefaults("AchievementServiceTests-")
    defer { removeTestDefaults(name) }
    let backups = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersBackups-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: backups) }
    let notifications = NotificationCenter()
    let replaced = PostCount()
    let token = notifications.addObserver(forName: .progressReplaced, object: nil, queue: nil) { _ in replaced.add() }
    defer { notifications.removeObserver(token) }

    let cache = AchievementFactsCache()
    let service = AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4), goalSeconds: { 600 },
                                     timeZone: msk, now: { at("2026-10-24 07:00") }, cache: cache)
    _ = try service.check(reason: .launch)
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: context, defaults: defaults))
    var stripped = archive
    stripped.achievements = []   // как архив поколения 2
    var importer = ProgressImporter(context: context, defaults: defaults, backupDirectory: backups)
    importer.notifications = notifications
    _ = try importer.importArchive(stripped)
    #expect(replaced.value == 1)
    #expect(try records(context).isEmpty)

    let clock = ManualClock()
    let toasts = ToastCenter(timer: clock.timer)
    var opened = 0
    let outcome = AchievementAnnouncer.progressReplaced(service: service, toasts: toasts, adultHumor: true) {
        opened += 1
    }
    #expect(cache.rebuilds == 2)
    #expect(outcome.isBackfill && !outcome.new.isEmpty)
    let toast = try #require(toasts.current)
    #expect(toast.action != nil)
    #expect(toast.message.contains("\(outcome.new.count)"))
    toasts.perform(toast)
    #expect(opened == 1)
}

/// Счётчик уведомлений (наблюдатель вызывается синхронно в том же потоке, что и `post`).
private final class PostCount: @unchecked Sendable {
    private(set) var value = 0
    func add() { value += 1 }
}

/// Таймер тостов, который ничего не ждёт.
@MainActor private final class ManualClock {
    var timer: ToastTimer { { _, _ in {} } }
}

// MARK: - Сводка: склонение

private func localization(_ language: String) -> Bundle {
    Bundle(url: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Localization/\(language).lproj"))!
}

@Test func backfillSummaryIsInflected() {
    let ru = Locale(identifier: "ru")
    let expected = [1: "Получена 1 ачивка за прошлые занятия", 2: "Получено 2 ачивки за прошлые занятия",
                    5: "Получено 5 ачивок за прошлые занятия", 21: "Получена 21 ачивка за прошлые занятия"]
    for (count, text) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(Formatting.backfillSummary(count, bundle: localization("ru"), locale: ru) == text, "ru \(count)")
        // Без переводов (рендер в тестах) — те же русские формы.
        #expect(Formatting.backfillSummary(count, bundle: .main, locale: ru) == text, "fallback \(count)")
    }
    let en = Locale(identifier: "en")
    #expect(Formatting.backfillSummary(1, bundle: localization("en"), locale: en) == "1 achievement earned for past practice")
    #expect(Formatting.backfillSummary(4, bundle: localization("en"), locale: en) == "4 achievements earned for past practice")
}

// MARK: - Фаза 5: новые ачивки по истории

/// Новые ачивки фазы 5 (21).
private let phase5Ids: Set<String> = [
    "streak.fire_month", "streak.insurance", "speed.growth.150", "speed.growth.200", "accuracy.all_fingers",
    "volume.exercises.100", "volume.exercises.500", "volume.exercises.1000", "volume.books.5", "volume.books.25",
    "special.weak_spot", "special.weak_spot.10", "special.own_words", "fun.pi", "fun.answer42", "fun.yo_master",
    "fun.learning_from_mistakes", "fun.cinderella", "fun.friday_night", "fun.weekend_warrior", "fun.almost",
]

/// База как у пользователя до 1.1.0: сессии без статистики пальцев и «ё», но «ё» в `KeyStat` (160 нажатий,
/// 20 ошибок); пять отрывков из книг, свой текст, «Слабые места».
@MainActor private func populatePhaseFiveHistory(_ context: ModelContext) throws {
    for (index, day) in ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"].enumerated() {
        insertSession(context, ended: "\(day) 12:00:00", day: day, mode: "practice", chars: 400, seconds: 120,
                      source: "library:book\(index)")
    }
    insertSession(context, ended: "2026-10-23 13:00:00", day: "2026-10-23", mode: "practice", source: "custom")
    insertSession(context, ended: "2026-10-23 14:00:00", day: "2026-10-23", mode: "weak", accuracy: 0.985,
                  source: "weak")
    let yo = KeyStat(language: "ru", character: "ё")
    yo.presses = 150
    yo.errors = 15
    context.insert(yo)
    let capital = KeyStat(language: "ru", character: "Ё")
    capital.presses = 10
    capital.errors = 5
    context.insert(capital)
    let english = KeyStat(language: "en", character: "e")
    english.presses = 500
    context.insert(english)
    try context.save()
}

@MainActor @Test func factsCarrySourceFingerStatsAndYo() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populatePhaseFiveHistory(context)
    insertSession(context, ended: "2026-10-24 05:00:00", day: "2026-10-24", mode: "practice",
                  fingerPresses: [.thumb: 30, .leftPinky: 4], fingerErrors: [.thumb: 0, .leftPinky: 1], yo: 2)
    try context.save()
    let facts = try makeService(context).facts()
    #expect(facts.yoKeyStatCorrect == 135 + 5)
    let last = try #require(facts.exercises.last)
    #expect(last.fingerPresses == [.thumb: 30, .leftPinky: 4])
    #expect(last.fingerErrors == [.thumb: 0, .leftPinky: 1])
    #expect(last.yoCorrect == 2)
    let first = try #require(facts.exercises.first)
    #expect(first.source == "library:book0")
    #expect(first.fingerPresses == nil && first.fingerErrors == nil && first.yoCorrect == nil)
}

/// После обновления на базе с прежними ачивками новые выдаются с датами из истории; «ё» — по `KeyStat` (момент
/// проверки); «Десять из десяти» без статистики пальцев не выдаётся. Это не «задним числом»: новые не просмотрены.
@MainActor @Test func updateGrantsPhaseFiveAchievementsFromHistory() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populatePhaseFiveHistory(context)
    context.insert(AchievementRecord(achievementId: "course.first_lesson", unlockedAt: at("2026-10-01 10:00"),
                                     seen: true))
    try context.save()
    let now = at("2026-10-24 07:00")
    let outcome = try makeService(context, now: now).check(reason: .launch)
    #expect(!outcome.isBackfill)
    let stored = Dictionary(uniqueKeysWithValues: try records(context).map { ($0.achievementId, $0) })
    let new = Set(outcome.new.map(\.id)).intersection(phase5Ids)
    #expect(new == ["fun.yo_master", "volume.books.5", "special.own_words", "special.weak_spot"])
    #expect(stored["fun.yo_master"]?.unlockedAt == now)
    #expect(stored["volume.books.5"]?.unlockedAt == at("2026-10-23 12:00"))
    #expect(stored["special.own_words"]?.unlockedAt == at("2026-10-23 13:00"))
    #expect(stored["special.weak_spot"]?.unlockedAt == at("2026-10-23 14:00"))
    #expect(stored["accuracy.all_fingers"] == nil)
    #expect(outcome.new.count >= 2)
    #expect(outcome.new.allSatisfy { stored[$0.id]?.seen == false })
    #expect(stored["course.first_lesson"]?.seen == true)
}

/// Проверка при запуске после обновления выдала несколько видимых ачивок — одна сводка, а не очередь тостов.
@MainActor @Test func launchCheckAfterUpdateShowsOneSummary() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populatePhaseFiveHistory(context)
    context.insert(AchievementRecord(achievementId: "course.first_lesson", unlockedAt: at("2026-10-01 10:00"),
                                     seen: true))
    try context.save()
    let toasts = ToastCenter(timer: ManualClock().timer)
    var opened = 0
    let outcome = AchievementAnnouncer.launchCheck(service: makeService(context), toasts: toasts, adultHumor: true) {
        opened += 1
    }
    #expect(!outcome.isBackfill && outcome.new.count >= 2)
    // Таблица выдач пуста — первый запуск 6d: в сводке и новые ачивки, и выдачи (первая выдача новой — не дважды).
    #expect(outcome.isGrantBackfill && !outcome.grants.isEmpty)
    let toast = try #require(toasts.current)
    #expect(toast.message == Formatting.backfillSummary(summaryCount(outcome)))
    #expect(toast.action != nil)
    toasts.dismiss()
    #expect(toasts.current == nil, "после сводки в очереди ничего нет")
    toasts.perform(toast)
    #expect(opened == 1)
    #expect(try records(context).filter { !$0.seen }.count == outcome.new.count)
}

/// Одна новая ачивка при запуске — обычный тост с её названием.
@MainActor @Test func launchCheckWithOneNewAchievementShowsItsToast() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populatePhaseFiveHistory(context)
    let others = AchievementCatalog.all.filter { $0.id != "special.own_words" }
    for achievement in others {
        context.insert(AchievementRecord(achievementId: achievement.id, unlockedAt: at("2026-10-01 10:00"), seen: true))
    }
    // Выдачи уже записаны (не первый запуск 6d).
    for item in AchievementEngine.occurrences(try makeService(context).facts()) {
        context.insert(AchievementGrant(achievementId: item.id, occurrence: item.key, grantedAt: item.date,
                                        value: item.value, seen: true))
    }
    try context.save()
    let toasts = ToastCenter(timer: ManualClock().timer)
    let outcome = AchievementAnnouncer.launchCheck(service: makeService(context), toasts: toasts, adultHumor: true) {}
    #expect(outcome.new.map(\.id) == ["special.own_words"] && outcome.grants.isEmpty)
    let toast = try #require(toasts.current)
    #expect(toast.icon == "text.quote")
    #expect(toast.message.contains(outcome.new[0].title))
}

// MARK: - Повторные получения (6d)

@MainActor private func grants(_ context: ModelContext, _ id: String? = nil) throws -> [AchievementGrant] {
    try context.fetch(FetchDescriptor<AchievementGrant>(sortBy: [SortDescriptor(\.occurrence)]))
        .filter { id == nil || $0.achievementId == id }
}

/// Факты несут поля сессий, нужные повторяемым ачивкам: id сессии, начало, свойства текста, пункт плана.
@MainActor @Test func factsCarrySessionFieldsForRepeatables() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    insertSession(context, ended: "2026-10-23 09:00:00", day: "2026-10-23", mode: "practice", seconds: 40,
                  planSlot: "text", traits: 9)
    insertSession(context, ended: "2026-10-23 10:00:00", day: "2026-10-23", mode: "practice")
    try context.save()
    let record = try #require(try context.fetch(FetchDescriptor<SessionRecord>(
        sortBy: [SortDescriptor(\.endedAt)])).first)
    let facts = try makeService(context).facts()
    let fact = try #require(facts.exercises.first)
    #expect(fact.sessionId == record.id.uuidString)
    #expect(fact.startedAt == at("2026-10-23 08:59:20"))
    #expect(fact.textTraits == 9 && fact.planSlot == .text)
    #expect(facts.exercises[1].planSlot == nil && facts.exercises[1].textTraits == nil)
}

/// Шаги звёзд урока издания 2 — после каждого завершённого упражнения урока по `LessonScoring.effectiveStars`;
/// итог совпадает с `starsByLesson`; уроки издания 1 в шагах не участвуют.
@MainActor @Test func lessonStarStepsFollowHistory() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let course = try CourseCatalog.load(.ru)
    let check = try #require(course.stages[0].checkLesson)
    let target = Double(try #require(course.targetCpm(for: check.id)))
    insertSession(context, ended: "2026-10-25 10:00", day: "2026-10-25", lessonId: check.id, kind: "check",
                  chars: 200, accuracy: 1, cpm: target, wrong: 0, stepIndex: 2)
    insertSession(context, ended: "2026-10-25 10:05", day: "2026-10-25", lessonId: check.id, kind: "check",
                  chars: 200, accuracy: 0.5, cpm: target, wrong: 20, stepIndex: 2)
    insertSession(context, ended: "2026-10-25 10:10", day: "2026-10-25", lessonId: check.id, kind: "check",
                  chars: 200, accuracy: 1, cpm: target * 2, wrong: 0, stepIndex: 2)
    insertSession(context, ended: "2026-10-25 10:20", day: "2026-10-25", lessonId: "ru.1.1", kind: "check",
                  chars: 200, accuracy: 1, cpm: 300, wrong: 0)
    let progress = LessonProgress(lessonId: check.id, language: "ru")
    progress.bestStars = 3
    progress.passedAt = at("2026-10-25 10:00")
    context.insert(progress)
    try context.save()
    let facts = try makeService(context, now: at("2026-10-25 12:00")).facts()
    let steps = try #require(facts.lessonStarSteps[check.id])
    #expect(steps.count >= 2, "звёзды менялись минимум дважды: \(steps)")
    #expect(steps.first?.date == at("2026-10-25 10:00"))
    #expect(steps.map(\.date) == steps.map(\.date).sorted())
    #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.stars != $1.stars })
    #expect(steps.last?.stars == facts.starsByLesson[check.id])
    #expect(steps.last?.date == at("2026-10-25 10:10") && steps.last?.checkCpm == target * 2)
    #expect(facts.lessonStarSteps["ru.1.1"] == nil, "издание 1 — без шагов")
}

/// Шаги звёзд не берут итоговые хранимые звёзды: до первой проверки урока шагов нет, а первый шаг со звёздами
/// датирован проверкой, даже если у урока `bestStars = 5` (иначе ★★★★★ и ступень получили бы дату первого шага).
@MainActor @Test func lessonStarStepsStartAtFirstCheckDespiteStoredStars() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let course = try CourseCatalog.load(.ru)
    let check = try #require(course.stages[0].checkLesson)
    let target = Double(try #require(course.targetCpm(for: check.id)))
    insertSession(context, ended: "2026-10-25 10:00", day: "2026-10-25", lessonId: check.id, kind: "words",
                  chars: 100, accuracy: 1, cpm: target, wrong: 0, stepIndex: 0)
    insertSession(context, ended: "2026-10-25 10:05", day: "2026-10-25", lessonId: check.id, kind: "words",
                  chars: 100, accuracy: 1, cpm: target, wrong: 0, stepIndex: 1)
    insertSession(context, ended: "2026-10-25 10:10", day: "2026-10-25", lessonId: check.id, kind: "check",
                  chars: 200, accuracy: 1, cpm: target * 2, wrong: 0, stepIndex: 2)
    let progress = LessonProgress(lessonId: check.id, language: "ru")
    progress.bestStars = 5
    progress.passedAt = at("2026-10-25 10:10")
    context.insert(progress)
    try context.save()
    let facts = try makeService(context, now: at("2026-10-25 12:00")).facts()
    let steps = try #require(facts.lessonStarSteps[check.id])
    let checkDate = at("2026-10-25 10:10")
    #expect(steps.allSatisfy { $0.date >= checkDate }, "шаги до проверки звёзд не дают: \(steps)")
    let firstThree = try #require(steps.first { $0.stars >= 3 })
    #expect(firstThree.date == checkDate && firstThree.checkCpm == target * 2)
    let five = try #require(steps.first { $0.stars >= 5 })
    #expect(five.checkCpm != nil)
    #expect(steps.last?.stars == facts.starsByLesson[check.id])
}

/// Число шагов урока для пункта «Урок» плана — та же функция, что у `DayPlanLoader`; только уроки пункта «Урок».
@MainActor @Test func lessonStepCountsReuseDayPlanLoader() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let course = try CourseCatalog.load(.ru)
    let lesson = try #require(course.stages[0].checkLesson)
    insertSession(context, ended: "2026-10-25 10:00", day: "2026-10-25", lessonId: lesson.id, kind: "check",
                  chars: 200, accuracy: 1, cpm: 80, wrong: 0, stepIndex: 2, planSlot: "lesson")
    insertSession(context, ended: "2026-10-25 10:10", day: "2026-10-25", lessonId: "ru.1.1", kind: "check",
                  planSlot: "lesson")
    try context.save()
    let facts = try makeService(context, now: at("2026-10-25 12:00")).facts()
    let expected = DayPlanLoader.stepCounts(course: course, ids: [lesson.id])
    #expect(expected[lesson.id] ?? 0 > 0)
    #expect(facts.lessonStepCounts == expected)
}

@MainActor private func morningHistory(_ context: ModelContext) throws {
    for day in ["2026-10-21", "2026-10-22"] {
        insertSession(context, ended: "\(day) 08:00:00", day: day, mode: "practice")
    }
    try context.save()
}

/// Первый запуск: выдачи из истории — просмотренные, повтор ничего не меняет, новое утро — непросмотренная
/// выдача с «×3»; существующая выдача с другим значением и датой не перезаписывается.
@MainActor @Test func grantsAreBackfilledThenOnlyMissingOnesAreAdded() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try morningHistory(context)
    let launch = try makeService(context).check(reason: .launch)
    #expect(launch.isGrantBackfill && launch.isBackfill)
    let morning = try grants(context, "time.morning")
    #expect(morning.map(\.occurrence) == ["2026-10-21", "2026-10-22"])
    #expect(morning.map(\.grantedAt) == [at("2026-10-21 08:00"), at("2026-10-22 08:00")])
    #expect(morning.allSatisfy { $0.seen })
    #expect(launch.grants.filter { $0.achievement.id == "time.morning" }.map(\.count) == [1, 2])
    let allGrants = try grants(context)
    #expect(allGrants.allSatisfy { $0.seen })
    #expect(try records(context).contains { $0.achievementId == "time.morning" })
    let total = try grants(context).count
    #expect(total == launch.grants.count)

    // Пользователь уже мог увидеть выдачу или изменить значение: ничего не трогаем.
    let first = try #require(morning.first)
    first.value = 7
    first.seen = false
    let stamp = first.grantedAt
    try context.save()
    let again = try makeService(context).check(reason: .launch)
    #expect(again.grants.isEmpty && !again.isGrantBackfill && !again.isBackfill)
    #expect(try grants(context).count == total)
    let kept = try #require(try grants(context, "time.morning").first)
    #expect(kept.value == 7 && !kept.seen && kept.grantedAt == stamp)

    insertSession(context, ended: "2026-10-23 09:00:00", day: "2026-10-23", mode: "practice")
    try context.save()
    let saved = try makeService(context, now: at("2026-10-23 09:01")).check(reason: .afterSave)
    let added = saved.grants.filter { $0.achievement.id == "time.morning" }
    #expect(added.count == 1 && added[0].occurrence == "2026-10-23" && added[0].count == 3)
    #expect(!saved.isGrantBackfill)
    let third = try #require(try grants(context, "time.morning").first { $0.occurrence == "2026-10-23" })
    #expect(!third.seen && third.grantedAt == at("2026-10-23 09:00"))
    #expect(try grants(context, "time.morning").count == 3)
}

/// Выдача, чьей пары нет, добавляется при запуске просмотренной даже при непустой таблице выдач (решение 15 6e:
/// при запуске недостающая выдача — результат обновления правил или каталога) и попадает в сводку; новая разовая
/// ачивка при таком запуске непросмотренная и не «задним числом».
@MainActor @Test func laterLaunchGrantsAreSeenAndSummarized() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try morningHistory(context)
    context.insert(AchievementRecord(achievementId: "time.morning", unlockedAt: at("2026-10-21 08:00"), seen: true))
    context.insert(AchievementGrant(achievementId: "time.morning", occurrence: "2026-10-21",
                                    grantedAt: at("2026-10-21 08:00"), seen: true))
    let caps = CounterRecord(name: CounterName.capsLockPresses)
    caps.value = 1
    context.insert(caps)
    try context.save()
    let result = try makeService(context).check(reason: .launch)
    #expect(result.isGrantBackfill && !result.isBackfill)
    #expect(result.grants.map(\.occurrence) == ["2026-10-22"] && result.grants.first?.count == 2)
    #expect(try grants(context, "time.morning").first { $0.occurrence == "2026-10-22" }?.seen == true)
    #expect(try grants(context, "time.morning").first { $0.occurrence == "2026-10-21" }?.seen == true)
    let unseenRecords = try records(context).filter { !$0.seen }
    #expect(result.new.map(\.id) == ["fun.oy_vsyo"] && unseenRecords.count == 1)
}

/// Первая неделя пользователя выполнена, а таблица выдач уже не пуста (база 6d): при запуске выдачи `challenge.week`
/// прошлых недель — просмотренные и в сводке; после сохранения упражнения новая выдача — непросмотренная.
@MainActor @Test func pastChallengeGrantsAreSeenAtLaunchAndNewOnesAreNot() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    func day(_ key: String, seconds: Double, exercises: Int) {
        let record = DayRecord(logicalDay: key)
        record.activeSeconds = seconds
        record.completedExercises = exercises
        record.goalSeconds = 600
        context.insert(record)
    }
    // Неделя 2026-W44 — первая у пользователя: три дня, три проверки урока, день с целью.
    for (index, lesson) in ["ru.1.1", "ru.1.2", "ru.1.3"].enumerated() {
        insertSession(context, ended: "2026-10-28 20:0\(index)", day: "2026-10-28", mode: "course", lessonId: lesson,
                      kind: "check", seconds: 250)
    }
    day("2026-10-28", seconds: 750, exercises: 3)
    for key in ["2026-10-29", "2026-10-30"] {
        insertSession(context, ended: "\(key) 20:00", day: key, mode: "course", seconds: 200)
        day(key, seconds: 200, exercises: 1)
    }
    // Неделя 2026-W45: цель и три проверки уже 2 ноября, второй день 3-го.
    for (index, lesson) in ["ru.1.4", "ru.1.5", "ru.1.6"].enumerated() {
        insertSession(context, ended: "2026-11-02 20:0\(index)", day: "2026-11-02", mode: "course", lessonId: lesson,
                      kind: "check", seconds: 250)
    }
    day("2026-11-02", seconds: 750, exercises: 3)
    insertSession(context, ended: "2026-11-03 20:00", day: "2026-11-03", mode: "course", seconds: 200)
    day("2026-11-03", seconds: 200, exercises: 1)
    // База 6d: выдача уже есть, значит, таблица не пуста и это не первый запуск выдач.
    context.insert(AchievementGrant(achievementId: "time.morning", occurrence: "2026-10-21",
                                    grantedAt: at("2026-10-21 08:00"), seen: true))
    context.insert(AchievementRecord(achievementId: "course.first_lesson", unlockedAt: at("2026-10-28 20:00"), seen: true))
    try context.save()

    let launch = try makeService(context, now: at("2026-11-03 21:00")).check(reason: .launch)
    let past = try grants(context, "challenge.week")
    #expect(past.map(\.occurrence) == ["2026-W44"])
    #expect(past.allSatisfy { $0.seen }, "выдачи прошлых недель при запуске — просмотренные")
    #expect(launch.grants.contains { $0.achievement.id == "challenge.week" })
    #expect(launch.isGrantBackfill && !launch.isBackfill)
    #expect(try grants(context).allSatisfy { $0.seen })
    #expect(AchievementAnnouncer.summaryCount(launch, adultHumor: true) >= 1)

    // Третий день недели W45 — выдача после сохранения упражнения непросмотренная.
    insertSession(context, ended: "2026-11-04 09:00", day: "2026-11-04", mode: "course", seconds: 200)
    try context.save()
    let saved = try makeService(context, now: at("2026-11-04 09:20")).check(reason: .afterSave)
    #expect(!saved.isGrantBackfill)
    let fresh = try grants(context, "challenge.week").filter { $0.occurrence == "2026-W45" }
    #expect(fresh.count == 1 && fresh[0].seen == false, "новая выдача после упражнения — непросмотренная")
}

/// Сводка при запуске: N — видимые новые ачивки плюс выдачи; скрытые «взрослые» выдачи не считаются.
@MainActor @Test func launchSummaryCountsGrants() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try morningHistory(context)
    let toasts = ToastCenter(timer: ManualClock().timer)
    let outcome = AchievementAnnouncer.launchCheck(service: makeService(context), toasts: toasts, adultHumor: true) {}
    #expect(outcome.isGrantBackfill && outcome.grants.count >= 2)
    let toast = try #require(toasts.current)
    #expect(toast.message == Formatting.backfillSummary(summaryCount(outcome)))

    let hiddenContainer = try ModelStore.makeContainer(inMemory: true)
    let hiddenContext = hiddenContainer.mainContext
    try morningHistory(hiddenContext)
    let hiddenToasts = ToastCenter(timer: ManualClock().timer)
    let visibleOutcome = AchievementAnnouncer.launchCheck(
        service: makeService(hiddenContext), toasts: hiddenToasts, adultHumor: false) {}
    let hiddenMessage = try #require(hiddenToasts.current).message
    #expect(hiddenMessage == Formatting.backfillSummary(summaryCount(visibleOutcome, adultHumor: false)))
}

/// Число в сводке запуска: новые и выдачи; первая выдача новой повторяемой — та же ачивка и не считается дважды.
private func summaryCount(_ outcome: AchievementService.Outcome, adultHumor: Bool = true) -> Int {
    let newIds = Set(outcome.new.map(\.id))
    let new = outcome.new.filter { adultHumor || !$0.adult }.count
    let grants = outcome.grants.filter {
        (adultHumor || !$0.achievement.adult) && !($0.count == 1 && newIds.contains($0.achievement.id))
    }.count
    return new + grants
}

/// Одна новая повторяемая ачивка при запуске (её первая выдача) — обычный тост, а не сводка «2».
@MainActor @Test func launchCheckWithOneNewRepeatableShowsItsToast() throws {
    let morning = try #require(AchievementCatalog.all.first { $0.id == "time.morning" })
    let outcome = AchievementService.Outcome(
        new: [morning], isBackfill: false,
        grants: [AchievementService.NewGrant(achievement: morning, occurrence: "2026-11-01", value: nil, count: 1)])
    #expect(AchievementAnnouncer.summaryCount(outcome, adultHumor: true) == 1)
}
