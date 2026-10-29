import Foundation
import SwiftData
import TypingCore

/// Записывает итог упражнения: сессия, день, статистика клавиш; отдельно — прогресс урока и счётчики.
/// `record`, `recordLesson` и `increment` только меняют контекст; сохраняет всё вместе `commit`.
@MainActor
struct ResultRecorder {
    let context: ModelContext
    /// Час начала логического дня. Читается при каждой записи, а не один раз на запуск:
    /// смена настройки посреди тренировки действует на следующую же запись.
    let dayStartHour: () -> Int
    /// Дневная цель в секундах; тоже читается при каждой записи и записывается в день (`DayRecord.goalSeconds`).
    let goalSeconds: () -> Double
    /// Шов для тестов: вызывается перед сохранением внутри `commit` и может бросить ошибку,
    /// чтобы проверить откат и алерт «Повторить» / «Отмена» (в приложении не задаётся).
    var beforeSave: (() throws -> Void)?

    /// Цель по умолчанию — исходная из настроек (`SettingsDefault.dailyGoalMinutes`), не из `UserDefaults`.
    init(context: ModelContext, dayStartHour: @escaping () -> Int,
         goalSeconds: @escaping () -> Double = { Double(SettingsDefault.dailyGoalMinutes) * 60 }) {
        self.context = context
        self.dayStartHour = dayStartHour
        self.goalSeconds = goalSeconds
    }

    /// Постоянный час начала дня (для тестов).
    init(context: ModelContext, dayStartHour: Int) {
        self.init(context: context, dayStartHour: { dayStartHour })
    }

    /// Для приложения: час начала дня и цель берутся из настроек в момент записи.
    static func live(context: ModelContext) -> ResultRecorder {
        ResultRecorder(context: context, dayStartHour: { StoredSettings.dayStartHour() },
                       goalSeconds: { StoredSettings.dailyGoalSeconds() })
    }

    /// Выполняет изменения и сохраняет их одной транзакцией. При ошибке откатывает контекст,
    /// поэтому тот же `body` можно безопасно выполнить повторно.
    func commit(_ body: () throws -> Void) throws {
        do {
            try body()
            try beforeSave?()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Активность логического дня, как она видна в контексте (с несохранёнными изменениями).
    func dayActivity(forKey key: String) throws -> DayActivity? {
        let descriptor = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.logicalDay == key })
        return try context.fetch(descriptor).first.map {
            DayActivity(activeSeconds: $0.activeSeconds, completedExercises: $0.completedExercises,
                        goalSeconds: $0.goalSeconds)
        }
    }

    /// `source` — откуда текст вне курса (см. `SessionRecord.source`).
    func record(_ result: ExerciseResult, source: String? = nil) throws {
        let day = LogicalDay.key(for: result.endedAt, dayStartHour: dayStartHour())
        let pinky = KeyStats.pinkyCounts(from: result)
        let fingers = KeyStats.fingerCounts(from: result)
        context.insert(SessionRecord(
            mode: result.mode.rawValue, language: result.language.rawValue, lessonId: result.lessonId,
            startedAt: result.startedAt, endedAt: result.endedAt, logicalDay: day,
            activeSeconds: result.activeSeconds, chars: result.chars, errorCount: result.errorCount,
            cpm: result.cpm, accuracy: result.accuracy, completed: result.completed,
            hintLevel: result.hintLevel.rawValue, maxErrorStreak: result.maxErrorStreak,
            wrongKeystrokes: result.wrongKeystrokes, exerciseKind: result.exerciseKind?.rawValue,
            pinkyPresses: pinky.presses, pinkyErrors: pinky.errors, source: source,
            fingerPresses: FingerCounts.data(fingers.presses), fingerErrors: FingerCounts.data(fingers.errors),
            yoPresses: KeyStats.yoCorrect(from: result), stepIndex: result.stepIndex,
            textTraits: result.textTraits.union(TextTraits.connected(source: source)).rawValue
        ))

        let dayRecord = try fetchOrCreateDay(day)
        // День следует текущей цели, пока в нём занимаются; после — остаётся с целью последней записи.
        dayRecord.goalSeconds = goalSeconds()
        dayRecord.activeSeconds += result.activeSeconds
        if result.completed { dayRecord.completedExercises += 1 } else { dayRecord.abandonedExercises += 1 }
        if !dayRecord.languages.contains(result.language.rawValue) {
            dayRecord.languages.append(result.language.rawValue)
        }

        for (character, sample) in KeyStats.samples(from: result) {
            let stat = try fetchOrCreateKeyStat(language: result.language.rawValue, character: String(character))
            if let code = sample.keyCode { stat.keyCode = Int(code) }
            stat.presses += sample.outcomes.count
            stat.errors += sample.outcomes.filter { $0 }.count
            for ms in sample.intervalsMs { stat.ewmaMs = KeyStats.ewma(stat.ewmaMs, ms) }
            stat.recent = KeyStats.appendRecent(stat.recent, sample.outcomes)
        }

        for (bigram, sample) in KeyStats.bigramSamples(from: result) {
            let stat = try fetchOrCreateBigramStat(language: result.language.rawValue, bigram: bigram)
            stat.count += sample.outcomes.count
            stat.errors += sample.outcomes.filter { $0 }.count
            for ms in sample.intervalsMs { stat.ewmaMs = KeyStats.ewma(stat.ewmaMs, ms) }
            stat.recent = KeyStats.appendRecent(stat.recent, sample.outcomes)
        }
    }

    /// Вызывается после проверочного упражнения урока; `stars` — по 5-звёздной шкале, `stars == 0` — урок не засчитан.
    /// Уроки издания 1 хранят прежнюю 3-звёздную шкалу (решение 1 фазы 6a), издания 2 — 5-звёздную (§16, решение 2):
    /// по ним работает запасное правило `effectiveStars`. Зачёт — как раньше, при stars > 0.
    func recordLesson(_ result: ExerciseResult, stars: Int) throws {
        guard let lessonId = result.lessonId else { return }
        let descriptor = FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.lessonId == lessonId })
        let progress = try context.fetch(descriptor).first ?? {
            let created = LessonProgress(lessonId: lessonId, language: result.language.rawValue)
            context.insert(created)
            return created
        }()
        progress.attempts += 1
        progress.bestStars = max(progress.bestStars, CourseCatalog.edition(ofLessonId: lessonId) >= 2
                                                        ? stars : LessonScoring.legacyScale(fiveStar: stars))
        progress.bestCpm = max(progress.bestCpm, result.cpm)
        progress.bestAccuracy = max(progress.bestAccuracy, result.accuracy)
        if stars > 0 && progress.passedAt == nil { progress.passedAt = result.endedAt }
    }

    func increment(_ name: String, by amount: Int = 1) throws {
        let descriptor = FetchDescriptor<CounterRecord>(predicate: #Predicate { $0.name == name })
        let counter = try context.fetch(descriptor).first ?? {
            let created = CounterRecord(name: name)
            context.insert(created)
            return created
        }()
        counter.value += amount
    }

    /// Сохраняет, сколько букв открыто в адаптивной тренировке для языка.
    func recordAdaptive(language: Language, unlockedCount: Int) throws {
        let code = language.rawValue
        let descriptor = FetchDescriptor<AdaptiveState>(predicate: #Predicate { $0.language == code })
        if let state = try context.fetch(descriptor).first {
            state.unlockedCount = unlockedCount
        } else {
            context.insert(AdaptiveState(language: code, unlockedCount: unlockedCount))
        }
    }

    /// Запоминает, когда открылась буква адаптивной тренировки.
    func recordUnlock(language: Language, letter: Character, at date: Date) {
        context.insert(AdaptiveUnlock(language: language.rawValue, letter: String(letter), unlockedAt: date))
    }

    /// Позиция в тексте всегда в пределах `0...длина`.
    func advanceCustomText(_ text: CustomText, to offset: Int) {
        text.offset = min(max(offset, 0), text.body.count)
    }

    private func fetchOrCreateDay(_ key: String) throws -> DayRecord {
        let descriptor = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.logicalDay == key })
        if let existing = try context.fetch(descriptor).first { return existing }
        let created = DayRecord(logicalDay: key)
        context.insert(created)
        return created
    }

    private func fetchOrCreateKeyStat(language: String, character: String) throws -> KeyStat {
        let descriptor = FetchDescriptor<KeyStat>(
            predicate: #Predicate { $0.language == language && $0.character == character })
        if let existing = try context.fetch(descriptor).first { return existing }
        let created = KeyStat(language: language, character: character)
        context.insert(created)
        return created
    }

    private func fetchOrCreateBigramStat(language: String, bigram: String) throws -> BigramStat {
        let descriptor = FetchDescriptor<BigramStat>(
            predicate: #Predicate { $0.language == language && $0.bigram == bigram })
        if let existing = try context.fetch(descriptor).first { return existing }
        let created = BigramStat(language: language, bigram: bigram)
        context.insert(created)
        return created
    }
}
