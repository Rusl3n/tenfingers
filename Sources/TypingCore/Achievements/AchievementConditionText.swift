import Foundation

/// Условие получения ачивки человеческими словами: его показывают у ещё не полученных ачивок
/// (у «Теперь вы можете…» — вместо шутки, которая раскрыла бы ответ). Чистая функция условия.
///
/// Тексты без склонения числительных: число стоит после двоеточия («Дней занятий подряд: 7»), поэтому
/// одна строка подходит любому значению порога. Ключи — `achievement.condition.*` в ресурсах ядра.
public enum AchievementConditionText {
    /// `localization` — `"ru"` или `"en"`; `nil` — язык системы. `display` — буквы условия в естественном порядке
    /// (слово или команда); без него буквы идут в адаптивном порядке языка.
    public static func describe(_ condition: AchievementCondition, display: String? = nil,
                                localization: String? = nil) -> String {
        func text(_ key: String) -> String { CoreText.localized("achievement.condition." + key, localization: localization) }
        func line(_ key: String, _ arguments: CVarArg...) -> String {
            String(format: text(key), arguments: arguments)
        }
        let locale = locale(for: localization)
        func number(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        }
        func integer(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
        func percent(_ fraction: Double) -> String { number(fraction * 100) + "%" }
        func name(_ language: Language) -> String { CoreText.localized(language.displayNameKey, localization: localization) }

        switch condition {
        case .streak(let days): return line("streak", days)
        case .fullStreakNoFreeze(let days): return line("fullStreak", days)
        case .speed(let language, let cpm): return line("speed", name(language), cpm, Analytics.recordMinimumChars)
        case .perfectAccuracy: return line("perfectAccuracy", Analytics.recordMinimumChars)
        case .accuracyRun(let count, let minimum): return line("accuracyRun", percent(minimum), count)
        case .cleanDay(let exercises, let minimum): return line("cleanDay", exercises, percent(minimum))
        case .firstLesson: return text("firstLesson")
        case .firstStage: return text("firstStage")
        case .courseCompleted(let language): return line("course", name(language))
        case .polyglot: return text("polyglot")
        case .allThreeStars(let language): return line("threeStars", name(language))
        case .volumeChars(let count): return line("volumeChars", integer(count))
        case .volumeHours(let hours): return line("volumeHours", number(hours))
        case .finishedBetween(let start, let end): return line("finishedBetween", start, end)
        case .noKeyboard: return line("noKeyboard", Analytics.recordMinimumChars)
        case .steelPinkies(let presses): return line("steelPinkies", presses)
        case .lettersUnlocked(let language, let characters):
            let listed = ordered(characters, language: language, display: display)
            let isLetters = characters.allSatisfy(\.isLetter)
            let key = isLetters ? (characters.count == 1 ? "lettersOne" : "lettersMany") : "symbols"
            return line(key, listed.joined(separator: " "))
        case .wholeAlphabet(let language): return line("alphabet", name(language))
        case .counter(let name, let threshold):
            switch name {
            case "wrongLayoutStarts": return line("wrongLayout", threshold)
            case "capsLockPresses": return line("capsLock", threshold)
            default: return line("counter", threshold)
            }
        case .errorStreak(let count): return line("errorStreak", count)
        case .errorsInExercise(let count): return line("errorsInExercise", count)
        case .lessonReplays(let count): return line("lessonReplays", count)
        case .abandonsInDay(let count): return line("abandonsInDay", count)
        case .dayOfYear(let month, let day): return line("dayOfYear", date(month: month, day: day, locale: locale))
        case .fridayThe13th: return text("friday13")
        case .bilingualDay: return text("bilingual")
        case .marathonDay(let minutes): return line("marathon", minutes)
        case .comeback(let gapDays): return line("comeback", gapDays)
        }
    }

    /// Знаки в порядке `display` (слово или команда, повторы пропускаются), в верхнем регистре; чего в `display`
    /// нет — после них в порядке `ordered(_:language:)`. Без `display` — только последний порядок.
    static func ordered(_ characters: Set<Character>, language: Language, display: String?) -> [String] {
        guard let display else { return ordered(characters, language: language) }
        var seen = Set<Character>()
        let named = display.filter { characters.contains($0) && seen.insert($0).inserted }
        let remaining = characters.subtracting(seen)
        return named.map { String($0).uppercased() } + ordered(remaining, language: language)
    }

    /// Буквы в порядке адаптивного режима языка (множество порядка не хранит), в верхнем регистре; прочие знаки
    /// (двоеточие, «!») — после букв, по коду.
    static func ordered(_ characters: Set<Character>, language: Language) -> [String] {
        let order = language.adaptiveOrder
        func rank(_ character: Character) -> Int? {
            order.firstIndex(of: Character(String(character).lowercased()))
        }
        let known = characters.compactMap { character in rank(character).map { (character, $0) } }
            .sorted { $0.1 < $1.1 }.map(\.0)
        let rest = characters.filter { rank($0) == nil }
            .sorted { String($0).unicodeScalars.first!.value < String($1).unicodeScalars.first!.value }
        return (known + rest).map { String($0).uppercased() }
    }

    private static func locale(for localization: String?) -> Locale {
        Locale(identifier: localization ?? CoreResources.bundle.preferredLocalizations.first ?? "en")
    }

    /// «1 января» / «January 1» (месяц и день без года).
    private static func date(month: Int, day: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        guard let date = calendar.date(from: DateComponents(year: 2024, month: month, day: day)) else {
            return "\(day).\(month)"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter.string(from: date)
    }
}

extension Achievement {
    /// Условие получения человеческими словами на языке системы (см. `AchievementConditionText`).
    public var conditionText: String {
        AchievementConditionText.describe(condition, display: lettersDisplay)
    }
}
