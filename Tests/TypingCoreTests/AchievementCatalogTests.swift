import Foundation
import Testing
@testable import TypingCore

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func strings(_ lang: String) throws -> [String: String] {
    let url = root.appendingPathComponent("Sources/TypingCore/Resources/\(lang).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

private func cyrillicWords(_ s: String) -> [String] {
    s.components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.unicodeScalars.contains { (0x400...0x4FF).contains($0.value) } }
}

@Test func achievementIdsAreUniqueAndStable() {
    let ids = AchievementCatalog.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    for id in ids {
        #expect(!id.isEmpty)
        #expect(id.unicodeScalars.allSatisfy { $0.isASCII && !$0.properties.isWhitespace }, "id «\(id)» не ASCII")
        #expect(id == id.lowercased(), "id «\(id)» с заглавными")
    }
    // Ключевые id из плана не переименовываются.
    for id in ["streak.7", "speed.ru.150", "letters.ru.pizza", "fun.ghbdtn", "fun.oy_vsyo"] {
        #expect(ids.contains(id), "нет id «\(id)»")
    }
}

/// Все 162 id как есть в базах пользователей: переименование или удаление должно ронять тест
/// (новая ачивка — осознанное дополнение этого списка).
private let goldenIds: [String] = [
    "streak.3", "streak.7", "streak.14", "streak.30",
    "streak.50", "streak.100", "streak.200", "streak.365",
    "streak.iron_will", "speed.ru.100", "speed.ru.150", "speed.ru.200",
    "speed.ru.250", "speed.ru.300", "speed.en.100", "speed.en.150",
    "speed.en.200", "speed.en.250", "speed.en.300", "accuracy.sniper",
    "accuracy.surgeon", "accuracy.clean_day", "course.first_lesson", "course.first_stage",
    "course.ru", "course.en", "course.polyglot", "course.stars.ru",
    "course.stars.en", "volume.chars.10k", "volume.chars.100k", "volume.chars.1m",
    "volume.hours.1", "volume.hours.10", "volume.hours.50", "volume.hours.100",
    "special.night_owl", "special.early_bird", "special.no_peeking", "special.steel_pinkies",
    "letters.ru.hello", "letters.ru.pizza", "letters.ru.borscht", "letters.ru.b_word",
    "letters.ru.three_letters", "letters.ru.deadline", "letters.ru.yo", "letters.ru.hard_sign",
    "letters.ru.alphabet", "letters.en.fluent_f", "letters.en.shit_happens", "letters.en.wtf",
    "letters.en.pizza", "letters.en.hello_world", "letters.en.sudo", "letters.en.vim",
    "fun.ghbdtn", "fun.sausage_fingers", "fun.ctrl_z", "fun.oy_vsyo",
    "fun.perfectionist", "fun.not_today", "fun.no_coffee", "fun.new_year",
    "fun.friday13", "fun.bilingual", "fun.marathon", "fun.comeback",
    // Фаза 5 (21).
    "streak.fire_month", "streak.insurance", "speed.growth.150", "speed.growth.200",
    "accuracy.all_fingers", "volume.exercises.100", "volume.exercises.500", "volume.exercises.1000",
    "volume.books.5", "volume.books.25", "special.weak_spot", "special.weak_spot.10",
    "special.own_words", "fun.pi", "fun.answer42", "fun.yo_master",
    "fun.learning_from_mistakes", "fun.cinderella", "fun.friday_night", "fun.weekend_warrior",
    "fun.almost",
    // Фаза 6c (4): ступени «Искры».
    "spark.7", "spark.30", "spark.100", "spark.365",
    // Фаза 6d (6): время суток и заходы.
    "time.morning", "time.afternoon", "time.evening", "habit.visits.2", "habit.visits.3", "habit.visits.5",
    // Фаза 6d (5): рекорд скорости, этапы, пять звёзд, ступени, неделя по плану.
    "speed.record", "course.stage", "course.five_stars", "course.speed_tier", "plan.week",
    // Фаза 6d (13): вехи курса, английский алфавит и «Вайбкодер».
    "letters.en.alphabet", "milestone.ru.digits", "milestone.en.digits", "milestone.ru.symbols",
    "milestone.en.symbols", "milestone.first_clean_text", "milestone.first_hard_text", "milestone.first_long_text",
    "milestone.first_blind_check", "milestone.first_plan", "milestone.first_tier", "fun.vibe_coder.ru",
    "fun.vibe_coder.en",
    // Фаза 6d (23): дистанция, объём и новые ступени.
    "volume.chars.500k", "volume.exercises.2500", "volume.exercises.4000",
    "distance.space.75k", "distance.space.100k", "distance.space.150k",
    "distance.pinky.45k", "distance.pinky.60k", "distance.pinky.85k",
    "distance.training.100", "distance.training.300", "distance.training.500",
    "distance.lessons.100", "distance.lessons.200", "distance.lessons.300",
    "distance.texts.100", "distance.texts.200", "distance.texts.300",
    "distance.plans.100", "distance.plans.300",
    "accuracy.surgeon.50", "accuracy.sniper.100", "accuracy.clean_day.100",
    // Фаза 6d (5): идеи пользователя и «Восемь пальцев».
    "habit.goal.x2", "habit.goal.x3", "fun.slow_steady", "course.first_try", "fingers.all_eight",
    // Фаза 6e (1): починка серии.
    "streak.repair",
    // Фаза 6e (2): испытания недели и месяца.
    "challenge.week", "challenge.month",
    // Фаза 6e (3): уровни.
    "level.10", "level.30", "level.45",
    // Ритм (решение 12 плана игры «Ритм»).
    "rhythm.first", "rhythm.fullcombo", "rhythm.perfect", "rhythm.combo100", "rhythm.s.expert",
    "rhythm.allmodes", "rhythm.hour",
    // Фаза 8b (4): «Работа над ошибками».
    "errorwords.fixed10", "errorwords.fixed50", "errorwords.fixed200", "errorwords.fixed1000",
]

@Test func catalogIdsMatchTheGoldenList() {
    let ids = AchievementCatalog.all.map(\.id)
    #expect(goldenIds.count == 162 && Set(goldenIds).count == 162)
    #expect(Set(ids) == Set(goldenIds),
            "пропали: \(Set(goldenIds).subtracting(ids).sorted()); лишние: \(Set(ids).subtracting(goldenIds).sorted())")
    #expect(ids.count == goldenIds.count)
}

@Test func parametricIdsAgreeWithTheirConditions() throws {
    for achievement in AchievementCatalog.all {
        let id = achievement.id, parts = id.split(separator: ".").map(String.init)
        switch achievement.condition {
        case .streak(let days):
            #expect(id == "streak.\(days)")
        case .sparkStreak(let days):
            #expect(id == "spark.\(days)")
        case .speed(let language, let cpm):
            #expect(id == "speed.\(language.rawValue).\(cpm)")
        case .volumeChars(let count):
            let suffix = count % 1_000_000 == 0 ? "\(count / 1_000_000)m" : "\(count / 1000)k"
            #expect(id == "volume.chars.\(suffix)", "«\(id)»: \(count)")
        case .volumeHours(let hours):
            #expect(id == "volume.hours.\(Int(hours))")
        case .lettersUnlocked(let language, _), .wholeAlphabet(let language):
            if id.hasPrefix("fun.vibe_coder.") {
                #expect(id == "fun.vibe_coder.\(language.rawValue)", "«\(id)»")
            } else {
                #expect(parts.count == 3 && parts[0] == "letters" && parts[1] == language.rawValue, "«\(id)»")
            }
        case .keysUnlocked(let language, let group):
            #expect(id == "milestone.\(language.rawValue).\(group == .digits ? "digits" : "symbols")", "«\(id)»")
        case let .dayPart(start, end):
            let names = [5: "morning", 12: "afternoon", 18: "evening"]
            #expect(id == "time.\(names[start] ?? "?")", "«\(id)»: \(start)–\(end)")
        case .visits(let count):
            #expect(id == "habit.visits.\(count)")
        case .courseCompleted(let language):
            #expect(id == "course.\(language.rawValue)")
        case .allLessonsExcellent(let language):
            #expect(id == "course.stars.\(language.rawValue)")
        case .speedGrowth(let factor, _):
            #expect(id == "speed.growth.\(Int((factor * 100).rounded()))", "«\(id)»: \(factor)")
        case .exercisesCompleted(let count):
            #expect(id == "volume.exercises.\(count)")
        case let .distance(kind, count):
            let names: [DistanceKind: String] = [.spaces: "space", .pinkies: "pinky", .trainings: "training",
                                                 .lessons: "lessons", .texts: "texts", .plans: "plans"]
            let suffix = kind == .spaces || kind == .pinkies ? "\(count / 1000)k" : "\(count)"
            #expect(id == "distance.\(names[kind] ?? "?").\(suffix)", "«\(id)»: \(kind) \(count)")
        case .booksFinished(let count):
            #expect(id == "volume.books.\(count)")
        case .weakSpotsClean(let count, _):
            // Первое чистое упражнение — `special.weak_spot` без числа, дальше — `special.weak_spot.<число>`.
            #expect(id == (count == 1 ? "special.weak_spot" : "special.weak_spot.\(count)"), "«\(id)»: \(count)")
        case .level(let level):
            #expect(id == "level.\(level)")
        default: break
        }
    }
    // Обратное направление: id с числом не должен остаться без условия-пары.
    for achievement in AchievementCatalog.all {
        let id = achievement.id
        // У серии числовые id — только `streak.<дни>` (`streak.iron_will`, `streak.fire_month` — по названию).
        if id.hasPrefix("streak."), Int(id.dropFirst("streak.".count)) != nil {
            guard case .streak = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("spark.") {
            guard case .sparkStreak = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("speed.growth.") {
            guard case .speedGrowth = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        } else if id == "speed.record" {
            guard case .speedRecord = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        } else if id.hasPrefix("speed.") {
            guard case .speed = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("volume.chars.") {
            guard case .volumeChars = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("volume.exercises.") {
            guard case .exercisesCompleted = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("volume.books.") {
            guard case .booksFinished = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("volume.hours.") {
            guard case .volumeHours = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id == "special.weak_spot" || id.hasPrefix("special.weak_spot.") {
            guard case .weakSpotsClean = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
    }
}

@Test func lettersDisplayIsTheOrderedFormOfTheConditionLetters() {
    for achievement in AchievementCatalog.all {
        if case let .lettersUnlocked(_, letters) = achievement.condition {
            let display = achievement.lettersDisplay
            #expect(display != nil, "«\(achievement.id)»: нет lettersDisplay")
            // Пробелы разрешены только у «Вайбкодера»: слова перечислены через пробел.
            let shown = achievement.id.hasPrefix("fun.vibe_coder.") ? (display ?? "").filter { $0 != " " } : display ?? ""
            #expect(Set(shown) == letters, "«\(achievement.id)»: \(display ?? "nil") ≠ \(letters)")
        } else {
            #expect(achievement.lettersDisplay == nil, "«\(achievement.id)»")
        }
    }
}

@Test func lockedLettersTextFollowsTheWordOrder() throws {
    func text(_ id: String) throws -> String {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == id })
        return AchievementConditionText.describe(achievement.condition, display: achievement.lettersDisplay,
                                                 localization: "ru")
    }
    #expect(try text("letters.ru.pizza") == "Откройте буквы: П И Ц А")
    #expect(try text("letters.ru.hello") == "Откройте буквы: П Р И В Е Т")
    #expect(try text("letters.en.vim") == "Откройте символы: : Q !")
    #expect(try text("letters.en.hello_world") == "Откройте буквы: H E L O W R D")
    #expect(try text("letters.ru.yo") == "Откройте букву: Ё")
    // Ругательства: буквы на экране по алфавиту, а не по слову.
    #expect(try text("letters.ru.three_letters") == "Откройте буквы: Й У Х")
    #expect(try text("letters.ru.b_word") == "Откройте буквы: Б Л Я")
    // en-ачивки — localization "ru" тоже годится: проверяем порядок.
    #expect(try text("letters.en.fluent_f") == "Откройте буквы: C F K U")
    #expect(try text("letters.en.shit_happens") == "Откройте буквы: H I S T")
}

@Test func swearWordConditionsKeepTheirLetterSets() throws {
    func condition(_ id: String) throws -> AchievementCondition {
        try #require(AchievementCatalog.all.first { $0.id == id }).condition
    }
    #expect(try condition("letters.ru.three_letters") == .lettersUnlocked(.ru, Set("хуй")))
    #expect(try condition("letters.ru.b_word") == .lettersUnlocked(.ru, Set("бля")))
    #expect(try condition("letters.ru.deadline") == .lettersUnlocked(.ru, Set("жопа")))
    #expect(try condition("letters.en.fluent_f") == .lettersUnlocked(.en, Set("fuck")))
    #expect(try condition("letters.en.shit_happens") == .lettersUnlocked(.en, Set("shit")))
    #expect(try condition("letters.en.wtf") == .lettersUnlocked(.en, Set("wtf")))
}

@Test func secretAchievementsAreFunAdultAndNightOwlEarlyBird() {
    let secret = Set(AchievementCatalog.all.filter(\.secret).map(\.id))
    let expected = Set(AchievementCatalog.all.filter { $0.category == .fun || $0.adult }.map(\.id))
        .union(["special.night_owl", "special.early_bird", "habit.visits.5"])
    #expect(secret == expected)
    #expect(secret.count == 32)
    #expect(secret.isSuperset(of: ["fun.vibe_coder.ru", "fun.vibe_coder.en"]))
}

@Test func catalogMatchesSectionTwelveCounts() {
    func count(_ category: AchievementCategory) -> Int {
        AchievementCatalog.all.filter { $0.category == category }.count
    }
    #expect(count(.streak) == 16)
    #expect(count(.speed) == 13)
    #expect(count(.accuracy) == 8)
    #expect(count(.course) == 11)
    #expect(count(.volume) == 32)
    #expect(count(.trainings) == 4)
    #expect(count(.special) == 18)
    #expect(count(.milestone) == 13)
    #expect(count(.letters) == 17)
    #expect(count(.fun) == 23)
    #expect(count(.rhythm) == 7)
    #expect(AchievementCatalog.all.count == 162)
}

@Test func everyAchievementHasRussianAndEnglishTexts() throws {
    let ru = try strings("ru"), en = try strings("en")
    for achievement in AchievementCatalog.all {
        for suffix in ["title", "detail"] {
            let key = "achievement.\(achievement.id).\(suffix)"
            let ruValue = try #require(ru[key], "ru: нет «\(key)»")
            let enValue = try #require(en[key], "en: нет «\(key)»")
            #expect(!ruValue.isEmpty && ruValue != key)
            #expect(!enValue.isEmpty && enValue != key)
            // В английском кириллица допустима только как названия букв: «The Б Word».
            #expect(cyrillicWords(enValue).allSatisfy { $0.count == 1 }, "en: «\(key)» → «\(enValue)»")
        }
    }
}

@Test func titleAndDetailResolveThroughCoreBundle() throws {
    let pizza = try #require(AchievementCatalog.all.first { $0.id == "letters.ru.pizza" })
    #expect(["Пиццерия", "Pizzeria"].contains(pizza.title))
    #expect(CoreText.localized("achievement.letters.ru.pizza.title", localization: "ru") == "Пиццерия")
    #expect(CoreText.localized("achievement.letters.ru.pizza.title", localization: "en") == "Pizzeria")
    let sniper = try #require(AchievementCatalog.all.first { $0.id == "accuracy.sniper" })
    #expect(!sniper.detail.isEmpty)
    // Знак процента в условии не ломает форматирование.
    let condition = AchievementConditionText.describe(sniper.condition, localization: "ru")
    #expect(!condition.contains("%%") && !condition.contains("%@"), "«\(condition)»")
}

/// «Отличник курса» сохраняет id `course.stars.*`, а условие — все уроки не ниже ★★★★ (прежние ★★★).
@Test func courseStarsAchievementsRequireExcellentStars() throws {
    for language in Language.allCases {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == "course.stars.\(language.rawValue)" })
        #expect(achievement.condition == .allLessonsExcellent(language))
    }
    #expect(LessonScoring.excellentStars == 4)
    let ru = try strings("ru"), en = try strings("en")
    #expect(ru["achievement.course.stars.ru.title"] == "Отличник курса (RU)")
    #expect(ru["achievement.course.stars.en.title"] == "Отличник курса (EN)")
    #expect(en["achievement.course.stars.ru.title"] == "Top of the Class (RU)")
    #expect(en["achievement.course.stars.en.title"] == "Top of the Class (EN)")
    #expect(ru["achievement.course.stars.ru.detail"] == "Все уроки не ниже четырёх звёзд. Перфекционизм одобрен")
    #expect(en["achievement.course.stars.en.detail"] == "Four stars or more in every lesson. Even the textbook is jealous")
}

/// Описание — шутка, а не пересказ условия (условие показывают «За что» и «Как получить»).
@Test func detailsAreJokesNotConditions() throws {
    let ru = try strings("ru"), en = try strings("en")
    for achievement in AchievementCatalog.all {
        let key = achievement.detailKey
        for (language, table) in [("ru", ru), ("en", en)] {
            let detail = try #require(table[key])
            let condition = AchievementConditionText.describe(achievement.condition, display: achievement.lettersDisplay,
                                                              localization: language)
            #expect(detail != condition, "\(language): «\(key)» повторяет условие")
            #expect(detail.count <= 90, "\(language): «\(key)» длиннее 90 знаков")
        }
    }
    #expect(ru["achievement.streak.3.detail"] == "Три дня подряд — это уже не случайность")
}

/// Условия скорости, «Снайпера» и «Без подглядывания» (строки «Как получить» и «За что») говорят о текущем
/// правиле: засчитывается и проверка урока, а скорость — только без ошибок.
@Test func qualifyingExerciseConditionsMentionLessonChecks() throws {
    let achievements = AchievementCatalog.all.filter {
        switch $0.condition {
        case .speed, .perfectAccuracy, .noKeyboard: true
        default: false
        }
    }
    #expect(achievements.count == 12)
    for achievement in achievements {
        let id = achievement.id
        let ruValue = AchievementConditionText.describe(achievement.condition, localization: "ru")
        let enValue = AchievementConditionText.describe(achievement.condition, localization: "en")
        #expect(ruValue.lowercased().contains("проверк"), "ru: «\(id)» → «\(ruValue)»")
        #expect(enValue.lowercased().contains("lesson check"), "en: «\(id)» → «\(enValue)»")
        if id.hasPrefix("speed.") {
            #expect(ruValue.contains("без единой ошибки"), "ru: «\(id)» → «\(ruValue)»")
            #expect(enValue.contains("no errors"), "en: «\(id)» → «\(enValue)»")
        }
    }
}

@Test func adultAchievementsAreExactlyTheSixFromSectionTwelve() {
    let adult = Set(AchievementCatalog.all.filter(\.adult).map(\.id))
    #expect(adult == [
        "letters.ru.b_word", "letters.ru.three_letters", "letters.ru.deadline",
        "letters.en.fluent_f", "letters.en.shit_happens", "letters.en.wtf",
    ])
}

@Test func unlockedLettersExistInLanguageOrCourse() throws {
    for achievement in AchievementCatalog.all {
        guard case let .lettersUnlocked(language, letters) = achievement.condition else { continue }
        // «Вайбкодер» — шуточная из «Забав», но по тем же буквам.
        #expect(achievement.category == .letters || achievement.id.hasPrefix("fun.vibe_coder."))
        #expect(!letters.isEmpty)
        let course = try CourseCatalog.load(language)
        let known = language.letters.union(course.typeableCharacters)
        #expect(letters.isSubset(of: known), "«\(achievement.id)»: \(letters.subtracting(known))")
    }
}

@Test func lettersAchievementsUseLetterConditions() {
    for achievement in AchievementCatalog.all where achievement.category == .letters {
        switch achievement.condition {
        case .lettersUnlocked, .wholeAlphabet: break
        default: Issue.record("«\(achievement.id)»: условие \(achievement.condition)")
        }
    }
}

@Test func iconsAreNonEmpty() {
    for achievement in AchievementCatalog.all {
        #expect(!achievement.icon.trimmingCharacters(in: .whitespaces).isEmpty, "«\(achievement.id)»")
    }
}

@Test func keyConditionsMatchThePlan() throws {
    func condition(_ id: String) throws -> AchievementCondition {
        try #require(AchievementCatalog.all.first { $0.id == id }).condition
    }
    #expect(try condition("fun.oy_vsyo") == .counter(name: "capsLockPresses", threshold: 1))
    #expect(try condition("fun.ghbdtn") == .counter(name: "wrongLayoutStarts", threshold: 10))
    #expect(try condition("streak.iron_will") == .fullStreakNoFreeze(days: 30))
    #expect(try condition("speed.en.300") == .speed(.en, cpm: 300))
    #expect(try condition("accuracy.surgeon") == .accuracyRun(count: 10, minimum: 0.98))
    #expect(try condition("accuracy.clean_day") == .cleanDay(exercises: 5, minimum: 0.97))
    #expect(try condition("letters.ru.pizza") == .lettersUnlocked(.ru, Set("пица")))
    #expect(try condition("letters.ru.alphabet") == .wholeAlphabet(.ru))
    #expect(try condition("special.night_owl") == .finishedBetween(startHour: 0, endHour: 4))
    #expect(try condition("fun.comeback") == .comeback(gapDays: 7))
    // Фаза 5.
    #expect(try condition("streak.fire_month") == .fullFireMonth)
    #expect(try condition("streak.insurance") == .freezeSavedStreak)
    #expect(try condition("speed.growth.150") == .speedGrowth(factor: 1.5, minExercises: 5))
    #expect(try condition("speed.growth.200") == .speedGrowth(factor: 2, minExercises: 5))
    #expect(try condition("accuracy.all_fingers") == .allFingersAccuracy(minimum: 0.97, presses: 30, days: 7))
    #expect(try condition("volume.exercises.100") == .exercisesCompleted(100))
    #expect(try condition("volume.exercises.500") == .exercisesCompleted(500))
    #expect(try condition("volume.exercises.1000") == .exercisesCompleted(1000))
    #expect(try condition("volume.books.5") == .booksFinished(5))
    #expect(try condition("volume.books.25") == .booksFinished(25))
    #expect(try condition("special.weak_spot") == .weakSpotsClean(count: 1, minimum: 0.98))
    #expect(try condition("special.weak_spot.10") == .weakSpotsClean(count: 10, minimum: 0.98))
    #expect(try condition("special.own_words") == .ownText)
    #expect(try condition("fun.pi") == .exactSpeed(cpm: 314))
    #expect(try condition("fun.answer42") == .exactSeconds(42))
    #expect(try condition("fun.yo_master") == .yoPresses(100))
    #expect(try condition("fun.learning_from_mistakes") == .totalErrors(1000))
    #expect(try condition("fun.cinderella") == .finishedAtMinute(hour: 0, minute: 0))
    #expect(try condition("fun.friday_night") == .fridayEvening(fromHour: 21))
    #expect(try condition("fun.weekend_warrior") == .weekendStreak(4))
    #expect(try condition("fun.almost") == .almostPerfect(minChars: 300, minimum: 0.999))
    // Фаза 6d: прежние условия времени суток не меняются.
    #expect(try condition("special.early_bird") == .finishedBetween(startHour: 6, endHour: 8))
    #expect(try condition("fun.no_coffee") == .finishedBetween(startHour: 5, endHour: 6))
    #expect(try condition("time.evening") == .dayPart(startHour: 18, endHour: 24))
}

/// Новые ачивки фазы 5 — в конце своей категории, в порядке плана, со значками из плана.
@Test func phaseFiveAchievementsAreAppendedWithPlannedIcons() {
    let planned: [(id: String, category: AchievementCategory, icon: String)] = [
        ("streak.fire_month", .streak, "flame.circle.fill"), ("streak.insurance", .streak, "umbrella.fill"),
        ("speed.growth.150", .speed, "chart.line.uptrend.xyaxis"),
        ("speed.growth.200", .speed, "arrow.up.right.circle.fill"),
        ("accuracy.all_fingers", .accuracy, "hand.raised.fill"),
        ("volume.exercises.100", .volume, "checklist"), ("volume.exercises.500", .volume, "list.bullet.clipboard"),
        ("volume.exercises.1000", .volume, "list.star"), ("volume.books.5", .volume, "book"),
        ("volume.books.25", .volume, "books.vertical"),
        ("special.weak_spot", .special, "bandage"), ("special.weak_spot.10", .special, "cross.case.fill"),
        ("special.own_words", .special, "text.quote"),
        ("fun.pi", .fun, "function"), ("fun.answer42", .fun, "number.circle"), ("fun.yo_master", .fun, "textformat"),
        ("fun.learning_from_mistakes", .fun, "xmark.circle"), ("fun.cinderella", .fun, "wand.and.stars"),
        ("fun.friday_night", .fun, "music.note"), ("fun.weekend_warrior", .fun, "figure.strengthtraining.traditional"),
        ("fun.almost", .fun, "smallcircle.filled.circle"),
    ]
    // Ачивки следующих подфаз (6d…) стоят после ачивок фазы 5.
    let later = Set<String>(["time.morning", "time.afternoon", "time.evening",
                              "habit.visits.2", "habit.visits.3", "habit.visits.5",
                              "speed.record", "course.stage", "course.five_stars", "course.speed_tier", "plan.week",
                              "fun.vibe_coder.ru", "fun.vibe_coder.en",
                              "volume.chars.500k", "volume.exercises.2500", "volume.exercises.4000",
                              "accuracy.surgeon.50", "accuracy.sniper.100", "accuracy.clean_day.100",
                              "habit.goal.x2", "habit.goal.x3", "fun.slow_steady", "course.first_try",
                              "fingers.all_eight", "streak.repair", "challenge.week", "challenge.month"])
        .union(AchievementCatalog.all.map(\.id).filter { $0.hasPrefix("distance.") })
    for category in AchievementCategory.allCases {
        let added = planned.filter { $0.category == category }
        let inCategory = AchievementCatalog.all.filter { $0.category == category && !later.contains($0.id) }
        let tail = inCategory.suffix(added.count)
        #expect(tail.map(\.id) == added.map(\.id), "\(category)")
        #expect(tail.map(\.icon) == added.map(\.icon), "\(category)")
    }
    let secret = Set(AchievementCatalog.all.filter(\.secret).map(\.id))
    for item in planned { #expect(secret.contains(item.id) == (item.category == .fun), "\(item.id)") }
}

/// Время суток и заходы (6d): значки из плана, `special`, повторяемые, кроме разовой секретной `habit.visits.5`.
@Test func timeOfDayAndVisitAchievementsMatchThePlan() throws {
    let planned: [(id: String, icon: String, condition: AchievementCondition, secret: Bool)] = [
        ("time.morning", "sunrise", .dayPart(startHour: 5, endHour: 12), false),
        ("time.afternoon", "sun.max", .dayPart(startHour: 12, endHour: 18), false),
        ("time.evening", "sunset", .dayPart(startHour: 18, endHour: 24), false),
        ("habit.visits.2", "2.circle.fill", .visits(2), false),
        ("habit.visits.3", "3.circle.fill", .visits(3), false),
        ("habit.visits.5", "5.circle.fill", .visits(5), true),
    ]
    for item in planned {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == item.id })
        #expect(achievement.category == .special && !achievement.adult)
        #expect(achievement.icon == item.icon && achievement.condition == item.condition)
        #expect(achievement.secret == item.secret)
        #expect(achievement.repeatable == (item.id != "habit.visits.5"), "«\(item.id)»")
    }
    // Значки не повторяют чужие.
    let icons = AchievementCatalog.all.map(\.icon)
    for item in planned { #expect(icons.filter { $0 == item.icon }.count == 1, "значок «\(item.icon)» занят") }
}

/// Повторяемые ачивки каталога: прежние ачивки времени суток и новые из 6d; id и условия прежних не менялись.
@Test func repeatableAchievementsAreTheTimeOfDayAndVisitOnes() {
    let repeatable = Set(AchievementCatalog.all.filter(\.repeatable).map(\.id))
    #expect(repeatable == ["special.night_owl", "special.early_bird", "fun.no_coffee", "fun.friday_night",
                           "time.morning", "time.afternoon", "time.evening", "habit.visits.2", "habit.visits.3",
                           "speed.record", "course.stage", "course.five_stars", "course.speed_tier", "plan.week",
                           "habit.goal.x2", "habit.goal.x3", "fun.slow_steady", "course.first_try",
                           "streak.repair", "challenge.week", "challenge.month"])
}

/// Починка серии (6e): последняя в блоке серии (после «Страхового случая»), повторяемая, значок пластыря.
@Test func streakRepairAchievementMatchesThePlan() throws {
    let achievement = try #require(AchievementCatalog.all.first { $0.id == "streak.repair" })
    #expect(achievement.category == .streak && achievement.icon == "bandage.fill")
    #expect(achievement.condition == .streakRepair)
    #expect(achievement.repeatable && !achievement.secret && !achievement.adult)
    #expect(AchievementCatalog.all.filter { $0.category == .streak }.last?.id == "streak.repair")
    #expect(AchievementCatalog.all.filter { $0.icon == "bandage.fill" }.count == 1)
    #expect(AchievementCatalog.all.count == 162)
}

/// Испытания недели и месяца (6e): последние в `special`, повторяемые, значки свободны (у плана — `flag.checkered` и
/// `calendar.badge.checkmark` заняты ачивками «Первый этап» и «30 дней»).
@Test func challengeAchievementsMatchThePlan() throws {
    let planned: [(id: String, icon: String, condition: AchievementCondition)] = [
        ("challenge.week", "checkmark.circle.fill", .challengeWeek), ("challenge.month", "calendar.circle.fill", .challengeMonth),
    ]
    let icons = AchievementCatalog.all.map(\.icon)
    for item in planned {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == item.id })
        #expect(achievement.category == .special && achievement.icon == item.icon)
        #expect(achievement.condition == item.condition)
        #expect(achievement.repeatable && !achievement.secret && !achievement.adult)
        #expect(icons.filter { $0 == item.icon }.count == 1, "значок «\(item.icon)» занят")
    }
    #expect(AchievementCatalog.all.filter { $0.category == .special }.suffix(2).map(\.id)
            == ["challenge.week", "challenge.month"])
    #expect(AchievementCatalog.all.count == 162)
}

/// Рекорд, этапы, пять звёзд, ступени и неделя по плану (6d): категории, значки, условия и повторяемость.
@Test func recordCourseAndPlanAchievementsMatchThePlan() throws {
    let planned: [(id: String, category: AchievementCategory, icon: String, condition: AchievementCondition)] = [
        ("speed.record", .speed, "gauge.with.dots.needle.100percent", .speedRecord),
        ("course.stage", .course, "flag.2.crossed.fill", .stagePassed),
        ("course.five_stars", .course, "trophy.fill", .lessonStars(5)),
        ("course.speed_tier", .course, "stairs", .tierPassed),
        ("plan.week", .special, "calendar.badge.clock", .planWeek(days: 7)),
    ]
    let icons = AchievementCatalog.all.map(\.icon)
    for item in planned {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == item.id })
        #expect(achievement.category == item.category && achievement.icon == item.icon)
        #expect(achievement.condition == item.condition)
        #expect(achievement.repeatable && !achievement.secret && !achievement.adult)
        #expect(icons.filter { $0 == item.icon }.count == 1, "значок «\(item.icon)» занят")
    }
    // Новые ачивки стоят в хвосте своей категории (после прежних), а у «Скорости» — после ступеней роста.
    #expect(AchievementCatalog.all.filter { $0.category == .speed }.last?.id == "speed.record")
    #expect(AchievementCatalog.all.filter { $0.category == .course }.suffix(4).map(\.id)
            == ["course.stage", "course.five_stars", "course.speed_tier", "course.first_try"])
    #expect(AchievementCatalog.all.filter { $0.category == .special }.suffix(5).map(\.id)
            == ["plan.week", "habit.goal.x2", "habit.goal.x3", "challenge.week", "challenge.month"])
}

@Test func categoriesKeepTheirOrderWithMilestonesAfterTheCourse() {
    #expect(AchievementCategory.allCases == [.streak, .speed, .accuracy, .course, .milestone, .volume, .special,
                                             .letters, .fun, .rhythm, .trainings])
}

/// Ступени «Искры» (6c): разовые ачивки серии после `streak.365`, не секретные, со значками из плана.
@Test func sparkAchievementsAreStreakCategoryWithPlannedIcons() throws {
    let planned: [(id: String, days: Int, icon: String)] = [
        ("spark.7", 7, "sparkle"), ("spark.30", 30, "sparkles"),
        ("spark.100", 100, "wand.and.stars"), ("spark.365", 365, "sparkles.rectangle.stack"),
    ]
    let streak = AchievementCatalog.all.filter { $0.category == .streak }
    let start = try #require(streak.firstIndex { $0.id == "streak.365" }) + 1
    #expect(streak[start..<(start + planned.count)].map(\.id) == planned.map(\.id))
    for item in planned {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == item.id })
        #expect(achievement.category == .streak && !achievement.secret && !achievement.adult)
        #expect(achievement.condition == .sparkStreak(days: item.days))
        #expect(achievement.icon == item.icon)
    }
}

/// Условия-просьбы («Откройте буквы…») у полученной ачивки читаются утверждением («Открыты буквы…»).
@Test func earnedConditionTextIsAStatementForImperativeConditions() throws {
    func text(_ id: String, _ language: String, earned: Bool) throws -> String {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == id })
        return AchievementConditionText.describe(achievement.condition, display: achievement.lettersDisplay,
                                                 localization: language, earned: earned)
    }
    #expect(try text("letters.ru.pizza", "ru", earned: true).hasPrefix("Открыты буквы"))
    #expect(try text("letters.ru.pizza", "ru", earned: true) == "Открыты буквы: П И Ц А")
    #expect(try text("letters.ru.pizza", "ru", earned: false) == "Откройте буквы: П И Ц А")
    #expect(try text("letters.en.pizza", "en", earned: true).hasPrefix("Letters opened"))
    #expect(try text("course.first_lesson", "ru", earned: true) == "Пройден первый урок курса")
    // Нейтральные условия вид не меняют.
    for id in ["streak.7", "speed.ru.150", "volume.hours.10", "fun.ctrl_z", "accuracy.sniper"] {
        for language in ["ru", "en"] {
            #expect(try text(id, language, earned: true) == text(id, language, earned: false), "\(language) \(id)")
        }
    }
}

/// У каждого условия-просьбы есть утверждение в обоих языках, и других `earned`-ключей в ресурсах нет.
@Test func everyEarnedFormExistsInBothLanguages() throws {
    let prefix = "achievement.condition."
    for language in ["ru", "en"] {
        let table = try strings(language)
        for key in AchievementConditionText.earnedForms {
            let plain = try #require(table[prefix + key], "\(language): нет «\(prefix + key)»")
            let earned = try #require(table[prefix + "earned." + key], "\(language): нет «\(prefix)earned.\(key)»")
            #expect(!earned.isEmpty && earned != plain, "\(language): «\(key)» не отличается от просьбы")
            #expect(earned.components(separatedBy: "%").count == plain.components(separatedBy: "%").count,
                    "\(language): «\(key)» — другое число подстановок")
            #expect(cyrillicWords(earned).allSatisfy { language == "ru" || $0.count == 1 }, "\(language): «\(earned)»")
        }
        let stored = Set(table.keys.filter { $0.hasPrefix(prefix + "earned.") }.map { String($0.dropFirst((prefix + "earned.").count)) })
        #expect(stored == AchievementConditionText.earnedForms, "\(language): \(stored.symmetricDifference(AchievementConditionText.earnedForms))")
    }
}

/// Вехи курса, английский алфавит и «Вайбкодер» (6d, Task 4): место в каталоге, значки, условия, секретность.
@Test func milestoneAchievementsMatchThePlan() throws {
    let planned: [(id: String, icon: String, condition: AchievementCondition)] = [
        ("milestone.ru.digits", "textformat.123", .keysUnlocked(.ru, .digits)),
        ("milestone.en.digits", "123.rectangle", .keysUnlocked(.en, .digits)),
        ("milestone.ru.symbols", "at", .keysUnlocked(.ru, .symbols)),
        ("milestone.en.symbols", "number.square", .keysUnlocked(.en, .symbols)),
        ("milestone.first_clean_text", "text.badge.checkmark", .cleanText(minChars: 200, hard: false)),
        ("milestone.first_hard_text", "text.badge.star", .cleanText(minChars: 200, hard: true)),
        ("milestone.first_long_text", "doc.plaintext", .cleanText(minChars: 600, hard: false)),
        ("milestone.first_blind_check", "eye.slash.circle", .blindStageCheck),
        ("milestone.first_plan", "checklist.checked", .firstPlanDay),
        ("milestone.first_tier", "arrow.up.forward.circle", .firstTier),
    ]
    let milestones = AchievementCatalog.all.filter { $0.category == .milestone }
    // Уровни (6e) стоят в конце категории после вех курса.
    #expect(milestones.map(\.id) == planned.map(\.id) + ["level.10", "level.30", "level.45"])
    let icons = AchievementCatalog.all.map(\.icon)
    for item in planned {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == item.id })
        #expect(achievement.icon == item.icon && achievement.condition == item.condition, "«\(item.id)»")
        #expect(!achievement.repeatable && !achievement.secret && !achievement.adult, "«\(item.id)»")
        #expect(icons.filter { $0 == item.icon }.count == 1, "значок «\(item.icon)» занят")
    }
    // Вехи идут сразу после «Курса»; английский алфавит — следом за русским.
    let all = AchievementCatalog.all.map(\.id)
    #expect(all.firstIndex(of: "milestone.ru.digits") == all.firstIndex(of: "course.first_try").map { $0 + 1 })
    #expect(all.firstIndex(of: "letters.en.alphabet") == all.firstIndex(of: "letters.ru.alphabet").map { $0 + 1 })
    let alphabet = try #require(AchievementCatalog.all.first { $0.id == "letters.en.alphabet" })
    #expect(alphabet.category == .letters && alphabet.condition == .wholeAlphabet(.en))
    #expect(alphabet.icon == "textformat.abc" && icons.filter { $0 == "textformat.abc" }.count == 1)
    #expect(!alphabet.secret && !alphabet.repeatable)
}

@Test func vibeCoderAchievementsAreSecretFunLetterConditionsThatDoNotShowTheWords() throws {
    let planned: [(id: String, language: Language, words: String, icon: String)] = [
        ("fun.vibe_coder.ru", .ru, "сделай исправь продолжай давай", "moon.zzz"),
        ("fun.vibe_coder.en", .en, "fix check make refactor", "cpu"),
    ]
    let all = AchievementCatalog.all.filter { $0.category == .fun }.map(\.id)
    #expect(Array(all.suffix(3).prefix(2)) == planned.map(\.id), "«Вайбкодер» — перед идеей пользователя в конце «Забав»")
    let icons = AchievementCatalog.all.map(\.icon)
    for item in planned {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == item.id })
        #expect(achievement.category == .fun && achievement.secret && !achievement.adult && !achievement.repeatable)
        #expect(achievement.condition == .lettersUnlocked(item.language, Set(item.words.filter { $0 != " " })))
        #expect(achievement.lettersDisplay == item.words)
        #expect(achievement.icon == item.icon && icons.filter { $0 == item.icon }.count == 1)
    }
}

/// Дистанция, объём и новые ступени (6d, Task 5): место в каталоге, значки, условия, не секретные и не повторяемые.
@Test func distanceStepsAndVolumeAchievementsMatchThePlan() throws {
    let all = AchievementCatalog.all
    let ids = all.map(\.id)
    func position(_ id: String) throws -> Int { try #require(ids.firstIndex(of: id), "нет «\(id)»") }
    // Ступени §8.6 — сразу после своей ачивки; объём — внутри своей лестницы.
    #expect(try position("accuracy.sniper.100") == position("accuracy.sniper") + 1)
    #expect(try position("accuracy.surgeon.50") == position("accuracy.surgeon") + 1)
    #expect(try position("accuracy.clean_day.100") == position("accuracy.clean_day") + 1)
    #expect(try position("volume.chars.500k") == position("volume.chars.100k") + 1)
    #expect(try position("volume.chars.1m") == position("volume.chars.500k") + 1)
    #expect(try position("volume.exercises.2500") == position("volume.exercises.1000") + 1)
    #expect(try position("volume.exercises.4000") == position("volume.exercises.2500") + 1)
    // Дистанция — в «Объёме», после всех прежних ачивок категории, лесенками по §8.5.
    let volume = all.filter { $0.category == .volume }
    let distance = all.filter { $0.id.hasPrefix("distance.") }
    #expect(distance.count == 17)
    #expect(Array(volume.suffix(distance.count)).map(\.id) == distance.map(\.id))
    #expect(distance.allSatisfy { $0.category == .volume })
    #expect(distance.map(\.id).first == "distance.space.75k" && distance.map(\.id).last == "distance.plans.300")
    let conditions: [(String, AchievementCondition, String)] = [
        ("volume.chars.500k", .volumeChars(500_000), "doc.on.doc"),
        ("volume.exercises.2500", .exercisesCompleted(2500), "gearshape.2"),
        ("volume.exercises.4000", .exercisesCompleted(4000), "building.2"),
        ("accuracy.sniper.100", .perfectCount(100), "target"),
        ("accuracy.surgeon.50", .accuracyRun(count: 50, minimum: 0.98), "cross.circle.fill"),
        ("accuracy.clean_day.100", .cleanDays(count: 100, exercises: 5, minimum: 0.97), "sparkle.magnifyingglass"),
        ("distance.space.75k", .distance(.spaces, 75_000), "space"),
        ("distance.space.100k", .distance(.spaces, 100_000), "arrow.left.and.right.square"),
        ("distance.space.150k", .distance(.spaces, 150_000), "moon.stars"),
        ("distance.pinky.45k", .distance(.pinkies, 45_000), "hand.point.up.fill"),
        ("distance.pinky.60k", .distance(.pinkies, 60_000), "dumbbell.fill"),
        ("distance.pinky.85k", .distance(.pinkies, 85_000), "medal"),
        ("distance.training.100", .distance(.trainings, 100), "figure.walk"),
        ("distance.training.300", .distance(.trainings, 300), "figure.strengthtraining.functional"),
        ("distance.training.500", .distance(.trainings, 500), "figure.highintensity.intervaltraining"),
        ("distance.lessons.100", .distance(.lessons, 100), "graduationcap.fill"),
        ("distance.lessons.200", .distance(.lessons, 200), "studentdesk"),
        ("distance.lessons.300", .distance(.lessons, 300), "building.columns"),
        ("distance.texts.100", .distance(.texts, 100), "book.closed"),
        ("distance.texts.200", .distance(.texts, 200), "newspaper.fill"),
        ("distance.texts.300", .distance(.texts, 300), "text.book.closed.fill"),
        ("distance.plans.100", .distance(.plans, 100), "list.clipboard"),
        ("distance.plans.300", .distance(.plans, 300), "calendar.day.timeline.left"),
    ]
    let icons = all.map(\.icon)
    for (id, condition, icon) in conditions {
        let achievement = try #require(all.first { $0.id == id })
        #expect(achievement.condition == condition && achievement.icon == icon, "«\(id)»")
        #expect(!achievement.secret && !achievement.adult && !achievement.repeatable, "«\(id)»")
        #expect(icons.filter { $0 == icon }.count == 1, "значок «\(icon)» занят")
    }
    // Названия не повторяют друг друга (у книг уже есть «Книжный червь» и «Библиотекарь»).
    let ru = try strings("ru")
    let titles = all.compactMap { ru[$0.titleKey] }
    #expect(Set(titles).count == titles.count - 1, "повторяются только «Вайбкодер» RU и EN")
}

/// Идеи пользователя и «Восемь пальцев» (6d, решение 18): значки, условия и повторяемость.
@Test func userIdeaAchievementsMatchThePlan() throws {
    let planned: [(id: String, category: AchievementCategory, icon: String, condition: AchievementCondition,
                   repeatable: Bool, secret: Bool)] = [
        ("habit.goal.x2", .special, "2.square.fill", .goalMultiple(2), true, false),
        ("habit.goal.x3", .special, "3.square.fill", .goalMultiple(3), true, false),
        ("fun.slow_steady", .fun, "tortoise.fill", .slowAndSteady, true, true),
        ("course.first_try", .course, "hand.thumbsup.fill", .firstTry, true, false),
        ("fingers.all_eight", .accuracy, "hands.clap.fill", .allFingersDrilled, false, false),
    ]
    let icons = AchievementCatalog.all.map(\.icon)
    for item in planned {
        let achievement = try #require(AchievementCatalog.all.first { $0.id == item.id })
        #expect(achievement.category == item.category && achievement.icon == item.icon, "«\(item.id)»")
        #expect(achievement.condition == item.condition && !achievement.adult, "«\(item.id)»")
        #expect(achievement.repeatable == item.repeatable && achievement.secret == item.secret, "«\(item.id)»")
        #expect(icons.filter { $0 == item.icon }.count == 1, "значок «\(item.icon)» занят")
    }
    #expect(AchievementCatalog.all.filter { $0.category == .accuracy }.last?.id == "fingers.all_eight")
    #expect(AchievementCatalog.all.filter { $0.category == .fun }.last?.id == "fun.slow_steady")
}
