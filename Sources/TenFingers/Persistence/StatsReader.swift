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

    func unlockedCount(language: Language) throws -> Int {
        let code = language.rawValue
        let descriptor = FetchDescriptor<AdaptiveState>(predicate: #Predicate { $0.language == code })
        return try context.fetch(descriptor).first?.unlockedCount ?? AdaptiveTrainer.initialLetters
    }

    /// Буквы, открытые пользователем: в курсе и в адаптивной тренировке (см. `OpenLetters`).
    func openLetters(language: Language, course: Course?) throws -> Set<Character> {
        let code = language.rawValue
        let progress = try context.fetch(FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.language == code }))
        let passed = Set(progress.filter { $0.passedAt != nil }.map(\.lessonId))
        return OpenLetters.combine(language: language, course: course, passedLessonIds: passed,
                                   adaptiveCount: try unlockedCount(language: language))
    }

    /// Доля ошибок по последним нажатиям (`recent`), а если их нет — по всем.
    private static func errorRate(recent: [Bool], errors: Int, total: Int) -> Double {
        if !recent.isEmpty { return Double(recent.filter { $0 }.count) / Double(recent.count) }
        return total > 0 ? Double(errors) / Double(total) : 0
    }
}

/// Буквы, которые пользователь уже открыл. Курс: все буквы до последнего пройденного урока
/// (в порядке курса). Адаптивная тренировка: открытые в ней буквы (не меньше стартовых шести).
enum OpenLetters {
    /// Меньше стольких открытых букв — «Слабые места» не запускаются: слов из них почти нет.
    static let minimumForWeakSpots = 8

    static func combine(language: Language, course: Course?, passedLessonIds: Set<String>,
                        adaptiveCount: Int) -> Set<Character> {
        var result = Set(AdaptiveTrainer(language: language).unlockedLetters(count: adaptiveCount))
        if let course, let last = course.lessons.last(where: { passedLessonIds.contains($0.id) }),
           let lesson = course.context(for: last.id) {
            for character in lesson.allowed {
                let lowered = Character(String(character).lowercased())
                if language.letters.contains(lowered) { result.insert(lowered) }
            }
        }
        return result
    }
}
