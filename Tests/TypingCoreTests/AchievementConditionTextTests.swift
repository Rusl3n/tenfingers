import Foundation
import Testing
@testable import TypingCore

private func ru(_ condition: AchievementCondition) -> String {
    AchievementConditionText.describe(condition, localization: "ru")
}

private func en(_ condition: AchievementCondition) -> String {
    AchievementConditionText.describe(condition, localization: "en")
}

/// Условие каждого вида: по одному примеру (порядок — как в `AchievementCondition`).
private let samples: [AchievementCondition] = [
    .streak(days: 7), .fullStreakNoFreeze(days: 30), .sparkStreak(days: 30), .speed(.ru, cpm: 150), .speed(.en, cpm: 250),
    .perfectAccuracy, .accuracyRun(count: 10, minimum: 0.98), .cleanDay(exercises: 5, minimum: 0.97),
    .firstLesson, .firstStage, .courseCompleted(.ru), .courseCompleted(.en), .polyglot,
    .allLessonsExcellent(.ru), .volumeChars(100_000), .volumeHours(1), .volumeHours(0.5),
    .finishedBetween(startHour: 0, endHour: 4), .noKeyboard, .steelPinkies(presses: 30),
    .lettersUnlocked(.ru, Set("пица")), .lettersUnlocked(.ru, Set("ё")), .lettersUnlocked(.en, Set(":q!")),
    .wholeAlphabet(.en),
    .counter(name: "wrongLayoutStarts", threshold: 10), .counter(name: "capsLockPresses", threshold: 1),
    .counter(name: "unknownCounter", threshold: 3),
    .errorStreak(10), .errorsInExercise(50), .lessonReplays(10), .abandonsInDay(3),
    .dayOfYear(month: 1, day: 1), .fridayThe13th, .bilingualDay, .marathonDay(minutes: 60),
    .comeback(gapDays: 7),
    // Фаза 5.
    .exercisesCompleted(1000), .speedGrowth(factor: 1.5, minExercises: 5),
    .allFingersAccuracy(minimum: 0.97, presses: 30, days: 7), .weakSpotsClean(count: 10, minimum: 0.98),
    .booksFinished(5), .ownText, .fullFireMonth, .freezeSavedStreak, .exactSpeed(cpm: 314), .exactSeconds(42),
    .yoPresses(100), .totalErrors(1000), .finishedAtMinute(hour: 0, minute: 0), .fridayEvening(fromHour: 21),
    .weekendStreak(4), .almostPerfect(minChars: 300, minimum: 0.999),
]

@Test func everyConditionKindHasATextInBothLanguages() {
    for condition in samples {
        for localization in ["ru", "en"] {
            let text = AchievementConditionText.describe(condition, localization: localization)
            #expect(!text.isEmpty, "\(condition)")
            #expect(!text.contains("achievement."), "ключ не переведён: «\(text)» (\(condition), \(localization))")
            #expect(!text.contains("%@") && !text.contains("%lld"), "формат не подставлен: «\(text)» (\(condition), \(localization))")
        }
    }
}

@Test func englishConditionTextsHaveNoRussianWordsExceptLetters() {
    for condition in samples {
        let words = en(condition).components(separatedBy: CharacterSet.alphanumerics.inverted)
        let cyrillic = words.filter { $0.unicodeScalars.contains { (0x400...0x4FF).contains($0.value) } }
        #expect(cyrillic.allSatisfy { $0.count == 1 }, "\(condition): «\(en(condition))»")
    }
}

@Test func streakAndFullStreak() {
    #expect(ru(.streak(days: 7)) == "Дней занятий подряд: 7")
    #expect(en(.streak(days: 7)) == "Practice streak, days: 7")
    #expect(ru(.fullStreakNoFreeze(days: 30)) == "Полных дней подряд без заморозок: 30")
    #expect(en(.fullStreakNoFreeze(days: 30)) == "Full days in a row without freezes: 30")
}

@Test func sparkStreakCondition() {
    #expect(ru(.sparkStreak(days: 7)) == "Дней подряд хотя бы с одним упражнением: 7")
    #expect(en(.sparkStreak(days: 7)) == "Days in a row with at least one exercise: 7")
}

@Test func speedNamesLanguageAndMinimumLength() {
    #expect(ru(.speed(.ru, cpm: 150))
            == "Русский: от 150 зн/мин без единой ошибки на проверке урока или тексте от 300 знаков")
    #expect(en(.speed(.en, cpm: 250))
            == "English: a lesson check or an exercise of at least 300 characters with no errors at 250 cpm or faster")
}

@Test func accuracyConditions() {
    #expect(ru(.perfectAccuracy) == "Проверка урока или упражнение от 300 знаков без единой ошибки")
    #expect(en(.perfectAccuracy) == "A lesson check or an exercise of at least 300 characters with no errors")
    #expect(ru(.accuracyRun(count: 10, minimum: 0.98)) == "Упражнений подряд с точностью от 98%: 10")
    #expect(en(.accuracyRun(count: 10, minimum: 0.98)) == "Exercises in a row with accuracy of 98% or more: 10")
    #expect(ru(.cleanDay(exercises: 5, minimum: 0.97)) == "Упражнений за день: не меньше 5, все с точностью от 97%")
    #expect(en(.cleanDay(exercises: 5, minimum: 0.97)) == "Exercises in a day: at least 5, all with accuracy of 97% or more")
}

@Test func fractionalAccuracyKeepsOneDecimal() {
    #expect(ru(.accuracyRun(count: 3, minimum: 0.985)).contains("98,5%"))
    #expect(en(.accuracyRun(count: 3, minimum: 0.985)).contains("98.5%"))
}

@Test func courseConditions() {
    #expect(ru(.firstLesson) == "Пройдите первый урок курса")
    #expect(en(.firstLesson) == "Complete the first lesson of the course")
    #expect(ru(.firstStage) == "Пройдите все уроки одного этапа курса")
    #expect(en(.firstStage) == "Complete every lesson of one course stage")
    #expect(ru(.courseCompleted(.en)) == "Пройдите весь курс: English")
    #expect(en(.courseCompleted(.ru)) == "Complete the whole course: Russian")
    #expect(ru(.polyglot) == "Пройдите оба курса: русский и английский")
    #expect(en(.polyglot) == "Complete both courses: Russian and English")
    #expect(ru(.allLessonsExcellent(.ru)) == "Все уроки курса не ниже четырёх звёзд: Русский")
    #expect(en(.allLessonsExcellent(.en)) == "Every lesson of the course on four stars or more: English")
}

@Test func volumeConditions() {
    #expect(ru(.volumeChars(100_000)).hasPrefix("Напечатано знаков: 100"))
    #expect(en(.volumeChars(100_000)).hasPrefix("Characters typed: 100"))
    #expect(ru(.volumeHours(1)) == "Часов чистой практики: 1")
    #expect(en(.volumeHours(50)) == "Hours of pure practice: 50")
    #expect(ru(.volumeHours(0.5)) == "Часов чистой практики: 0,5")
}

@Test func specialConditions() {
    #expect(ru(.finishedBetween(startHour: 0, endHour: 4)) == "Завершите упражнение между 0:00 и 4:00")
    #expect(en(.finishedBetween(startHour: 6, endHour: 8)) == "Finish an exercise between 6:00 and 8:00")
    #expect(ru(.noKeyboard) == "Проверка урока или упражнение от 300 знаков без экранной клавиатуры")
    #expect(en(.noKeyboard) == "A lesson check or an exercise of at least 300 characters without the on-screen keyboard")
    #expect(ru(.steelPinkies(presses: 30)) == "Упражнение без единой ошибки мизинцами; нажатий мизинцами не меньше: 30")
    #expect(en(.steelPinkies(presses: 30)) == "An exercise with no pinky errors; pinky presses, at least: 30")
}

@Test func lettersAreListedInAdaptiveOrderUppercased() {
    // Порядок задан языком (множество его не хранит): адаптивный порядок «оеаинтсрвлкмдпуяыьгзбчйхжшюцщэфъё».
    #expect(ru(.lettersUnlocked(.ru, Set("пица"))) == "Откройте буквы: А И П Ц")
    #expect(en(.lettersUnlocked(.ru, Set("пица"))) == "Open the letters: А И П Ц")
    #expect(ru(.lettersUnlocked(.ru, Set("привет"))) == "Откройте буквы: Е И Т Р В П")
}

@Test func displayOrderOverridesTheAdaptiveOrder() {
    func ru(_ letters: String, display: String?) -> String {
        AchievementConditionText.describe(.lettersUnlocked(.ru, Set(letters)), display: display, localization: "ru")
    }
    #expect(ru("пица", display: "пицца") == "Откройте буквы: П И Ц А")
    // Чего нет в display — после, в адаптивном порядке; лишнее из display (не в условии) игнорируется.
    #expect(ru("пица", display: "пц") == "Откройте буквы: П Ц А И")
    #expect(ru("пица", display: "пицаяя") == "Откройте буквы: П И Ц А")
    #expect(ru("пица", display: nil) == "Откройте буквы: А И П Ц")
    #expect(AchievementConditionText.describe(.lettersUnlocked(.en, Set(":q!")), display: ":q!", localization: "en")
            == "Open the characters: : Q !")
}

@Test func singleLetterUsesTheSingularForm() {
    #expect(ru(.lettersUnlocked(.ru, Set("ё"))) == "Откройте букву: Ё")
    #expect(en(.lettersUnlocked(.ru, Set("ё"))) == "Open the letter: Ё")
}

@Test func symbolsAreListedAfterLettersInsteadOfClaimingToBeLetters() {
    #expect(ru(.lettersUnlocked(.en, Set(":q!"))) == "Откройте символы: Q ! :")
    #expect(en(.lettersUnlocked(.en, Set(":q!"))) == "Open the characters: Q ! :")
}

@Test func lettersTextIsStableAcrossCalls() {
    let condition = AchievementCondition.lettersUnlocked(.en, Set("helowrd"))
    #expect(en(condition) == en(condition))
    #expect(en(condition) == "Open the letters: E O R H L D W")
}

@Test func wholeAlphabetNamesTheLanguage() {
    #expect(ru(.wholeAlphabet(.ru)) == "Откройте весь алфавит: Русский")
    #expect(en(.wholeAlphabet(.en)) == "Open the whole alphabet: English")
}

@Test func counterConditions() {
    #expect(ru(.counter(name: "wrongLayoutStarts", threshold: 10)) == "Попыток начать печатать не в той раскладке: 10")
    #expect(en(.counter(name: "wrongLayoutStarts", threshold: 10)) == "Times you started typing in the wrong layout: 10")
    #expect(ru(.counter(name: "capsLockPresses", threshold: 1)) == "Нажатий Caps Lock во время упражнения: 1")
    #expect(en(.counter(name: "capsLockPresses", threshold: 1)) == "Caps Lock presses during an exercise: 1")
    // Неизвестный счётчик (из более новой версии) — общий текст, а не ключ.
    #expect(ru(.counter(name: "unknownCounter", threshold: 3)) == "Событий в приложении: 3")
    #expect(en(.counter(name: "unknownCounter", threshold: 3)) == "App events: 3")
}

@Test func funConditions() {
    #expect(ru(.errorStreak(10)) == "Ошибок подряд в одном упражнении: 10")
    #expect(en(.errorStreak(10)) == "Errors in a row in one exercise: 10")
    #expect(ru(.errorsInExercise(50)) == "Ошибок в одном упражнении: 50")
    #expect(en(.errorsInExercise(50)) == "Errors in one exercise: 50")
    #expect(ru(.lessonReplays(10)) == "Попыток одного урока: 10")
    #expect(en(.lessonReplays(10)) == "Attempts at one lesson: 10")
    #expect(ru(.abandonsInDay(3)) == "Брошенных упражнений за день: 3")
    #expect(en(.abandonsInDay(3)) == "Abandoned exercises in a day: 3")
    #expect(ru(.dayOfYear(month: 1, day: 1)) == "Позанимайтесь в этот день: 1 января")
    #expect(en(.dayOfYear(month: 1, day: 1)) == "Practice on this day: January 1")
    #expect(ru(.fridayThe13th) == "Позанимайтесь в пятницу, 13-го числа")
    #expect(en(.fridayThe13th) == "Practice on Friday the 13th")
    #expect(ru(.bilingualDay) == "Упражнения на обоих языках за один день")
    #expect(en(.bilingualDay) == "Exercises in both languages in one day")
    #expect(ru(.marathonDay(minutes: 60)) == "Минут чистой практики за день: 60")
    #expect(en(.marathonDay(minutes: 60)) == "Minutes of pure practice in a day: 60")
    #expect(ru(.comeback(gapDays: 7)) == "Вернитесь к занятиям после перерыва в днях: 7")
    #expect(en(.comeback(gapDays: 7)) == "Come back to practice after a break, in days: 7")
}

@Test func everyCatalogConditionIsDescribed() {
    for achievement in AchievementCatalog.all {
        let text = achievement.conditionText
        #expect(!text.isEmpty && !text.contains("achievement."), "«\(achievement.id)»: «\(text)»")
    }
}

@Test func phaseFiveConditionsInRussian() {
    // Разделитель разрядов зависит от ICU (неразрывный или узкий пробел).
    func spaced(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }
    #expect(spaced(ru(.exercisesCompleted(1000))) == "Завершённых упражнений: 1 000")
    #expect(ru(.speedGrowth(factor: 1.5, minExercises: 5))
            == "Средняя скорость за 7 дней в 1,5 раза выше, чем в первую неделю языка (от 5 упражнений)")
    #expect(ru(.speedGrowth(factor: 2, minExercises: 5)).contains("в 2 раза выше"))
    #expect(ru(.allFingersAccuracy(minimum: 0.97, presses: 30, days: 7))
            == "Точность каждого пальца за 7 дн. — от 97%, не меньше 30 нажатий на палец")
    #expect(ru(.weakSpotsClean(count: 10, minimum: 0.98)) == "Упражнений «Слабые места» с точностью от 98%: 10")
    #expect(ru(.booksFinished(5)) == "Отрывков из книг набрано до конца: 5")
    #expect(ru(.ownText) == "Завершите упражнение со своим текстом")
    #expect(ru(.fullFireMonth) == "Все дни календарного месяца — полный огонь, без заморозок")
    #expect(ru(.freezeSavedStreak) == "Заморозка спасла серию: после пропуска вы вернулись к занятиям")
    #expect(ru(.exactSpeed(cpm: 314)) == "Итоговая скорость упражнения — ровно 314 зн/мин")
    #expect(ru(.exactSeconds(42)) == "Чистое время упражнения — ровно 42 с")
    #expect(ru(.yoPresses(100)) == "Буква «Ё» без ошибки, раз: 100")
    #expect(spaced(ru(.totalErrors(1000))) == "Ошибок за всё время: 1 000")
    #expect(ru(.finishedAtMinute(hour: 0, minute: 0)) == "Завершите упражнение ровно в 0:00")
    #expect(ru(.fridayEvening(fromHour: 21)) == "Завершите упражнение в пятницу после 21:00")
    #expect(ru(.weekendStreak(4)) == "Выходных подряд с занятиями и в субботу, и в воскресенье: 4")
    let almost = ru(.almostPerfect(minChars: 300, minimum: 0.999))
    #expect(almost == "Упражнение от 300 знаков с точностью от 99,9%, но не 100%")
    #expect(!almost.contains("%%"))
}

@Test func phaseFiveConditionsInEnglish() {
    #expect(en(.exercisesCompleted(1000)) == "Exercises finished: 1,000")
    #expect(en(.speedGrowth(factor: 1.5, minExercises: 5))
            == "7-day average speed is 1.5× your first week on a language (at least 5 exercises)")
    #expect(en(.allFingersAccuracy(minimum: 0.97, presses: 30, days: 7))
            == "Every finger at 97%+ accuracy over 7 days, at least 30 presses each")
    #expect(en(.weakSpotsClean(count: 1, minimum: 0.98)) == "Weak spots exercises at 98%+ accuracy: 1")
    #expect(en(.booksFinished(25)) == "Book excerpts typed to the end: 25")
    #expect(en(.ownText) == "Finish an exercise with your own text")
    #expect(en(.fullFireMonth) == "Every day of a calendar month at full flame, no freezes")
    #expect(en(.freezeSavedStreak) == "A freeze saved your streak: you came back after a missed day")
    #expect(en(.exactSpeed(cpm: 314)) == "Finish an exercise at exactly 314 characters per minute")
    #expect(en(.exactSeconds(42)) == "An exercise with exactly 42 s of active time")
    #expect(en(.yoPresses(100)) == "Letter Ё typed without errors, times: 100")
    #expect(en(.totalErrors(1000)) == "Typos in total: 1,000")
    #expect(en(.finishedAtMinute(hour: 0, minute: 0)) == "Finish an exercise at exactly 0:00")
    #expect(en(.fridayEvening(fromHour: 21)) == "Finish an exercise on a Friday after 21:00")
    #expect(en(.weekendStreak(4)) == "Weekends in a row with practice on both Saturday and Sunday: 4")
    #expect(en(.almostPerfect(minChars: 300, minimum: 0.999))
            == "An exercise of 300+ characters at 99.9%+ accuracy, but not 100%")
}

/// Новые условия-просьбы у полученной ачивки читаются утверждением.
@Test func phaseFiveImperativeConditionsHaveEarnedForms() {
    func earned(_ condition: AchievementCondition, _ language: String) -> String {
        AchievementConditionText.describe(condition, localization: language, earned: true)
    }
    #expect(earned(.ownText, "ru") == "Завершено упражнение со своим текстом")
    #expect(earned(.finishedAtMinute(hour: 0, minute: 0), "ru") == "Упражнение завершено ровно в 0:00")
    #expect(earned(.fridayEvening(fromHour: 21), "ru") == "Упражнение завершено в пятницу после 21:00")
    #expect(earned(.exactSpeed(cpm: 314), "ru") == "Упражнение завершено со скоростью ровно 314 зн/мин")
    #expect(earned(.ownText, "en") == "An exercise with your own text finished")
    #expect(earned(.finishedAtMinute(hour: 0, minute: 0), "en") == "An exercise finished at exactly 0:00")
    #expect(earned(.fridayEvening(fromHour: 21), "en") == "An exercise finished on a Friday after 21:00")
    #expect(earned(.exactSpeed(cpm: 314), "en") == "An exercise finished at exactly 314 characters per minute")
    for key in ["ownText", "atMinute", "fridayEvening", "exactSpeed"] {
        #expect(AchievementConditionText.earnedForms.contains(key), "\(key)")
    }
}
