import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

// MARK: - Помощники

private let msk = TimeZone(identifier: "Europe/Moscow")!

/// «2026-11-03 09:00» по Москве.
private func at(_ text: String) -> Date {
    let parts = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" }).compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = msk
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3],
                                              minute: parts[4]))!
}

@MainActor private func insertSession(_ context: ModelContext, ended: String, day: String, kind: String? = nil,
                                      lessonId: String? = nil, seconds: Double = 200) {
    let end = at(ended)
    context.insert(SessionRecord(
        mode: "course", language: "ru", lessonId: lessonId, startedAt: end.addingTimeInterval(-seconds), endedAt: end,
        logicalDay: day, activeSeconds: seconds, chars: 80, errorCount: 1, cpm: 160, accuracy: 0.99,
        completed: true, hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 1, exerciseKind: kind))
}

@MainActor private func insertDay(_ context: ModelContext, _ day: String, seconds: Double, exercises: Int) {
    let record = DayRecord(logicalDay: day)
    record.activeSeconds = seconds
    record.completedExercises = exercises
    record.goalSeconds = 600
    context.insert(record)
}

/// История двух недель: первая (26 октября – 1 ноября) — лёгкий набор выполнен 30 октября, вторая только началась.
@MainActor private func populateTwoWeeks(_ context: ModelContext) throws {
    for (index, lesson) in ["ru.1.1", "ru.1.2", "ru.1.3"].enumerated() {
        insertSession(context, ended: "2026-10-28 20:0\(index)", day: "2026-10-28", kind: "check", lessonId: lesson,
                      seconds: 250)
    }
    insertDay(context, "2026-10-28", seconds: 750, exercises: 3)
    insertSession(context, ended: "2026-10-29 20:00", day: "2026-10-29")
    insertDay(context, "2026-10-29", seconds: 200, exercises: 1)
    insertSession(context, ended: "2026-10-30 20:00", day: "2026-10-30")
    insertDay(context, "2026-10-30", seconds: 200, exercises: 1)
    insertSession(context, ended: "2026-11-02 20:00", day: "2026-11-02")
    insertDay(context, "2026-11-02", seconds: 200, exercises: 1)
    insertSession(context, ended: "2026-11-03 09:00", day: "2026-11-03")
    insertDay(context, "2026-11-03", seconds: 200, exercises: 1)
    try context.save()
}

@MainActor private func makeService(_ context: ModelContext, now: Date = at("2026-11-03 10:00"),
                                    cache: AchievementFactsCache = AchievementFactsCache()) -> AchievementService {
    AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4), goalSeconds: { 600 },
                       timeZone: msk, now: { now }, cache: cache)
}

// MARK: - YearLoader

/// Снимок года совпадает с ядром: журнал опыта, уровень, испытания текущей недели и месяца, история.
@MainActor @Test func yearLoaderMatchesTheCore() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateTwoWeeks(context)
    let service = makeService(context)
    let state = try YearLoader(context: context, service: service).state()

    let facts = try service.facts()
    let challenges = Challenges.evaluate(facts)
    let ledger = Experience.ledger(facts)
    #expect(state.ledger == ledger)
    #expect(state.ledger.total > 0)
    let progress = LevelCurve.progress(forExperience: ledger.total)
    #expect(state.level == progress.level && state.gained == progress.gained && state.needed == progress.needed)
    #expect(state.title == LevelTitle.of(level: progress.level))
    #expect(state.today == "2026-11-03")
    #expect(state.week == challenges.first { $0.period == .week("2026-W45") })
    #expect(state.month == challenges.first { $0.period == .month("2026-11") })
    #expect(state.week != nil && state.month != nil)
    #expect(state.streak == StreakCalculator.summarize(days: facts.days, today: "2026-11-03", goalSeconds: 600))

    // История — периоды с хотя бы одним выполненным испытанием, новые сверху: первая неделя выполнена целиком.
    let done = challenges.filter { $0.results.contains { $0.completedAt != nil } }
    #expect(state.history == Array(done.reversed()))
    #expect(state.history.contains { $0.period == .week("2026-W44") && $0.allDoneAt == at("2026-10-30 20:00") })
}

/// Повторный вызов без новых занятий ничего не пересчитывает; новая сессия, новый день — пересчёт (решение 16).
@MainActor @Test func yearLoaderCachesUntilHistoryChanges() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateTwoWeeks(context)
    let cache = AchievementFactsCache()
    let loader = YearLoader(context: context, service: makeService(context, cache: cache))

    let first = try loader.state()
    #expect(cache.yearBuilds == 1)
    #expect(try loader.state() == first)
    #expect(cache.yearBuilds == 1, "минутный таймер главной не пересчитывает опыт")

    insertSession(context, ended: "2026-11-03 09:30", day: "2026-11-03")
    try context.save()
    let second = try loader.state()
    #expect(cache.yearBuilds == 2)
    #expect(second.ledger.total > first.ledger.total)

    // Другой день с тем же кэшем — пересчёт: сегодняшний день в ключе.
    let nextDay = YearLoader(context: context, service: makeService(context, now: at("2026-11-04 10:00"), cache: cache))
    #expect(try nextDay.state().today == "2026-11-04")
    #expect(cache.yearBuilds == 3)

    // Явный сброс кэша фактов (загрузка прогресса из файла) сбрасывает и снимок.
    cache.invalidate()
    _ = try nextDay.state()
    #expect(cache.yearBuilds == 4)
}

/// После проверки ачивок снимок года берёт её факты: упражнения для `facts()` читаются один раз, а не дважды.
@MainActor @Test func yearLoaderReusesFactsOfTheAchievementCheck() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    try populateTwoWeeks(context)
    let cache = AchievementFactsCache()
    let service = makeService(context, cache: cache)

    _ = try service.check(reason: .afterSave)
    #expect(cache.exerciseReads == 1)
    let state = try YearLoader(context: context, service: service).state()
    #expect(cache.exerciseReads == 1, "второй сборки facts() нет")
    #expect(cache.factsReuses == 1 && cache.yearBuilds == 1)

    // Тот же результат, что и без проверки (поведение не меняется).
    let fresh = try YearLoader(context: context, service: makeService(context)).state()
    #expect(state == fresh)

    // Запомненные факты отдаются один раз: после новой сессии без проверки факты собираются заново.
    insertSession(context, ended: "2026-11-03 09:30", day: "2026-11-03")
    try context.save()
    _ = try YearLoader(context: context, service: service).state()
    #expect(cache.exerciseReads == 2 && cache.factsReuses == 1)
}

/// Пустая база: уровень 1, испытаний нет.
@MainActor @Test func yearStateOfEmptyStore() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let state = try YearLoader(context: container.mainContext, service: makeService(container.mainContext)).state()
    #expect(state.level == 1 && state.title == .novice && state.gained == 0 && state.needed == 100)
    #expect(state.week == nil && state.month == nil && state.history.isEmpty)
    #expect(state.ledger.total == 0)
}

// MARK: - YearAnnouncer

@MainActor private func baseState() throws -> YearState {
    let container = try ModelStore.makeContainer(inMemory: true)
    return try YearLoader(context: container.mainContext, service: makeService(container.mainContext)).state()
}

private func challenge(_ id: ChallengeId, done: Bool) -> ChallengeResult {
    ChallengeResult(id: id, progress: done ? 5 : 2, target: 5, completedAt: done ? at("2026-11-03 09:00") : nil)
}

private func period(_ period: ChallengePeriod, _ results: [ChallengeResult],
                    allDoneAt: Date? = nil) -> ChallengePeriodResult {
    ChallengePeriodResult(period: period, parameters: ChallengeParameters(goalMinutes: 10, cpm: 100),
                          results: results, allDoneAt: allDoneAt)
}

@MainActor private func state(_ base: YearState, level: Int = 1, week: ChallengePeriodResult? = nil,
                              month: ChallengePeriodResult? = nil) -> YearState {
    YearState(ledger: base.ledger, level: level, title: LevelTitle.of(level: level), gained: 0, needed: 100 * level,
              week: week, month: month, history: [], streak: base.streak, today: "2026-11-03")
}

/// Тосты по очереди: показанные сейчас и ждущие.
@MainActor private func drain(_ toasts: ToastCenter) -> [String] {
    var messages: [String] = []
    while let current = toasts.current {
        messages.append(current.message)
        toasts.dismiss()
    }
    return messages
}

@MainActor private func makeToasts() -> ToastCenter { ToastCenter(timer: { _, _ in {} }) }

/// При запуске тостов нет, оба ключа выставлены по текущему состоянию (решение 14).
@MainActor @Test func launchSetsKeysWithoutToasts() throws {
    let (defaults, name) = makeTestDefaults("year-launch")
    defer { removeTestDefaults(name) }
    let base = try baseState()
    let week = period(.week("2026-W45"), [challenge(.weekGoal5, done: true), challenge(.weekVisit7, done: false)])
    let month = period(.month("2026-11"), [challenge(.monthGoal20, done: true)])
    YearAnnouncer.launch(state: state(base, level: 12, week: week, month: month), defaults: defaults)
    #expect(defaults.integer(forKey: "yearAnnouncedLevel") == 12)
    #expect(Set(defaults.stringArray(forKey: "yearAnnouncedChallenges") ?? [])
            == ["2026-W45#w.goal5", "2026-11#m.goal20"])
}

/// Переход 9 → 10: один тост «Уровень 10 · Ученик»; повтор — ничего; скачок на несколько уровней — один тост.
@MainActor @Test func levelToastIsShownOncePerLevelChange() throws {
    let (defaults, name) = makeTestDefaults("year-level")
    defer { removeTestDefaults(name) }
    let base = try baseState()
    let toasts = makeToasts()
    YearAnnouncer.launch(state: state(base, level: 9), defaults: defaults)

    #expect(YearAnnouncer.afterSave(state: state(base, level: 9), toasts: toasts, sound: nil, defaults: defaults) == 0)
    #expect(drain(toasts).isEmpty)

    #expect(YearAnnouncer.afterSave(state: state(base, level: 10), toasts: toasts, sound: nil, defaults: defaults) == 1)
    #expect(drain(toasts) == ["Уровень 10 · Ученик"])
    #expect(defaults.integer(forKey: "yearAnnouncedLevel") == 10)
    #expect(YearAnnouncer.afterSave(state: state(base, level: 10), toasts: toasts, sound: nil, defaults: defaults) == 0)
    #expect(drain(toasts).isEmpty)

    #expect(YearAnnouncer.afterSave(state: state(base, level: 30), toasts: toasts, sound: nil, defaults: defaults) == 1)
    #expect(drain(toasts) == ["Уровень 30 · Мастер"], "скачок на несколько уровней — один тост последнего")

    // Уровень стал ниже (поднята цель дня): тоста нет, показанный уровень не опускается —
    // возврат к 30 тоста не повторит.
    #expect(YearAnnouncer.afterSave(state: state(base, level: 29), toasts: toasts, sound: nil, defaults: defaults) == 0)
    #expect(defaults.integer(forKey: "yearAnnouncedLevel") == 30)
    #expect(YearAnnouncer.afterSave(state: state(base, level: 30), toasts: toasts, sound: nil, defaults: defaults) == 0)
    #expect(drain(toasts).isEmpty)

    // Загружен другой прогресс — базовая линия от запуска, следует за состоянием.
    YearAnnouncer.launch(state: state(base, level: 5), defaults: defaults)
    #expect(defaults.integer(forKey: "yearAnnouncedLevel") == 5)
}

/// Выполненное испытание недели и месяца — тост на каждое один раз: «+100 опыта» и «+500 опыта».
@MainActor @Test func challengeToastIsShownOncePerChallenge() throws {
    let (defaults, name) = makeTestDefaults("year-challenge")
    defer { removeTestDefaults(name) }
    let base = try baseState()
    let toasts = makeToasts()
    let before = state(base, week: period(.week("2026-W45"), [challenge(.weekGoal5, done: false)]),
                       month: period(.month("2026-11"), [challenge(.monthGoal20, done: false)]))
    YearAnnouncer.launch(state: before, defaults: defaults)

    let after = state(base, week: period(.week("2026-W45"), [challenge(.weekGoal5, done: true)]),
                      month: period(.month("2026-11"), [challenge(.monthGoal20, done: false)]))
    #expect(YearAnnouncer.afterSave(state: after, toasts: toasts, sound: nil, defaults: defaults) == 1)
    #expect(drain(toasts) == ["Испытание выполнено: Пять целей · +100 опыта"])
    #expect(YearAnnouncer.afterSave(state: after, toasts: toasts, sound: nil, defaults: defaults) == 0)
    #expect(drain(toasts).isEmpty)

    let monthDone = state(base, week: after.week, month: period(.month("2026-11"), [challenge(.monthGoal20, done: true)]))
    #expect(YearAnnouncer.afterSave(state: monthDone, toasts: toasts, sound: nil, defaults: defaults) == 1)
    #expect(drain(toasts) == ["Испытание выполнено: Двадцать целей · +500 опыта"])
}

/// Третье выполненное испытание недели — ещё +100 за все три (решение 10): тост показывает полную награду.
@MainActor @Test func thirdWeeklyChallengeToastIncludesAllThreeBonus() throws {
    let (defaults, name) = makeTestDefaults("year-all-three")
    defer { removeTestDefaults(name) }
    let base = try baseState()
    let toasts = makeToasts()
    let two = state(base, week: period(.week("2026-W45"), [challenge(.weekGoal5, done: true), challenge(.weekVisit7, done: true),
                                                           challenge(.weekChars, done: false)]))
    YearAnnouncer.launch(state: two, defaults: defaults)

    let three = state(base, week: period(.week("2026-W45"), [challenge(.weekGoal5, done: true), challenge(.weekVisit7, done: true),
                                                             challenge(.weekChars, done: true)],
                                         allDoneAt: at("2026-11-03 09:00")))
    #expect(YearAnnouncer.afterSave(state: three, toasts: toasts, sound: nil, defaults: defaults) == 1)
    #expect(drain(toasts) == ["Испытание выполнено: Знаки · +200 опыта"])
    // Месяц бонуса «все три» не получает.
    let month = state(base, week: three.week, month: period(.month("2026-11"), [challenge(.monthGoal20, done: true)],
                                                           allDoneAt: at("2026-11-03 09:00")))
    #expect(YearAnnouncer.afterSave(state: month, toasts: toasts, sound: nil, defaults: defaults) == 1)
    #expect(drain(toasts) == ["Испытание выполнено: Двадцать целей · +500 опыта"])
}

/// Уровень и испытания одним сохранением: уровень первым, потом каждое испытание; испытаний не больше трёх за раз,
/// но в `UserDefaults` отмечены все.
@MainActor @Test func toastsAreCappedAtThreeChallenges() throws {
    let (defaults, name) = makeTestDefaults("year-cap")
    defer { removeTestDefaults(name) }
    let base = try baseState()
    let toasts = makeToasts()
    YearAnnouncer.launch(state: state(base, level: 4), defaults: defaults)
    let all = state(base, level: 5,
                    week: period(.week("2026-W45"), [challenge(.weekGoal5, done: true), challenge(.weekVisit7, done: true),
                                                     challenge(.weekChars, done: true)]),
                    month: period(.month("2026-11"), [challenge(.monthGoal20, done: true)]))
    #expect(YearAnnouncer.afterSave(state: all, toasts: toasts, sound: nil, defaults: defaults) == 4)
    #expect(drain(toasts) == ["Уровень 5 · Новичок", "Испытание выполнено: Пять целей · +100 опыта",
                              "Испытание выполнено: Без пропусков · +100 опыта",
                              "Испытание выполнено: Знаки · +100 опыта"])
    #expect(Set(defaults.stringArray(forKey: "yearAnnouncedChallenges") ?? [])
            == ["2026-W45#w.goal5", "2026-W45#w.visit7", "2026-W45#w.chars", "2026-11#m.goal20"])
    #expect(YearAnnouncer.afterSave(state: all, toasts: toasts, sound: nil, defaults: defaults) == 0)
    #expect(drain(toasts).isEmpty, "четвёртое испытание не копится до следующего раза")
}

/// Новая неделя: ключи прошлой недели отбрасываются; её выполненные испытания заново не объявляются.
@MainActor @Test func newPeriodDropsOldKeys() throws {
    let (defaults, name) = makeTestDefaults("year-period")
    defer { removeTestDefaults(name) }
    let base = try baseState()
    let toasts = makeToasts()
    YearAnnouncer.launch(
        state: state(base, week: period(.week("2026-W45"), [challenge(.weekGoal5, done: true)]),
                     month: period(.month("2026-11"), [challenge(.monthGoal20, done: true)])), defaults: defaults)

    let next = state(base, week: period(.week("2026-W46"), [challenge(.weekGoal5, done: false), challenge(.weekChars, done: true)]),
                     month: period(.month("2026-11"), [challenge(.monthGoal20, done: true)]))
    #expect(YearAnnouncer.afterSave(state: next, toasts: toasts, sound: nil, defaults: defaults) == 1)
    #expect(drain(toasts) == ["Испытание выполнено: Знаки · +100 опыта"])
    #expect(Set(defaults.stringArray(forKey: "yearAnnouncedChallenges") ?? [])
            == ["2026-W46#w.chars", "2026-11#m.goal20"])

    // Та же цель в новой неделе — другой ключ, объявляется снова.
    let again = state(base, week: period(.week("2026-W46"), [challenge(.weekGoal5, done: true), challenge(.weekChars, done: true)]),
                      month: next.month)
    #expect(YearAnnouncer.afterSave(state: again, toasts: toasts, sound: nil, defaults: defaults) == 1)
    #expect(drain(toasts) == ["Испытание выполнено: Пять целей · +100 опыта"])
}

/// Запуск ещё не выставил ключи (нет базовой линии): первое сохранение только запоминает состояние, без лавины тостов.
@MainActor @Test func withoutBaselineAfterSaveOnlyRemembers() throws {
    let (defaults, name) = makeTestDefaults("year-baseline")
    defer { removeTestDefaults(name) }
    let base = try baseState()
    let toasts = makeToasts()
    let current = state(base, level: 7, week: period(.week("2026-W45"), [challenge(.weekGoal5, done: true)]))
    #expect(YearAnnouncer.afterSave(state: current, toasts: toasts, sound: nil, defaults: defaults) == 0)
    #expect(drain(toasts).isEmpty)
    #expect(defaults.integer(forKey: "yearAnnouncedLevel") == 7)
    #expect(defaults.stringArray(forKey: "yearAnnouncedChallenges") == ["2026-W45#w.goal5"])
}

/// Ключи состояния показа — вне архива и вне настроек (§20, решение 14).
@Test func yearKeysAreNotArchived() {
    let archived = Set(ArchivedSettings.entries.map(\.key))
    #expect(archived.isDisjoint(with: [SettingsKey.yearAnnouncedLevel, SettingsKey.yearAnnouncedChallenges]))
    #expect(SettingsKey.yearAnnouncedLevel == "yearAnnouncedLevel")
    #expect(SettingsKey.yearAnnouncedChallenges == "yearAnnouncedChallenges")
}

// MARK: - Названия

/// Названия испытаний, званий и рангов заведены для каждого значения; у разных значений разные названия.
@Test func yearTextCoversEveryCase() {
    let challengeTitles = ChallengeId.allCases.map { YearText.title($0) }
    #expect(challengeTitles.allSatisfy { !$0.isEmpty } && Set(challengeTitles).count == ChallengeId.allCases.count)
    #expect(YearText.title(.weekGoal5) == "Пять целей" && YearText.title(.monthGoal20) == "Двадцать целей")
    let levelTitles = LevelTitle.allCases.map { YearText.title($0) }
    #expect(levelTitles == ["Новичок", "Ученик", "Уверенный", "Мастер", "Виртуоз", "Легенда"])
    let ranks = SpeedRank.allCases.map { YearText.title($0) }
    #expect(ranks == ["Пешеход", "Велосипедист", "Водитель", "Гонщик", "Пилот", "Ракета"])
}

// MARK: - Координатор

/// После сохранения упражнения и проверки ачивок координатор вызывает проверку года (со звуком — только на итоге).
@MainActor @Test func coordinatorRunsYearCheckAfterAchievements() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    var delayed: [@MainActor () -> Void] = []
    let coordinator = ExerciseCoordinator(recorder: recorder, playSound: { _ in }, goalSeconds: { 1e9 },
                                          afterDelay: { _, action in delayed.append(action) })
    coordinator.achievements = AchievementService(recorder: recorder, goalSeconds: { 1e9 }, timeZone: msk,
                                                  now: { Date() }, catalog: [])
    var calls: [Bool] = []
    coordinator.yearCheck = { calls.append($0) }

    let spec = ExerciseSpec(id: 0, kind: .words, title: "Слова", text: "ао")
    let session = coordinator.start(spec: spec, language: .ru, mode: .practice, lessonId: nil, hint: .full) { s, r in
        coordinator.recordFinish(s, r)
    }
    session.layoutLanguage = .ru
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 0.3)
    // На экране итога — после паузы звука результата, со звуком (ачивок нет).
    #expect(calls.isEmpty && delayed.count == 1)
    delayed.forEach { $0() }
    #expect(calls == [true])
}
