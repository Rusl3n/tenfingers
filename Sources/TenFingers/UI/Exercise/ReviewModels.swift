import Foundation
import TypingCore

/// Разбор шага на промежуточном экране и итоге повтора шага (§2.2): строки правил и данные мини-графика.
struct StepReviewScreen: Equatable {
    /// «Хорошее», затем «что мешало» (строка допуска показывается отдельно, `StepInterim.toleranceLine`).
    let lines: [ReviewLine]
    /// `nil` — отрезков нет (запись без них): график скрыт.
    let segments: [SpeedSegment]?
    /// Индексы медленных отрезков (выделяются цветом).
    let slow: [Int]
    /// Целевой текст шага: по нему подсказка графика показывает слова отрезка.
    let text: String

    /// График — от двух отрезков: по одному полосе сравнивать не с чем.
    var showsChart: Bool { (segments?.count ?? 0) >= 2 }

    static func make(text: String, result: ExerciseResult, targetCpm: Double?,
                     segments: [SpeedSegment]?) -> StepReviewScreen {
        let review = ExerciseReview.step(text: text, result: result, targetCpm: targetCpm, segments: segments ?? [])
        return StepReviewScreen(lines: [review.good].compactMap { $0 } + review.trouble, segments: segments,
                                slow: SpeedSegments.slow(segments ?? []), text: text)
    }
}

extension SpeedSegment {
    /// Слова отрезка в целевом тексте (без крайних пробелов); `nil` — отрезок не помещается в текст.
    func words(in text: String) -> String? {
        let chars = Array(text)
        guard start >= 0, end <= chars.count, start < end else { return nil }
        let words = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? nil : words
    }
}

/// Запись шага текущего прохода урока: то, что нужно разбору урока (значение вместо `SessionRecord`).
struct PassRecord: Equatable {
    let stepIndex: Int
    let startedAt: Date
    let completed: Bool
    let cpm: Double
    let errorCount: Int
    let fingerPresses: [Finger: Int]
    let fingerErrors: [Finger: Int]
    let segments: [SpeedSegment]?

    init(stepIndex: Int, startedAt: Date, completed: Bool, cpm: Double, errorCount: Int,
         fingerPresses: [Finger: Int], fingerErrors: [Finger: Int], segments: [SpeedSegment]?) {
        self.stepIndex = stepIndex
        self.startedAt = startedAt
        self.completed = completed
        self.cpm = cpm
        self.errorCount = errorCount
        self.fingerPresses = fingerPresses
        self.fingerErrors = fingerErrors
        self.segments = segments
    }

    /// `nil` для записи без номера шага (до поколения 6) и не из курса.
    init?(_ record: SessionRecord) {
        guard record.mode == ExerciseMode.course.rawValue, let step = record.stepIndex else { return nil }
        self.init(stepIndex: step, startedAt: record.startedAt, completed: record.completed, cpm: record.cpm,
                  errorCount: record.errorCount, fingerPresses: FingerCounts.counts(record.fingerPresses) ?? [:],
                  fingerErrors: FingerCounts.counts(record.fingerErrors) ?? [:],
                  segments: record.decodedSpeedSegments)
    }
}

/// Разбор урока на его итоге (§2.3): шаги ТЕКУЩЕГО прохода, график, «Получилось», «Подтянуть», «Куда дальше».
struct LessonReviewModel: Equatable {
    struct StepSpeed: Equatable {
        let index: Int
        let cpm: Double
    }

    /// Средняя скорость по шагам прохода (по номеру шага).
    let stepSpeeds: [StepSpeed]
    /// Отрезки итогового (последнего) шага; `nil` — их нет.
    let finalSegments: [SpeedSegment]?
    let review: LessonReview

    /// `records` — записи этого урока (любые; лишние отбираются). Проход: шаги до `resumeStart` — пройденные раньше
    /// (продолжение `LessonResume`), берётся последняя завершённая запись; остальные — только начатые не раньше
    /// `passStart`, тоже последняя на шаг (повтор шага заменяет прежнюю попытку). `letters` — ошибки по буквам
    /// шагов (в базе их нет, держит раннер; после перезапуска приложения посреди урока ранних шагов в них нет).
    static func make(records: [PassRecord], letters: [Int: [Character: Int]], resumeStart: Int,
                     passStart: Date) -> LessonReviewModel {
        var latest: [Int: PassRecord] = [:]
        for record in records where record.completed {
            guard record.stepIndex < resumeStart || record.startedAt >= passStart else { continue }
            if let known = latest[record.stepIndex], known.startedAt >= record.startedAt { continue }
            latest[record.stepIndex] = record
        }
        let steps = latest.values.sorted { $0.stepIndex < $1.stepIndex }
        var presses: [Finger: Int] = [:], wrong: [Finger: Int] = [:]
        for step in steps {
            presses.merge(step.fingerPresses, uniquingKeysWith: +)
            wrong.merge(step.fingerErrors, uniquingKeysWith: +)
        }
        let review = ExerciseReview.lesson(
            steps: steps.map {
                LessonStepSummary(stepIndex: $0.stepIndex, cpm: $0.cpm, errorCount: $0.errorCount,
                                  errorsByCharacter: letters[$0.stepIndex] ?? [:])
            },
            fingerPresses: presses, fingerErrors: wrong, errorWordsAvailable: false)
        return LessonReviewModel(stepSpeeds: steps.map { StepSpeed(index: $0.stepIndex, cpm: $0.cpm) },
                                 finalSegments: steps.last?.segments, review: review)
    }
}

/// Куда ведёт рекомендация «Куда дальше»: тот же запуск, что у карточки раздела.
enum ReviewDestination {
    /// «Пальцы» с этим пальцем (занятие на точность, как кнопка карточки), «Слабые места», следующий урок.
    /// `.errorWords` в 8a не возникает; следующего урока нет — `nil` (кнопки нет).
    static func run(for advice: ReviewAdvice, language: Language, next: LessonRun?) -> RunKind? {
        switch advice {
        case .finger(let finger): .finger(FingerRun(language: language, finger: finger, drill: .accuracy))
        case .weakSpots: .weakSpots(TrainingRun(language: language))
        case .nextLesson: next.map { .lesson($0) }
        case .errorWords: nil
        }
    }

    static func title(for advice: ReviewAdvice) -> String? {
        switch advice {
        case .finger(let finger): String(localized: "Тренировать: \(finger.displayName)")
        case .weakSpots: String(localized: "Слабые места")
        case .nextLesson: String(localized: "Следующий урок")
        case .errorWords: nil
        }
    }
}

/// Строка разбора (`ReviewLine`) → текст на языке интерфейса.
enum ReviewText {
    /// `template` — перевод ключа (по умолчанию из бандла приложения); единственный `%@` — аргументы через запятую.
    static func text(_ line: ReviewLine, template: String? = nil) -> String {
        let template = template ?? Bundle.main.localizedString(forKey: line.key, value: line.key, table: nil)
        return String(format: template, line.args.joined(separator: ", "))
    }
}
