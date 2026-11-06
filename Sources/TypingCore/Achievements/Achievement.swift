import Foundation

public enum AchievementCategory: String, CaseIterable, Sendable {
    case streak, speed, accuracy, course, milestone, volume, special, letters, fun
    /// Игра «Ритм» (решение 12 плана игры): ачивки по сохранённым заходам и времени в игре.
    case rhythm
    /// «Тренировки» (8b–8c): исправленные слова, замеры скорости.
    case trainings
}

/// Группа клавиш курса для вех: цифры 0–9 или знаки и символы (все `newKeys` издания 2, кроме букв и цифр).
public enum KeyGroup: Sendable {
    case digits, symbols
}

/// Вид дистанции (6d, решение 11): что считает `AchievementCondition.distance`.
public enum DistanceKind: Sendable {
    /// Нажатия пробела (`fingerPresses[.thumb]`); сессии без статистики пальцев (до 1.1.0) не считаются.
    case spaces
    /// Нажатия мизинцами (`pinkyPresses`).
    case pinkies
    /// Завершённые порции тренировки: режимы `adaptive` и `weak` (в том числе «Точность пальца»).
    case trainings
    /// Завершённые проверки `check` (не `refresh`) в режиме курса: последний шаг любого урока, с переигровками.
    case lessons
    /// Завершённые связные тексты от `Analytics.recordMinimumChars` знаков.
    case texts
    /// Логические дни с выполненным планом дня (решение 8).
    case plans
}

/// Условие получения ачивки; проверяет `AchievementEngine` по фактам из истории.
/// Точность — доля от 0 до 1, как `ExerciseResult.accuracy`.
public enum AchievementCondition: Equatable, Sendable {
    /// Текущая серия достигала N дней.
    case streak(days: Int)
    /// N полных дней подряд без заморозок.
    case fullStreakNoFreeze(days: Int)
    /// «Искра»: N дней подряд с хотя бы одним завершённым упражнением (`.full` или `.half`); замороженный день
    /// не считается.
    case sparkStreak(days: Int)
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
    /// Все уроки курса языка, кроме ступеней скорости (`tier`), не ниже `LessonScoring.excellentStars` (по `LessonScoring.effectiveStars`).
    case allLessonsExcellent(Language)
    case volumeChars(Int), volumeHours(Double)
    /// Локальное время завершения упражнения в [startHour, endHour).
    case finishedBetween(startHour: Int, endHour: Int)
    /// Время суток для повторяемых ачивок: местное время завершения упражнения в [startHour, endHour); одно
    /// получение на логический день (6d, решение 4).
    case dayPart(startHour: Int, endHour: Int)
    /// За логический день ≥ N заходов (6d, решение 5): новый заход начинается, если от конца предыдущего
    /// завершённого упражнения до начала следующего прошло больше 60 минут.
    case visits(Int)
    /// «Новый рекорд скорости» (6d, решение 6): подходящее безошибочное упражнение языка с округлённым `cpm`
    /// строго выше прежнего рекорда языка; первое такое упражнение языка — точка отсчёта.
    case speedRecord
    /// Проверка этапа (`LessonKind.stageCheck`) впервые набрала порог этапа `Stage.gate` (6d, решение 7);
    /// у издания 1 — все уроки этапа засчитаны.
    case stagePassed
    /// Урок издания 2 впервые достиг N звёзд по `LessonScoring.effectiveStars` (6d, решение 7).
    case lessonStars(Int)
    /// Урок-ступень (`LessonKind.tier`) издания 2 впервые получил ★★★ (6d, решение 7).
    case tierPassed
    /// N логических дней подряд с выполненным планом дня; после выдачи отсчёт с нуля (6d, решения 8–9).
    case planWeek(days: Int)
    /// Дистанция (6d, решение 11): сумма или число событий вида `DistanceKind` достигла порога.
    case distance(DistanceKind, Int)
    /// N подходящих упражнений (завершённая проверка урока или завершённое ≥ 300 знаков) на 100%.
    case perfectCount(Int)
    /// N логических дней, в которые первые `exercises` завершённых упражнений все с точностью ≥ `minimum`.
    case cleanDays(count: Int, exercises: Int, minimum: Double)
    /// Открыты все клавиши группы для языка (6d, решение 10): все 10 цифр, либо все знаки и символы курса издания 2.
    case keysUnlocked(Language, KeyGroup)
    /// Завершённый связный текст (`textTraits & 8` или `source` `library:*` / `custom`) от `minChars` знаков без
    /// единой ошибки; `hard` — ещё и заглавные, пунктуация и цифры (`textTraits` содержит 1, 2 и 4).
    case cleanText(minChars: Int, hard: Bool)
    /// Первая завершённая проверка этапа с `HintLevel.hidden`, набравшая порог этапа `Stage.gate`.
    case blindStageCheck
    /// Первый логический день с выполненным планом дня (решение 8).
    case firstPlanDay
    /// Первая выдача `course.speed_tier`: первый урок-ступень с ★★★.
    case firstTier
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
    /// Пропущенный день спасён двойной целью на следующий день (`DayStatus.repaired`, 6e, §10.4).
    case streakRepair
    /// Выполнены все три испытания недели (6e, §10.2); повторяемая, ключ — неделя (`2026-W44`).
    case challengeWeek
    /// Выполнено испытание месяца (6e, §10.2); повторяемая, ключ — месяц (`2026-11`).
    case challengeMonth
    /// Достигнут уровень опыта N (6e, §10.3): дата — начисление, после которого порог уровня взят.
    case level(Int)
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

    // 6d, идеи пользователя (решение 18).

    /// Чистое время логического дня ≥ N × цели этого дня (`DayActivity.goalSeconds`, а где её нет и у сегодняшнего —
    /// текущая цель); повторяемая, ключ — день, значение — минуты за день.
    case goalMultiple(Int)
    /// «Тише едешь»: завершённый шаг урока без ошибок, медленнее цели урока; повторяемая, одно получение на день.
    case slowAndSteady
    /// «С первого раза»: первая попытка (и брошенная) шага урока издания 2 завершена без ошибок и не медленнее
    /// цели урока; повторяемая, ключ — `<lessonId>#<stepIndex>`.
    case firstTry
    /// Завершено занятие «Точность пальца» (`source` `finger:<палец>:accuracy`) для каждого из восьми пальцев.
    case allFingersDrilled

    // Игра «Ритм» (решение 12): разовые, по пройденным трекам (`RhythmFact.cleared`); `rhythmSeconds` — по времени
    // сессий `rhythm`, пройденных и нет.

    /// Первый пройденный трек.
    case rhythmCleared
    /// Трек пройден без единого `miss`.
    case rhythmFullCombo
    /// Трек пройден, все оценённые ноты — `perfect`.
    case rhythmAllPerfect
    /// Пройденный трек с максимальным комбо ≥ N.
    case rhythmCombo(Int)
    /// Пройденный трек на уровне `level` с оценкой `grade`.
    case rhythmGrade(RhythmGrade, level: RhythmLevelID)
    /// Пройдено хотя бы по одному треку в каждом из четырёх режимов нот; дата — первый пройденный трек последнего режима.
    case rhythmAllModes
    /// Сумма `activeSeconds` всех сессий `rhythm` (пройденных и нет) достигла N секунд.
    case rhythmSeconds(Double)

    // Замер скорости (8c): по сохранённым `SpeedMeasurement`, задним числом не выдаются (замеров до 2.9.0 нет).

    /// Первый сохранённый замер скорости (любого варианта).
    case measureFirst
    /// Замер, чей `cpm` ≥ 2 × `cpm` первого замера того же варианта (длительность + вид текста + язык).
    case measureDoubled
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
    /// Повторяемая: получается много раз (по ключу получения), «×N» на значке (6d, решение 2). Первое получение
    /// создаёт запись ачивки, дальше — выдачи.
    public let repeatable: Bool
    public let condition: AchievementCondition
    /// Только у `lettersUnlocked`: слово или команда, из которых набрано условие («пицца», «:q!»); по нему буквы
    /// в тексте условия идут в естественном порядке. Множество в условии порядка не хранит.
    public let lettersDisplay: String?

    public init(id: String, category: AchievementCategory, icon: String, adult: Bool = false,
                secret: Bool = false, repeatable: Bool = false, condition: AchievementCondition,
                lettersDisplay: String? = nil) {
        self.id = id
        self.category = category
        self.icon = icon
        self.adult = adult
        self.secret = secret
        self.repeatable = repeatable
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
