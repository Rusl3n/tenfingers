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

    // Фаза 5 (спецификация фазы 5, §7.4 и решения §11).

    /// N-е завершённое упражнение (любой режим).
    case exercisesCompleted(Int)
    /// На каком-либо языке средний `cpm` завершённых упражнений за логические дни `[d−6, d]` ≥ factor × средний
    /// за первую неделю языка `[D0, D0+6]`; `d ≥ D0+13`, в обоих окнах ≥ minExercises упражнений.
    case speedGrowth(factor: Double, minExercises: Int)
    /// За логические дни `[d−(days−1), d]` у каждого пальца (`Finger.allCases`) ≥ presses нажатий и точность
    /// ≥ minimum. Только сессии со статистикой пальцев (с версии 1.1.0), в том числе брошенные.
    case allFingersAccuracy(minimum: Double, presses: Int, days: Int)
    /// count завершённых «Слабых мест» (`ExerciseMode.weak`) с точностью ≥ minimum.
    case weakSpotsClean(count: Int, minimum: Double)
    /// N разных отрывков из книг (`source` вида `library:<id>`), набранных до конца.
    case booksFinished(Int)
    /// Завершённое упражнение со своим текстом (`source == "custom"`).
    case ownText
    /// Все дни календарного месяца — `.full`.
    case fullFireMonth
    /// Заморозка, после которой (через одни заморозки) снова день с занятиями.
    case freezeSavedStreak
    /// Завершённое упражнение с округлённым `cpm` ровно cpm.
    case exactSpeed(cpm: Int)
    /// Завершённое упражнение с округлённым чистым временем ровно N секунд.
    case exactSeconds(Int)
    /// «Ё» без ошибки N раз: сессии (с 1.1.0) или `KeyStat` — что больше.
    case yoPresses(Int)
    /// `wrongKeystrokes` всех упражнений (и брошенных) в сумме ≥ N.
    case totalErrors(Int)
    /// Местное время завершения упражнения — hour:minute (любая секунда).
    case finishedAtMinute(hour: Int, minute: Int)
    /// Пятница, местное время завершения ≥ fromHour:00.
    case fridayEvening(fromHour: Int)
    /// N календарных выходных подряд с завершёнными упражнениями и в субботу, и в воскресенье (логические дни).
    case weekendStreak(Int)
    /// Завершённое упражнение от minChars знаков с точностью от minimum, но не 100%.
    case almostPerfect(minChars: Int, minimum: Double)
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
    /// Секретная: пока не получена, вместо названия, значка и условия — «???», замок и «Секретная ачивка».
    public let secret: Bool
    public let condition: AchievementCondition
    /// Только у `lettersUnlocked`: слово или команда, из которых набрано условие («пицца», «:q!»); по нему буквы
    /// в тексте условия идут в естественном порядке. Множество в условии порядка не хранит.
    public let lettersDisplay: String?

    public init(id: String, category: AchievementCategory, icon: String, adult: Bool = false,
                secret: Bool = false, condition: AchievementCondition, lettersDisplay: String? = nil) {
        self.id = id
        self.category = category
        self.icon = icon
        self.adult = adult
        self.secret = secret
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
