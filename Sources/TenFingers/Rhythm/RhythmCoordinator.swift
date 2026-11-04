import Foundation
import SwiftData
import TypingCore

/// Запуск игры «Ритм»: новый `id` на каждый запуск (по нему пересоздаётся экран).
struct RhythmRun: Identifiable, Equatable {
    let id = UUID()
    let language: Language
    let mode: RhythmNoteMode
    let level: RhythmLevelID
    let style: RhythmBeatStyle
}

/// Жизненный цикл захода: набор нот и расстановка, запись результата (тем же путём и с тем же алертом, что у
/// упражнений), рекорды и скорость для уровня «Под меня».
@MainActor
final class RhythmCoordinator {
    typealias Unavailable = RhythmNoteSource.Unavailable

    /// Последние завершённые сессии языка, по которым берётся скорость для «Под меня» (решение 4).
    static let personalSessions = 10
    /// Короче — сессия не показывает скорость.
    static let personalMinChars = 100
    /// Меньше нажатий — доля ошибок буквы не оценивается (решение 2).
    static let errorRateMinPresses = 5

    /// Сохранение, алерт ошибки (`saveErrorAlert`), ачивки, год и напоминания — как у упражнений.
    let saver: ExerciseCoordinator
    private let context: ModelContext
    private let openLetters: @MainActor (Language) -> Set<Character>
    private let fingers: @MainActor (Language) -> [Character: Finger]
    private let words: @MainActor (Language) -> [String]
    private let targetCpm: @MainActor () -> Double
    private let seed: @MainActor () -> UInt64
    /// Код клавиши символа в текущей раскладке (для новых строк статистики букв); `nil` — в раскладке нет.
    private let keyCode: @MainActor (Character) -> UInt16?

    init(saver: ExerciseCoordinator, context: ModelContext,
         openLetters: @escaping @MainActor (Language) -> Set<Character>,
         fingers: @escaping @MainActor (Language) -> [Character: Finger],
         words: @escaping @MainActor (Language) -> [String],
         targetCpm: @escaping @MainActor () -> Double,
         seed: @escaping @MainActor () -> UInt64 = { UInt64.random(in: UInt64.min...UInt64.max) },
         keyCode: @escaping @MainActor (Character) -> UInt16? = { _ in nil }) {
        self.saver = saver
        self.context = context
        self.openLetters = openLetters
        self.fingers = fingers
        self.words = words
        self.targetCpm = targetCpm
        self.seed = seed
        self.keyCode = keyCode
    }

    /// Координатор приложения: те же зависимости, что у `ExerciseCoordinator.live`, плюс библиотека курсов и
    /// раскладка (открытые буквы, слова и пальцы букв).
    static func live(context: ModelContext, sound: SoundPlayer, toasts: ToastCenter,
                     reminders: ReminderScheduler? = nil, library: ContentLibrary,
                     layout: KeyboardLayoutService) -> RhythmCoordinator {
        let saver = ExerciseCoordinator.live(context: context, sound: sound, toasts: toasts, reminders: reminders)
        let reader = StatsReader(context: context)
        return RhythmCoordinator(
            saver: saver, context: context,
            openLetters: { language in
                (try? reader.openLetters(language: language, course: library.courses[language],
                                         legacy: library.legacyCourses[language]))
                    ?? Set(AdaptiveTrainer(language: language).unlockedLetters(count: AdaptiveTrainer.initialLetters))
            },
            fingers: { language in
                let current = layout.fingerOf(language: language)
                return (try? reader.fingerLetters(language: language, layout: current)) ?? current
            },
            words: { library.planners[$0]?.generator.wordList.words ?? [] },
            targetCpm: {
                Double(UserDefaults.standard.object(forKey: SettingsKey.adaptiveTargetCpm) as? Int
                    ?? SettingsDefault.adaptiveTargetCpm)
            },
            keyCode: { layout.snapshot.keyPress(for: $0)?.keyCode })
    }

    // MARK: - Набор нот

    /// Всё, из чего собираются наборы нот всех режимов языка.
    struct Inputs {
        let open: Set<Character>
        let fingers: [Character: Finger]
        let weak: [Character]
        let errorRates: [Character: Double]
        let words: [String]
    }

    func inputs(for language: Language) -> Inputs {
        let open = openLetters(language)
        let mastery = (try? StatsReader(context: context).keyMastery(language: language)) ?? [:]
        let trainer = AdaptiveTrainer(language: language, targetCpm: targetCpm())
        let weak = WeakSpots.worstKeys(mastery.filter { open.contains($0.key) }, thresholdMs: trainer.thresholdMs,
                                       limit: RhythmNoteSource.maxProblemLetters)
        return Inputs(open: open, fingers: fingers(language), weak: weak, errorRates: errorRates(language: language),
                      words: words(language))
    }

    /// Доля ошибок буквы: `KeyStat.errors / presses`, только с достаточным числом нажатий (строчные и заглавные вместе).
    private func errorRates(language: Language) -> [Character: Double] {
        let code = language.rawValue
        let stats = (try? context.fetch(FetchDescriptor<KeyStat>(predicate: #Predicate { $0.language == code }))) ?? []
        var totals: [Character: (presses: Int, errors: Int)] = [:]
        for stat in stats {
            guard stat.character.count == 1, let character = stat.character.lowercased().first else { continue }
            let sum = totals[character] ?? (0, 0)
            totals[character] = (sum.presses + stat.presses, sum.errors + stat.errors)
        }
        return totals.filter { $0.value.presses >= Self.errorRateMinPresses }
            .mapValues { Double($0.errors) / Double($0.presses) }
    }

    func source(mode: RhythmNoteMode, language: Language, inputs: Inputs) throws(Unavailable) -> RhythmNoteSource {
        try RhythmNoteSource.make(mode: mode, language: language, open: inputs.open, weak: inputs.weak,
                                  errorRates: inputs.errorRates, words: inputs.words, fingers: inputs.fingers)
    }

    /// Режимы, для которых нот нет, и причина; доступного режима в словаре нет.
    func availability(language: Language) -> [RhythmNoteMode: Unavailable] {
        let inputs = inputs(for: language)
        var result: [RhythmNoteMode: Unavailable] = [:]
        for mode in RhythmNoteMode.allCases {
            do throws(Unavailable) {
                _ = try source(mode: mode, language: language, inputs: inputs)
            } catch {
                result[mode] = error
            }
        }
        return result
    }

    /// Короткая причина недоступности режима для экрана выбора.
    nonisolated static func reason(_ unavailable: Unavailable, mode: RhythmNoteMode) -> String {
        switch unavailable {
        case .tooFewLetters:
            mode == .closed ? String(localized: "Все буквы уже открыты") : String(localized: "Пока мало открытых букв")
        case .tooFewWords: String(localized: "Мало слов из открытых букв")
        case .noStats: String(localized: "Нет статистики букв")
        }
    }

    // MARK: - Уровень «Под меня»

    /// Скорость печати для «Под меня»: медиана `cpm` последних 10 завершённых сессий языка не из игры и не короче
    /// 100 знаков (решение 4); нет таких сессий — `nil`.
    func personalCpm(language: Language) -> Double? {
        let code = language.rawValue
        let rhythm = ExerciseMode.rhythm.rawValue
        let minChars = Self.personalMinChars
        var descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.language == code && $0.mode != rhythm && $0.completed && $0.chars >= minChars },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        descriptor.fetchLimit = Self.personalSessions
        let sessions = (try? context.fetch(descriptor)) ?? []
        return Self.median(sessions.map(\.cpm))
    }

    nonisolated static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Уровень по id: «Под меня» — по скорости печати, остальные (и бесконечный) — готовые.
    func level(for id: RhythmLevelID, language: Language) -> RhythmLevel {
        id == .personal ? .personal(cpm: personalCpm(language: language)) : .preset(id)
    }

    // MARK: - Заход

    /// Расстановка нот нового захода (зерно — случайное на каждый заход) и карта «символ → палец» раскладки языка.
    func prepare(run: RhythmRun) throws(Unavailable) -> (RhythmChart, [Character: Finger]) {
        let inputs = inputs(for: run.language)
        let source = try source(mode: run.mode, language: run.language, inputs: inputs)
        let chart = RhythmChartBuilder.build(source: source, level: level(for: run.level, language: run.language),
                                             fingers: inputs.fingers, seed: seed())
        return (chart, inputs.fingers)
    }

    /// Итог захода для записи. Время конца и `uptime` (шкала `systemUptime`) задают активное время по часам.
    private func outcome(game: RhythmGame, chart: RhythmChart, run: RhythmRun, clock: RhythmClock, startedAt: Date,
                         uptime: TimeInterval, now: Date) -> RhythmOutcome {
        RhythmOutcome.make(
            game: game, chart: chart, source: RhythmNoteSource(mode: run.mode, letters: []), language: run.language,
            startedAt: startedAt, endedAt: now, activeSeconds: clock.activeSeconds(at: uptime),
            fingers: fingers(run.language),
            keyCodes: Dictionary(chart.notes.compactMap { note in keyCode(note.character).map { (note.character, $0) } },
                                 uniquingKeysWith: { first, _ in first }))
    }

    /// Итог `finish`: сохранено (запись — если её удалось прочитать; экран итога от неё не зависит) или не удалось —
    /// тогда показан алерт «Повторить» / «Отмена» (`saver.onRetrySucceeded`, `saver.onSaveCancelled`).
    enum FinishOutcome {
        case saved(RhythmResult?)
        case failed

        var result: RhythmResult? {
            if case .saved(let result) = self { result } else { nil }
        }
    }

    /// Конец захода (пройден или проигран): сохраняет. Заход без оценённых нот не пишется (`.saved(nil)`).
    /// `wrongLayoutAttempted` — была попытка ввода в чужой раскладке: счётчик `wrongLayoutStarts` (как у упражнений).
    func finish(game: RhythmGame, chart: RhythmChart, run: RhythmRun, clock: RhythmClock, startedAt: Date,
                wrongLayoutAttempted: Bool = false,
                uptime: TimeInterval = ProcessInfo.processInfo.systemUptime, now: Date = .now) -> FinishOutcome {
        guard !game.outcomes.isEmpty else { return .saved(nil) }
        let result = outcome(game: game, chart: chart, run: run, clock: clock, startedAt: startedAt, uptime: uptime,
                             now: now)
        guard saver.recordRhythm(result, wrongLayoutAttempted: wrongLayoutAttempted, how: .finished) else {
            return .failed
        }
        return .saved(storedResult(language: run.language))
    }

    /// Прерванный заход (решение 11): пишется, только если оценена хотя бы одна нота; счётчик чужой раскладки
    /// пишется всегда. `interactive` — кнопка «Выйти»: ошибка сохранения покажет алерт, после него
    /// `saver.onExitAfterAlert`; `false` — молча. `true` в ответе — можно уходить сразу.
    @discardableResult
    func abandon(game: RhythmGame, chart: RhythmChart, run: RhythmRun, clock: RhythmClock, startedAt: Date,
                 wrongLayoutAttempted: Bool = false, interactive: Bool = false, quitting: Bool = false,
                 uptime: TimeInterval = ProcessInfo.processInfo.systemUptime, now: Date = .now) -> Bool {
        let result = game.outcomes.isEmpty ? nil
            : outcome(game: game, chart: chart, run: run, clock: clock, startedAt: startedAt, uptime: uptime, now: now)
        return saver.recordRhythm(result, wrongLayoutAttempted: wrongLayoutAttempted,
                                  how: interactive ? .exit : .silent(quitting: quitting))
    }

    /// Запись, только что сохранённая `finish`: самая свежая у языка (время конца — «сейчас»).
    private func storedResult(language: Language) -> RhythmResult? {
        let code = language.rawValue
        var descriptor = FetchDescriptor<RhythmResult>(predicate: #Predicate { $0.language == code },
                                                       sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Рекорды

    /// Все записи заходов; сочетание, «пройден» и язык отбирает `RhythmRecords`.
    private func allResults() -> [RhythmResult] {
        (try? context.fetch(FetchDescriptor<RhythmResult>())) ?? []
    }

    /// Рекорды сочетания по пройденным заходам; таких нет — `RhythmRecords.empty`.
    func records(language: Language, mode: RhythmNoteMode, level: RhythmLevelID) -> RhythmRecords {
        RhythmRecords.make(allResults(), language: language, mode: mode, level: level)
    }

    /// Рекорды бесконечного режима (время и очки) по всем заходам набора нот и языка.
    func endlessRecords(language: Language, mode: RhythmNoteMode) -> RhythmEndlessRecords {
        RhythmEndlessRecords.make(allResults(), language: language, mode: mode)
    }

    /// Последний пройденный заход сочетания поставил рекорд очков (отметка на экране выбора).
    func latestSetBest(language: Language, mode: RhythmNoteMode, level: RhythmLevelID) -> Bool {
        RhythmRecords.latestSetBest(allResults(), language: language, mode: mode, level: level)
    }
}
