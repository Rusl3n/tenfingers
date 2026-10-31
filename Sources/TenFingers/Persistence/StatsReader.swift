import Foundation
import SwiftData
import TypingCore

/// Читает накопленную статистику и приводит её к виду, понятному ядру тренировки.
@MainActor
struct StatsReader {
    let context: ModelContext

    func keyMastery(language: Language) throws -> [Character: KeyMastery] {
        let code = language.rawValue
        let stats = try context.fetch(FetchDescriptor<KeyStat>(predicate: #Predicate { $0.language == code }))
        // Заглавные и строчные считаются одной клавишей: строки статистики сливаются по строчному символу.
        var merged: [Character: [KeyStat]] = [:]
        for stat in stats {
            guard stat.character.count == 1, let character = stat.character.first else { continue }
            let lowered = String(character).lowercased()
            let key = lowered.count == 1 ? Character(lowered) : character
            merged[key, default: []].append(stat)
        }
        var result: [Character: KeyMastery] = [:]
        for (character, group) in merged {
            let presses = group.reduce(0) { $0 + $1.presses }
            let errors = group.reduce(0) { $0 + $1.errors }
            let timed = group.compactMap { stat in stat.ewmaMs.map { (ms: $0, weight: Double(max(stat.presses, 1))) } }
            let weight = timed.reduce(0) { $0 + $1.weight }
            let ewma = weight > 0 ? timed.reduce(0) { $0 + $1.ms * $1.weight } / weight : nil
            // Строчная строка идёт первой: так порядок `recent` не зависит от порядка выборки.
            let ordered = group.sorted { lhs, _ in lhs.character == String(character) }
            let recent = Array(ordered.flatMap(\.recent).suffix(KeyStats.recentWindow))
            result[character] = KeyMastery(ewmaMs: ewma,
                                           errorRate: Self.errorRate(recent: recent, errors: errors, total: presses),
                                           presses: presses)
        }
        return result
    }

    func bigramMastery(language: Language) throws -> [String: KeyMastery] {
        let code = language.rawValue
        let stats = try context.fetch(FetchDescriptor<BigramStat>(predicate: #Predicate { $0.language == code }))
        var result: [String: KeyMastery] = [:]
        for stat in stats {
            result[stat.bigram] = KeyMastery(ewmaMs: stat.ewmaMs,
                                             errorRate: Self.errorRate(recent: stat.recent, errors: stat.errors,
                                                                       total: stat.count),
                                             presses: stat.count)
        }
        return result
    }

    /// Статистика клавиш и сочетаний для планировщика: «Повтор», «Ускорение» и шаги `focus` строятся по ней.
    /// `course` — курс издания 2 языка: по нему считаются буквы «трудных» уроков (вес ×2 в «Повторе»); без курса
    /// (издание 1, тренировки) их нет.
    func learnerStats(language: Language, course: Course? = nil, now: Date = .now,
                      dayStartHour: Int = StoredSettings.dayStartHour(), calendar: Calendar = .current) throws -> LearnerStats {
        var hard = Set<Character>()
        if let course, course.edition >= 2 {
            let today = LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar)
            hard = try ProgressSnapshot(context: context).hardLetters(course: course, today: today,
                                                                      dayStartHour: dayStartHour, calendar: calendar)
        }
        return LearnerStats(keys: try keyMastery(language: language), bigrams: try bigramMastery(language: language),
                            hardLetters: hard)
    }

    /// Время и нажатия каждой клавиши курса: буква → (`ewmaMs`, нажатия). Клавиши без времени пропускаются.
    func keyEwma(language: Language) throws -> [Character: (ms: Double, presses: Int)] {
        var result: [Character: (ms: Double, presses: Int)] = [:]
        for (letter, mastery) in try keyMastery(language: language) {
            if let ms = mastery.ewmaMs { result[letter] = (ms: ms, presses: mastery.presses) }
        }
        return result
    }

    /// Буква → палец языка: по коду клавиши в истории (`KeyStat.keyCode`), раскладка `layout` — запасом для букв без
    /// истории. От активной раскладки основная карта не зависит.
    func fingerLetters(language: Language, layout: [Character: Finger]) throws -> [Character: Finger] {
        let code = language.rawValue
        let stats = try context.fetch(FetchDescriptor<KeyStat>(predicate: #Predicate { $0.language == code }))
        return FingerTraining.letterFingers(
            keys: stats.map { (character: $0.character, keyCode: $0.keyCode, presses: $0.presses) },
            language: language, fallback: layout)
    }

    /// Нажатия и ошибки пальцев за `days` логических дней по `today` включительно (поля сессий `fingerPresses` и
    /// `fingerErrors`; у сессий без них пальцы не учитываются).
    func fingerTotals(language: Language, days: Int,
                      today: String) throws -> (presses: [Finger: Int], errors: [Finger: Int]) {
        let code = language.rawValue
        let start = StreakCalculator.dayKey(today, offset: -(days - 1))
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.language == code && $0.logicalDay >= start && $0.logicalDay <= today }))
        var presses: [Finger: Int] = [:], errors: [Finger: Int] = [:]
        for session in sessions {
            for (finger, count) in FingerCounts.counts(session.fingerPresses) ?? [:] where finger != .thumb {
                presses[finger, default: 0] += count
            }
            for (finger, count) in FingerCounts.counts(session.fingerErrors) ?? [:] where finger != .thumb {
                errors[finger, default: 0] += count
            }
        }
        return (presses, errors)
    }

    /// Оценка пальцев за `FingerTraining.days` дней: нажатия сессий, скорость клавиш и буквы пальцев по истории клавиш (запасом — раскладка) (§6.4).
    func fingerReports(language: Language, fingerOf: [Character: Finger], thresholdMs: Double, now: Date = .now,
                       dayStartHour: Int = StoredSettings.dayStartHour(),
                       calendar: Calendar = .current) throws -> [FingerReport] {
        try fingerReports(language: language, fingerOf: fingerOf, thresholdMs: thresholdMs,
                          today: LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar))
    }

    /// То же на логический день `today` (план дня).
    func fingerReports(language: Language, fingerOf: [Character: Finger], thresholdMs: Double,
                       today: String) throws -> [FingerReport] {
        let totals = try fingerTotals(language: language, days: FingerTraining.days, today: today)
        return FingerTraining.reports(presses: totals.presses, errors: totals.errors,
                                      keyEwma: try keyEwma(language: language), fingerOf: fingerOf,
                                      thresholdMs: thresholdMs)
    }

    func unlockedCount(language: Language) throws -> Int {
        let code = language.rawValue
        let descriptor = FetchDescriptor<AdaptiveState>(predicate: #Predicate { $0.language == code })
        return try context.fetch(descriptor).first?.unlockedCount ?? AdaptiveTrainer.initialLetters
    }

    /// Буквы, открытые пользователем: в курсах обоих изданий (текущем и архиве `legacy`) и в адаптивной
    /// тренировке (см. `OpenLetters`).
    func openLetters(language: Language, course: Course?, legacy: Course?) throws -> Set<Character> {
        let code = language.rawValue
        let progress = try context.fetch(FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.language == code }))
        let passed = Set(progress.filter { $0.passedAt != nil }.map(\.lessonId))
        return OpenLetters.combine(language: language, course: course, legacy: legacy, passedLessonIds: passed,
                                   adaptiveCount: try unlockedCount(language: language))
    }

    /// Доля ошибок по последним нажатиям (`recent`), а если их нет — по всем.
    private static func errorRate(recent: [Bool], errors: Int, total: Int) -> Double {
        if !recent.isEmpty { return Double(recent.filter { $0 }.count) / Double(recent.count) }
        return total > 0 ? Double(errors) / Double(total) : 0
    }
}

/// Буквы, которые пользователь уже открыл. Курс: все буквы до последнего пройденного урока
/// (в порядке курса); курсы обоих изданий — объединение, так буквы прежнего курса остаются открытыми.
/// Адаптивная тренировка: открытые в ней буквы (не меньше стартовых шести).
enum OpenLetters {
    /// Меньше стольких открытых букв — «Слабые места» не запускаются: слов из них почти нет.
    static let minimumForWeakSpots = 8

    static func combine(language: Language, course: Course?, legacy: Course? = nil, passedLessonIds: Set<String>,
                        adaptiveCount: Int) -> Set<Character> {
        var result = Set(AdaptiveTrainer(language: language).unlockedLetters(count: adaptiveCount))
        for course in [course, legacy].compactMap({ $0 }) {
            guard let last = course.lessons.last(where: { passedLessonIds.contains($0.id) }),
                  let lesson = course.context(for: last.id) else { continue }
            for character in lesson.allowed {
                let lowered = Character(String(character).lowercased())
                if language.letters.contains(lowered) { result.insert(lowered) }
            }
        }
        return result
    }
}
