import Foundation
import TypingCore

/// Названия «года» (6e) — испытаний, званий уровней и рангов скорости — в одном месте: ядро отдаёт перечисления,
/// строки приложения живут в `Localization/{ru,en}.lproj`. Ими пользуются тосты, главная и аналитика.
enum YearText {
    static func title(_ id: ChallengeId) -> String {
        switch id {
        case .weekGoal5: String(localized: "Пять целей")
        case .weekVisit7: String(localized: "Без пропусков")
        case .weekChars: String(localized: "Знаки")
        case .weekClean: String(localized: "Чистая работа")
        case .weekStars: String(localized: "Звездопад")
        case .weekTimes: String(localized: "Утро, день, вечер")
        case .weekVisits: String(localized: "Двойной заход")
        case .weekSpeed: String(localized: "Быстрее себя")
        case .weekReview: String(localized: "Работа над ошибками")
        case .weekPlan: String(localized: "По плану")
        case .firstDays: String(localized: "3 дня с занятиями")
        case .firstLessons: String(localized: "3 урока")
        case .firstGoal: String(localized: "1 день с целью")
        case .monthGoal20: String(localized: "Двадцать целей")
        case .monthVisit28: String(localized: "Почти каждый день")
        case .monthChars: String(localized: "Большой объём")
        case .monthStage: String(localized: "Новый этап")
        case .monthGrowth: String(localized: "Рост")
        }
    }

    static func title(_ title: LevelTitle) -> String {
        switch title {
        case .novice: String(localized: "Новичок")
        case .apprentice: String(localized: "Ученик")
        case .confident: String(localized: "Уверенный")
        case .master: String(localized: "Мастер")
        case .virtuoso: String(localized: "Виртуоз")
        case .legend: String(localized: "Легенда")
        }
    }

    static func title(_ rank: SpeedRank) -> String {
        switch rank {
        case .pedestrian: String(localized: "Пешеход")
        case .cyclist: String(localized: "Велосипедист")
        case .driver: String(localized: "Водитель")
        case .racer: String(localized: "Гонщик")
        case .pilot: String(localized: "Пилот")
        case .rocket: String(localized: "Ракета")
        }
    }

    /// «Уровень 12 · Ученик».
    static func levelLine(level: Int, title: LevelTitle) -> String {
        let name = Self.title(title)
        return String(localized: "Уровень \(level) · \(name)")
    }

    /// Условие испытания одной строкой, с числами периода: «Наберите 5 000 знаков», «Скорость от 132 зн/мин» (единица —
    /// из настроек). Числа знаков берутся из цели испытания (G и C уже учтены в ней), порог скорости — из C периода.
    static func condition(_ result: ChallengeResult, parameters: ChallengeParameters, unit: SpeedUnit,
                          bundle: Bundle = .main, locale: Locale = Formatting.interfaceLocale()) -> String {
        let days = Formatting.days(result.target, bundle: bundle, locale: locale)
        switch result.id {
        case .weekGoal5, .monthGoal20: return String(localized: "\(days) с полным огнём", bundle: bundle, locale: locale)
        case .weekVisit7, .monthVisit28: return String(localized: "\(days) с занятиями", bundle: bundle, locale: locale)
        case .weekChars, .monthChars:
            let chars = result.target.formatted(.number.locale(locale))
            return String(localized: "Наберите \(chars) знаков", bundle: bundle, locale: locale)
        case .weekClean:
            return String(localized: "5 упражнений от 100 знаков без единой ошибки", bundle: bundle, locale: locale)
        case .weekStars: return String(localized: "Новые звёзды в 3 уроках", bundle: bundle, locale: locale)
        case .weekTimes: return String(localized: "Занятия утром, днём и вечером", bundle: bundle, locale: locale)
        case .weekVisits: return String(localized: "2 дня с двумя заходами", bundle: bundle, locale: locale)
        case .weekSpeed:
            let speed = unit.format(parameters.cpm * 1.1, rounding: .up)
            return String(localized: "Скорость от \(speed)", bundle: bundle, locale: locale)
        case .weekReview:
            return String(localized: "3 упражнения «Освежить» или «Повтор»", bundle: bundle, locale: locale)
        case .weekPlan: return String(localized: "4 дня с выполненным планом", bundle: bundle, locale: locale)
        case .firstDays: return String(localized: "Занимайтесь в разные дни", bundle: bundle, locale: locale)
        case .firstLessons: return String(localized: "Пройдите проверки уроков курса", bundle: bundle, locale: locale)
        case .firstGoal: return String(localized: "Наберите время дневной цели", bundle: bundle, locale: locale)
        case .monthStage: return String(localized: "Возьмите порог этапа курса", bundle: bundle, locale: locale)
        case .monthGrowth:
            return String(localized: "Средняя скорость выше, чем в прошлом месяце, в 1,05 раза", bundle: bundle, locale: locale)
        }
    }
}
