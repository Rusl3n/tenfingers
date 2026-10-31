import Foundation

/// Условие получения ачивки человеческими словами: его показывают у ещё не полученных ачивок
/// (у «Теперь вы можете…» — вместо шутки, которая раскрыла бы ответ). Чистая функция условия.
///
/// У условий, которые звучат как просьба («Пройдите первый урок»), есть второй вид — утверждение для уже полученной
/// ачивки («Пройден первый урок курса»): ключи `achievement.condition.earned.*`, их список — `earnedForms`. У прочих
/// условий (нейтральные «Дней занятий подряд: 7») вид один.
///
/// Тексты без склонения числительных: число стоит после двоеточия («Дней занятий подряд: 7»), поэтому
/// одна строка подходит любому значению порога. Ключи — `achievement.condition.*` в ресурсах ядра.
public enum AchievementConditionText {
    /// Ключи условий, у которых есть вид-утверждение (`achievement.condition.earned.<ключ>`): те, чей обычный
    /// текст — просьба. Остальные условия нейтральны, и для них `earned` ничего не меняет.
    public static let earnedForms: Set<String> = [
        "firstLesson", "firstStage", "course", "polyglot", "finishedBetween", "dayPart",
        "lettersOne", "lettersMany", "symbols", "alphabet", "dayOfYear", "friday13", "comeback",
        "ownText", "atMinute", "fridayEvening", "exactSpeed", "allFingersDrilled",
    ]

    /// `localization` — `"ru"` или `"en"`; `nil` — язык системы. `display` — буквы условия в естественном порядке
    /// (слово или команда); без него буквы идут в адаптивном порядке языка. `earned` — условие как утверждение
    /// для полученной ачивки («Пройден первый урок курса»), а не просьба («Пройдите первый урок курса»).
    public static func describe(_ condition: AchievementCondition, display: String? = nil,
                                localization: String? = nil, earned: Bool = false) -> String {
        func text(_ key: String) -> String {
            let name = earned && earnedForms.contains(key) ? "earned." + key : key
            return CoreText.localized("achievement.condition." + name, localization: localization)
        }
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
        case .sparkStreak(let days): return line("sparkStreak", days)
        case .speed(let language, let cpm): return line("speed", name(language), cpm, Analytics.recordMinimumChars)
        case .perfectAccuracy: return line("perfectAccuracy", Analytics.recordMinimumChars)
        case .accuracyRun(let count, let minimum): return line("accuracyRun", percent(minimum), count)
        case .cleanDay(let exercises, let minimum): return line("cleanDay", exercises, percent(minimum))
        case .firstLesson: return text("firstLesson")
        case .firstStage: return text("firstStage")
        case .courseCompleted(let language): return line("course", name(language))
        case .polyglot: return text("polyglot")
        case .allLessonsExcellent(let language): return line("excellentStars", name(language))
        case .volumeChars(let count): return line("volumeChars", integer(count))
        case .volumeHours(let hours): return line("volumeHours", number(hours))
        case .finishedBetween(let start, let end): return line("finishedBetween", start, end)
        case let .dayPart(start, end): return line("dayPart", start, end - 1)
        case .visits(let count): return line("visits", count)
        case .speedRecord: return line("speedRecord", Analytics.recordMinimumChars)
        case .stagePassed: return text("stagePassed")
        case .lessonStars(let stars): return line("lessonStars", String(repeating: "★", count: stars))
        case .tierPassed: return text("tierPassed")
        case .planWeek(let days): return line("planWeek", days)
        case let .keysUnlocked(language, group):
            return line(group == .digits ? "keysDigits" : "keysSymbols", name(language))
        case let .cleanText(minChars, hard): return line(hard ? "hardText" : "cleanText", minChars)
        case .blindStageCheck: return text("blindStageCheck")
        case .firstPlanDay: return text("firstPlanDay")
        case .firstTier: return text("firstTier")
        case let .distance(kind, count):
            let key: String
            switch kind {
            case .spaces: key = "distance.spaces"
            case .pinkies: key = "distance.pinkies"
            case .trainings: key = "distance.trainings"
            case .lessons: key = "distance.lessons"
            case .texts: key = "distance.texts"
            case .plans: key = "distance.plans"
            }
            return kind == .texts ? line(key, Analytics.recordMinimumChars, integer(count)) : line(key, integer(count))
        case .perfectCount(let count): return line("perfectCount", Analytics.recordMinimumChars, count)
        case let .cleanDays(count, exercises, minimum): return line("cleanDays", count, exercises, percent(minimum))
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
        case .exercisesCompleted(let count): return line("exercises", integer(count))
        case let .speedGrowth(factor, minExercises): return line("speedGrowth", number(factor), minExercises)
        case let .allFingersAccuracy(minimum, presses, days): return line("allFingers", days, percent(minimum), presses)
        case let .weakSpotsClean(count, minimum): return line("weakSpots", percent(minimum), count)
        case .booksFinished(let count): return line("books", count)
        case .ownText: return text("ownText")
        case .fullFireMonth: return text("fireMonth")
        case .freezeSavedStreak: return text("freezeSaved")
        case .exactSpeed(let cpm): return line("exactSpeed", cpm)
        case .exactSeconds(let seconds): return line("exactSeconds", seconds)
        case .yoPresses(let count): return line("yoPresses", count)
        case .totalErrors(let count): return line("totalErrors", integer(count))
        case let .finishedAtMinute(hour, minute): return line("atMinute", hour, minute)
        case .fridayEvening(let fromHour): return line("fridayEvening", fromHour)
        case .weekendStreak(let count): return line("weekends", count)
        case let .almostPerfect(minChars, minimum): return line("almost", minChars, percent(minimum))
        case .goalMultiple(let factor): return line("goalMultiple", factor)
        case .slowAndSteady: return text("slowAndSteady")
        case .firstTry: return text("firstTry")
        case .allFingersDrilled: return text("allFingersDrilled")
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

    /// Условие как утверждение для полученной ачивки («Пройден первый урок курса»); у нейтральных условий
    /// совпадает с `conditionText`.
    public var earnedConditionText: String {
        AchievementConditionText.describe(condition, display: lettersDisplay, earned: true)
    }
}
