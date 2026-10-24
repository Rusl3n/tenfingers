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

/// Все 89 id как есть в базах пользователей: переименование или удаление должно ронять тест
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
]

@Test func catalogIdsMatchTheGoldenList() {
    let ids = AchievementCatalog.all.map(\.id)
    #expect(goldenIds.count == 89 && Set(goldenIds).count == 89)
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
        case .speed(let language, let cpm):
            #expect(id == "speed.\(language.rawValue).\(cpm)")
        case .volumeChars(let count):
            let suffix = count % 1_000_000 == 0 ? "\(count / 1_000_000)m" : "\(count / 1000)k"
            #expect(id == "volume.chars.\(suffix)", "«\(id)»: \(count)")
        case .volumeHours(let hours):
            #expect(id == "volume.hours.\(Int(hours))")
        case .lettersUnlocked(let language, _), .wholeAlphabet(let language):
            #expect(parts.count == 3 && parts[0] == "letters" && parts[1] == language.rawValue, "«\(id)»")
        case .courseCompleted(let language):
            #expect(id == "course.\(language.rawValue)")
        case .allThreeStars(let language):
            #expect(id == "course.stars.\(language.rawValue)")
        case .speedGrowth(let factor, _):
            #expect(id == "speed.growth.\(Int((factor * 100).rounded()))", "«\(id)»: \(factor)")
        case .exercisesCompleted(let count):
            #expect(id == "volume.exercises.\(count)")
        case .booksFinished(let count):
            #expect(id == "volume.books.\(count)")
        case .weakSpotsClean(let count, _):
            // Первое чистое упражнение — `special.weak_spot` без числа, дальше — `special.weak_spot.<число>`.
            #expect(id == (count == 1 ? "special.weak_spot" : "special.weak_spot.\(count)"), "«\(id)»: \(count)")
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
        if id.hasPrefix("speed.growth.") {
            guard case .speedGrowth = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
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
            #expect(Set(display ?? "") == letters, "«\(achievement.id)»: \(display ?? "nil") ≠ \(letters)")
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
        .union(["special.night_owl", "special.early_bird"])
    #expect(secret == expected)
    #expect(secret.count == 28)
}

@Test func catalogMatchesSectionTwelveCounts() {
    func count(_ category: AchievementCategory) -> Int {
        AchievementCatalog.all.filter { $0.category == category }.count
    }
    #expect(count(.streak) == 11)
    #expect(count(.speed) == 12)
    #expect(count(.accuracy) == 4)
    #expect(count(.course) == 7)
    #expect(count(.volume) == 12)
    #expect(count(.special) == 7)
    #expect(count(.letters) == 16)
    #expect(count(.fun) == 20)
    #expect(AchievementCatalog.all.count == 89)
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
        #expect(achievement.category == .letters)
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
    for category in AchievementCategory.allCases {
        let added = planned.filter { $0.category == category }
        let inCategory = AchievementCatalog.all.filter { $0.category == category }
        let tail = inCategory.suffix(added.count)
        #expect(tail.map(\.id) == added.map(\.id), "\(category)")
        #expect(tail.map(\.icon) == added.map(\.icon), "\(category)")
    }
    let secret = Set(AchievementCatalog.all.filter(\.secret).map(\.id))
    for item in planned { #expect(secret.contains(item.id) == (item.category == .fun), "\(item.id)") }
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
