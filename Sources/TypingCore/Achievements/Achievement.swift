import Foundation

public enum AchievementCategory: String, CaseIterable, Sendable {
    case streak, speed, accuracy, course, volume, special, letters, fun
}

/// Условие получения ачивки; проверяет `AchievementEngine` по фактам из истории.
/// Точность — доля от 0 до 1, как `ExerciseResult.accuracy`.
public enum AchievementCondition: Equatable, Sendable {
    /// Текущая серия достигала N дней.
    case streak(days: Int)
    /// N полных дней подряд без заморозок.
    case fullStreakNoFreeze(days: Int)
    /// Подходящее упражнение (завершённая проверка урока или завершённое упражнение ≥ 300 знаков) на языке
    /// без единой ошибки (точность 100%) с cpm ≥ N.
    case speed(Language, cpm: Int)
    /// 100% на подходящем упражнении (завершённая проверка урока или завершённое упражнение ≥ 300 знаков).
    case perfectAccuracy
    /// N завершённых упражнений подряд с точностью ≥ minimum.
    case accuracyRun(count: Int, minimum: Double)
    /// Логический день: ≥ N упражнений, все с точностью ≥ minimum.
    case cleanDay(exercises: Int, minimum: Double)
    case firstLesson, firstStage
    case courseCompleted(Language), polyglot
    /// Все уроки курса языка на ★★★ (по `LessonScoring.effectiveStars`).
    case allThreeStars(Language)
    case volumeChars(Int), volumeHours(Double)
    /// Локальное время завершения упражнения в [startHour, endHour).
    case finishedBetween(startHour: Int, endHour: Int)
    /// Подходящее упражнение (завершённая проверка урока или завершённое упражнение ≥ 300 знаков)
    /// с `HintLevel.hidden`.
    case noKeyboard
    /// ≥ N нажатий мизинцами и ни одной ошибки мизинцами в одном упражнении.
    case steelPinkies(presses: Int)
    /// Открыты все перечисленные буквы языка (курс + адаптивный режим, см. §21).
    case lettersUnlocked(Language, Set<Character>)
    /// Открыт весь алфавит языка.
    case wholeAlphabet(Language)
    /// Счётчик приложения (`CounterName`) достиг порога.
    case counter(name: String, threshold: Int)
    /// `maxErrorStreak` ≥ N в одном упражнении.
    case errorStreak(Int)
    /// `wrongKeystrokes` ≥ N в одном упражнении.
    case errorsInExercise(Int)
    /// Попыток одного урока ≥ N.
    case lessonReplays(Int)
    /// Брошенных упражнений за логический день ≥ N.
    case abandonsInDay(Int)
    case dayOfYear(month: Int, day: Int)
    case fridayThe13th
    /// Упражнения на обоих языках за один логический день.
    case bilingualDay
    /// Минут чистой практики за логический день ≥ N.
    case marathonDay(minutes: Int)
    /// Занятие после перерыва ≥ N дней.
    case comeback(gapDays: Int)
}

public struct Achievement: Identifiable, Equatable, Sendable {
    /// Стабильный id, никогда не переименовывать: по нему хранятся полученные ачивки.
    /// Ключи перевода — `achievement.<id>.title` и `achievement.<id>.detail`.
    public let id: String
    public let category: AchievementCategory
    /// Имя SF Symbol.
    public let icon: String
    /// «Взрослый юмор»: при выключенной настройке скрывается, но выдаётся.
    public let adult: Bool
    public let condition: AchievementCondition
    /// Только у `lettersUnlocked`: слово или команда, из которых набрано условие («пицца», «:q!»); по нему буквы
    /// в тексте условия идут в естественном порядке. Множество в условии порядка не хранит.
    public let lettersDisplay: String?

    public init(id: String, category: AchievementCategory, icon: String, adult: Bool = false,
                condition: AchievementCondition, lettersDisplay: String? = nil) {
        self.id = id
        self.category = category
        self.icon = icon
        self.adult = adult
        self.condition = condition
        self.lettersDisplay = lettersDisplay
    }

    public var titleKey: String { "achievement.\(id).title" }
    public var detailKey: String { "achievement.\(id).detail" }

    /// Название на языке системы.
    public var title: String { CoreText.localized(titleKey) }
    /// Описание на языке системы: условие человеческими словами, у «Теперь вы можете…» — шутка из §12.
    public var detail: String { CoreText.localized(detailKey) }
}
