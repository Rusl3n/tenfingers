import Foundation
import TypingCore

/// Число открытых букв после порции: перечитывается из хранилища внутри транзакции записи
/// и никогда не уменьшается (даже если прежнее чтение при старте порции не удалось).
/// Каждая новая буква записывается в `AdaptiveUnlock` с датой `date`.
enum AdaptiveProgress {
    @MainActor @discardableResult
    static func record(recorder: ResultRecorder, trainer: AdaptiveTrainer,
                       language: Language, at date: Date = Date()) throws -> (before: Int, after: Int) {
        let reader = StatsReader(context: recorder.context)
        let stored = try reader.unlockedCount(language: language)
        let stats = try reader.keyMastery(language: language)
        let next = max(stored, trainer.nextUnlockedCount(current: stored, stats: stats))
        try recorder.recordAdaptive(language: language, unlockedCount: next)
        let opened = trainer.unlockedLetters(count: stored).count
        for letter in trainer.unlockedLetters(count: next).dropFirst(opened) {
            recorder.recordUnlock(language: language, letter: letter, at: date)
        }
        return (stored, next)
    }
}
