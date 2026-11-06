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
    /// Словарь языка для списка слов с ошибками (по умолчанию — общий кэш; в тестах можно подменить).
    var vocabulary: (Language) -> Set<String> = ErrorWordVocabulary.words

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

    /// `source` — откуда текст вне курса (см. `SessionRecord.source`); `planSlot` — пункт плана дня, из которого
    /// запущено упражнение (`nil` — запуск не из плана, решение 15 фазы 6c).
    func record(_ result: ExerciseResult, source: String? = nil, planSlot: PlanSlot? = nil) throws {
        let day = LogicalDay.key(for: result.endedAt, dayStartHour: dayStartHour())
        let pinky = KeyStats.pinkyCounts(from: result)
        let fingers = KeyStats.fingerCounts(from: result)
        let segments = result.mode == .course
            ? try? JSONEncoder().encode(SpeedSegments.split(text: result.text, timings: result.timings)) : nil
        context.insert(SessionRecord(
            mode: result.mode.rawValue, language: result.language.rawValue, lessonId: result.lessonId,
            startedAt: result.startedAt, endedAt: result.endedAt, logicalDay: day,
            activeSeconds: result.activeSeconds, chars: result.chars, errorCount: result.errorCount,
            cpm: result.cpm, accuracy: result.accuracy, completed: result.completed,
            hintLevel: result.hintLevel.rawValue, maxErrorStreak: result.maxErrorStreak,
            wrongKeystrokes: result.wrongKeystrokes, exerciseKind: result.exerciseKind?.rawValue,
            pinkyPresses: pinky.presses, pinkyErrors: pinky.errors, source: source,
            fingerPresses: FingerCounts.data(fingers.presses), fingerErrors: FingerCounts.data(fingers.errors),
            yoPresses: KeyStats.yoCorrect(from: result), stepIndex: result.stepIndex, planSlot: planSlot?.rawValue,
            textTraits: result.textTraits.union(TextTraits.connected(source: source)).rawValue,
            speedSegments: segments
        ))

        try updateDay(day, activeSeconds: result.activeSeconds, completed: result.completed,
                      language: result.language)

        if result.completed && result.mode != .rhythm { try recordErrorWords(result) }

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

    /// Заход игры «Ритм» (решения 8–9): сессия `rhythm` (скорости нет, `cpm` 0), день, статистика букв и `RhythmResult`.
    /// Статистика букв — как у обычного упражнения, но без времени (`ewmaMs` не трогается) и без сочетаний: в игре
    /// буквы идут по такту, а не по скорости пальцев. Новая строка буквы получает код клавиши из раскладки
    /// (`outcome.keyCodes`), а если кода нет — не создаётся; код существующей строки не меняется. Сессия и день
    /// «завершены» по `outcome.completed` (у бесконечного режима это и конец по здоровью), `RhythmResult.cleared` — по
    /// `outcome.cleared`, `bpm` бесконечного — бит последней оценённой ступени. Только меняет контекст, сохраняет `commit`.
    func recordRhythm(_ outcome: RhythmOutcome) throws {
        let day = LogicalDay.key(for: outcome.endedAt, dayStartHour: dayStartHour())
        let report = outcome.report
        context.insert(SessionRecord(
            mode: ExerciseMode.rhythm.rawValue, language: outcome.language.rawValue, lessonId: nil,
            startedAt: outcome.startedAt, endedAt: outcome.endedAt, logicalDay: day,
            activeSeconds: outcome.activeSeconds, chars: outcome.notes, errorCount: outcome.misses, cpm: 0,
            accuracy: report.accuracy, completed: outcome.completed, hintLevel: HintLevel.full.rawValue,
            maxErrorStreak: outcome.maxMissStreak, wrongKeystrokes: outcome.wrongKeystrokes, exerciseKind: nil,
            source: "rhythm:\(outcome.mode.rawValue)", fingerPresses: FingerCounts.data(outcome.fingerPresses),
            fingerErrors: FingerCounts.data(outcome.fingerErrors), textTraits: 0))

        try updateDay(day, activeSeconds: outcome.activeSeconds, completed: outcome.completed, language: outcome.language)

        for (character, misses) in outcome.keySamples {
            let language = outcome.language.rawValue
            let stat: KeyStat
            if let existing = try existingKeyStat(language: language, character: String(character)) {
                stat = existing   // код клавиши уже записан тренировками: не перезаписывается
            } else if let code = outcome.keyCodes[character] {
                stat = KeyStat(language: language, character: String(character))
                stat.keyCode = Int(code)
                context.insert(stat)
            } else {
                // Клавиши для символа в раскладке нет: строка с `keyCode` 0 попала бы на физическую «A».
                continue
            }
            stat.presses += misses.count
            stat.errors += misses.filter { $0 }.count
            stat.recent = KeyStats.appendRecent(stat.recent, misses)
        }

        context.insert(RhythmResult(
            language: outcome.language.rawValue, mode: outcome.mode.rawValue, level: outcome.level.id.rawValue,
            bpm: Self.beatBPM(of: outcome), startedAt: outcome.startedAt, endedAt: outcome.endedAt, score: outcome.score,
            accuracy: report.accuracy, maxCombo: outcome.maxCombo, grade: report.grade.rawValue,
            cleared: outcome.cleared, judgements: Self.json(report.counts), report: Self.json(report)))
    }

    /// Темп бита записи: у обычного уровня — его `bpm`, у бесконечного — бит последней оценённой ступени.
    private static func beatBPM(of outcome: RhythmOutcome) -> Int {
        guard outcome.level.id == .endless, let peak = outcome.report.peakNotesPerMinute else {
            return outcome.level.bpm
        }
        return RhythmEndless.beatBPM(notesPerMinute: peak)
    }

    private static func json<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Словарь строк и чисел и `RhythmReport` кодируются всегда.
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
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

    /// Обновляет список «слов с ошибками» языка по целевому тексту (позиции ошибок — `timings[i].hadError`):
    /// вставляет, обновляет и удаляет записи, а исправленные слова добавляет к счётчику `fixedWords`.
    private func recordErrorWords(_ result: ExerciseResult) throws {
        var positions = Set<Int>()
        for (index, timing) in result.timings.enumerated() where timing.hadError { positions.insert(index) }
        let allowed = vocabulary(result.language)
        // Словарь не загрузился — ничего не трогаем, иначе уборка удалила бы весь список.
        guard !allowed.isEmpty else { return }
        let hits = ErrorWordTracker.hits(text: result.text, errorPositions: positions, vocabulary: allowed)
        let code = result.language.rawValue
        var stored: [ErrorWord] = []
        var byKey: [String: ErrorWord] = [:]
        for word in try context.fetch(FetchDescriptor<ErrorWord>(predicate: #Predicate { $0.language == code })) {
            // Уборка: фразы и записи не из словаря удаляются (исправленными не считаются).
            guard ErrorWordFilter.isAllowed(text: word.text, isPhrase: word.isPhrase, vocabulary: allowed) else {
                context.delete(word); continue
            }
            let key = Self.errorWordKey(word.text, word.isPhrase)
            // Дубликаты (например, из архива): остаётся первая запись, лишние удаляются.
            if byKey[key] == nil { byKey[key] = word; stored.append(word) } else { context.delete(word) }
        }
        let before = stored.map {
            ErrorWordEntry(text: $0.text, isPhrase: $0.isPhrase, errors: $0.errors, cleanStreak: $0.cleanStreak,
                           firstSeen: $0.firstSeen, lastSeen: $0.lastSeen)
        }
        guard !hits.isEmpty else { return }
        let (after, fixed) = ErrorWordBook.apply(hits, to: before, now: result.endedAt)
        var kept = Set<String>()
        for entry in after {
            let key = Self.errorWordKey(entry.text, entry.isPhrase)
            kept.insert(key)
            if let word = byKey[key] {
                word.errors = entry.errors; word.cleanStreak = entry.cleanStreak
                word.firstSeen = entry.firstSeen; word.lastSeen = entry.lastSeen
            } else {
                context.insert(ErrorWord(language: code, text: entry.text, isPhrase: entry.isPhrase,
                                         errors: entry.errors, cleanStreak: entry.cleanStreak,
                                         firstSeen: entry.firstSeen, lastSeen: entry.lastSeen))
            }
        }
        for word in stored where !kept.contains(Self.errorWordKey(word.text, word.isPhrase)) { context.delete(word) }
        if fixed > 0 { try increment(CounterName.fixedWords, by: fixed) }
    }

    private static func errorWordKey(_ text: String, _ isPhrase: Bool) -> String { (isPhrase ? "p:" : "w:") + text }

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

    /// Общая часть записи любого упражнения: время, число упражнений, язык и цель дня.
    private func updateDay(_ key: String, activeSeconds: Double, completed: Bool, language: Language) throws {
        let dayRecord = try fetchOrCreateDay(key)
        // День следует текущей цели, пока в нём занимаются; после — остаётся с целью последней записи.
        dayRecord.goalSeconds = goalSeconds()
        dayRecord.activeSeconds += activeSeconds
        if completed { dayRecord.completedExercises += 1 } else { dayRecord.abandonedExercises += 1 }
        if !dayRecord.languages.contains(language.rawValue) {
            dayRecord.languages.append(language.rawValue)
        }
    }

    private func fetchOrCreateDay(_ key: String) throws -> DayRecord {
        let descriptor = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.logicalDay == key })
        if let existing = try context.fetch(descriptor).first { return existing }
        let created = DayRecord(logicalDay: key)
        context.insert(created)
        return created
    }

    private func existingKeyStat(language: String, character: String) throws -> KeyStat? {
        let descriptor = FetchDescriptor<KeyStat>(
            predicate: #Predicate { $0.language == language && $0.character == character })
        return try context.fetch(descriptor).first
    }

    private func fetchOrCreateKeyStat(language: String, character: String) throws -> KeyStat {
        if let existing = try existingKeyStat(language: language, character: character) { return existing }
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
