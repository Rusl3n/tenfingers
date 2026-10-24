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

/// Все 68 id как есть в базах пользователей: переименование или удаление должно ронять тест
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
]

@Test func catalogIdsMatchTheGoldenList() {
    let ids = AchievementCatalog.all.map(\.id)
    #expect(goldenIds.count == 68 && Set(goldenIds).count == 68)
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
        default: break
        }
    }
    // Обратное направление: id с числом не должен остаться без условия-пары.
    for achievement in AchievementCatalog.all {
        let id = achievement.id
        if id.hasPrefix("streak.") && id != "streak.iron_will" {
            guard case .streak = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("speed.") {
            guard case .speed = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("volume.chars.") {
            guard case .volumeChars = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
        }
        if id.hasPrefix("volume.hours.") {
            guard case .volumeHours = achievement.condition else { Issue.record("«\(id)»: условие \(achievement.condition)"); continue }
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
}

@Test func catalogMatchesSectionTwelveCounts() {
    func count(_ category: AchievementCategory) -> Int {
        AchievementCatalog.all.filter { $0.category == category }.count
    }
    #expect(count(.streak) == 9)
    #expect(count(.speed) == 10)
    #expect(count(.accuracy) == 3)
    #expect(count(.course) == 7)
    #expect(count(.volume) == 7)
    #expect(count(.special) == 4)
    #expect(count(.letters) == 16)
    #expect(count(.fun) == 12)
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
    #expect(sniper.detail.contains("100%"), "знак процента не должен ломаться: «\(sniper.detail)»")
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
}
