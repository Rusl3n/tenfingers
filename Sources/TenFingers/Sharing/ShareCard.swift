import Foundation
import TypingCore

/// Событие, которым можно поделиться картинкой-карточкой (§19).
enum ShareEvent: Equatable {
    /// Полученная ачивка и дата получения.
    case achievement(Achievement, Date)
    /// Серия занятий: дней подряд и сколько из них полных.
    case streak(days: Int, full: Int)
    /// Рекорд скорости (знаки в минуту) на языке и его дата.
    case speedRecord(Language, cpm: Double, date: Date)
    /// Пройден этап курса: id этапа и название (уже на языке интерфейса).
    case stage(id: String, title: String, language: Language)
    /// Пройден весь курс языка.
    case course(language: Language)

    /// Дата самого события; `nil` — событие «сейчас» (серия, этап, курс).
    var date: Date? {
        switch self {
        case .achievement(_, let date), .speedRecord(_, _, let date): date
        case .streak, .stage, .course: nil
        }
    }

    /// Имя SF Symbol крупной иконки карточки.
    var icon: String {
        switch self {
        case .achievement(let achievement, _): achievement.icon
        case .streak: "flame.fill"
        case .speedRecord: "speedometer"
        case .stage: "flag.checkered"
        case .course: "graduationcap.fill"
        }
    }

    /// Основа имени файла (ASCII): `tenfingers-streak-30`.
    var fileStem: String {
        switch self {
        case .achievement(let achievement, _): "tenfingers-achievement-\(achievement.id)"
        case .streak(let days, _): "tenfingers-streak-\(days)"
        case .speedRecord(let language, let cpm, _): "tenfingers-speed-\(language.rawValue)-\(Int(cpm.rounded()))"
        case .stage(let id, _, _): "tenfingers-stage-\(id)"
        case .course(let language): "tenfingers-course-\(language.rawValue)"
        }
    }

    /// Что предложить на экране итога урока: последний урок этапа пройден — этап, последний урок курса — курс.
    static func completion(course: Course, lessonId: String, stars: Int) -> ShareEvent? {
        guard stars > 0, let stage = course.stage(of: lessonId), stage.lessons.last?.id == lessonId else { return nil }
        if course.lessons.last?.id == lessonId { return .course(language: course.language) }
        return .stage(id: stage.id, title: stage.localizedTitle, language: course.language)
    }

    /// Повтор одного шага: этап или курс засчитывает только проверка (`stars` — её звёзды).
    static func stepCompletion(course: Course, lessonId: String, kind: ExerciseKind, stars: Int?) -> ShareEvent? {
        guard kind == .check, let stars else { return nil }
        return completion(course: course, lessonId: lessonId, stars: stars)
    }
}

/// Карточка к показу: событие и дата на ней (новый `id` на каждое открытие листа).
struct ShareCard: Identifiable, Equatable {
    let id = UUID()
    let event: ShareEvent
    let date: Date

    init(_ event: ShareEvent, now: Date = .now) {
        self.event = event
        self.date = event.date ?? now
    }

    var fileName: String { event.fileStem + ".png" }
}

/// Кем подписана карточка.
enum ShareSignature: String, CaseIterable, Identifiable {
    case nickname, fullName, both, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nickname: String(localized: "Никнейм")
        case .fullName: String(localized: "Имя")
        case .both: String(localized: "Никнейм и имя")
        case .none: String(localized: "Без подписи")
        }
    }
}

enum ShareTheme: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: String(localized: "Светлая")
        case .dark: String(localized: "Тёмная")
        }
    }
}

enum ShareBackground: String, CaseIterable, Identifiable {
    case colored, transparent
    var id: String { rawValue }

    var title: String {
        switch self {
        case .colored: String(localized: "Цветной")
        case .transparent: String(localized: "Прозрачный")
        }
    }
}

enum ShareFormat: String, CaseIterable, Identifiable {
    /// 1200×630 — превью ссылок в соцсетях.
    case wide
    /// 1080×1080 — квадрат.
    case square
    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .wide: CGSize(width: 1200, height: 630)
        case .square: CGSize(width: 1080, height: 1080)
        }
    }

    var title: String {
        switch self {
        case .wide: String(localized: "Широкая 1200×630")
        case .square: String(localized: "Квадрат 1080×1080")
        }
    }
}

/// Профиль для подписи: никнейм и имя из настроек (пробелы по краям отбрасываются).
struct ShareProfile: Equatable {
    let nickname: String
    let fullName: String

    init(nickname: String, fullName: String) {
        self.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stored(_ defaults: UserDefaults = .standard) -> ShareProfile {
        ShareProfile(nickname: defaults.string(forKey: SettingsKey.profileNickname) ?? "",
                     fullName: defaults.string(forKey: SettingsKey.profileFullName) ?? "")
    }

    var isEmpty: Bool { nickname.isEmpty && fullName.isEmpty }

    /// Варианты подписи, для которых в профиле есть данные; «Без подписи» — всегда.
    var available: [ShareSignature] {
        ShareSignature.allCases.filter { signature in
            switch signature {
            case .nickname: !nickname.isEmpty
            case .fullName: !fullName.isEmpty
            case .both: !nickname.isEmpty && !fullName.isEmpty
            case .none: true
            }
        }
    }

    /// По умолчанию — всё, что заполнено.
    var defaultSignature: ShareSignature {
        switch (nickname.isEmpty, fullName.isEmpty) {
        case (false, false): .both
        case (false, true): .nickname
        case (true, false): .fullName
        case (true, true): .none
        }
    }

    /// Строка подписи («Имя · никнейм») или `nil`, если подписывать нечем.
    func text(for signature: ShareSignature) -> String? {
        guard available.contains(signature) else { return nil }
        return switch signature {
        case .nickname: nickname
        case .fullName: fullName
        case .both: "\(fullName) · \(nickname)"
        case .none: nil
        }
    }
}

/// Настройки карточки; запоминаются между открытиями листа.
struct ShareOptions: Equatable {
    var signature: ShareSignature
    var theme: ShareTheme
    var background: ShareBackground
    var format: ShareFormat

    /// Сохранённые опции; подпись, для которой в профиле больше нет данных, — подпись по умолчанию.
    static func load(_ defaults: UserDefaults = .standard, profile: ShareProfile) -> ShareOptions {
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        let stored: ShareSignature? = defaults.string(forKey: SettingsKey.shareSignature).flatMap(ShareSignature.init(rawValue:))
        let signature = stored.flatMap { profile.available.contains($0) ? $0 : nil } ?? profile.defaultSignature
        return ShareOptions(signature: signature, theme: value(SettingsKey.shareTheme, ShareTheme.light),
                            background: value(SettingsKey.shareBackground, ShareBackground.colored),
                            format: value(SettingsKey.shareFormat, ShareFormat.wide))
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(signature.rawValue, forKey: SettingsKey.shareSignature)
        defaults.set(theme.rawValue, forKey: SettingsKey.shareTheme)
        defaults.set(background.rawValue, forKey: SettingsKey.shareBackground)
        defaults.set(format.rawValue, forKey: SettingsKey.shareFormat)
    }
}

/// Чем можно делиться: ачивки с `adult` при выключенном «Взрослом юморе» — нет.
enum ShareAvailability {
    static func canShare(_ achievement: Achievement, adultHumor: Bool) -> Bool {
        adultHumor || !achievement.adult
    }
}

/// Тексты карточки на языке интерфейса (`bundle` и `locale` подменяются в тестах и при рендере картинок README).
struct ShareCardText: Equatable {
    let header: String
    let headline: String
    let subtitle: String?
    let signature: String?
    let date: String
    let watermark: String

    init(card: ShareCard, options: ShareOptions, profile: ShareProfile, unit: SpeedUnit,
         bundle: Bundle = .main, locale: Locale? = nil) {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        switch card.event {
        case .achievement(let achievement, _):
            header = String(localized: "Новая ачивка", bundle: bundle, locale: locale)
            headline = achievement.title
            subtitle = achievement.detail
        case .streak(let days, let full):
            let count = Formatting.days(days, bundle: bundle, locale: locale)
            header = String(localized: "Серия занятий", bundle: bundle, locale: locale)
            headline = String(localized: "\(count) подряд", bundle: bundle, locale: locale)
            subtitle = String(localized: "Полных дней: \(full)", bundle: bundle, locale: locale)
        case .speedRecord(let language, let cpm, _):
            header = String(localized: "Рекорд скорости", bundle: bundle, locale: locale)
            headline = "\(unit.wholeValue(cpm))"
            subtitle = Self.speedSubtitle(unit: unit, language: language, bundle: bundle, locale: locale)
        case .stage(_, let title, let language):
            header = String(localized: "Этап пройден", bundle: bundle, locale: locale)
            headline = title
            subtitle = Self.layoutName(language, bundle: bundle, locale: locale)
        case .course(let language):
            header = String(localized: "Курс пройден", bundle: bundle, locale: locale)
            headline = Self.layoutName(language, bundle: bundle, locale: locale)
            subtitle = String(localized: "Все уроки курса пройдены", bundle: bundle, locale: locale)
        }
        signature = profile.text(for: options.signature)
        date = card.date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
        watermark = String(localized: "Десять пальцев · github.com/Rusl3n/tenfingers", bundle: bundle, locale: locale)
    }

    /// Текст «Поделиться…» к картинке.
    static func message(bundle: Bundle = .main) -> String {
        String(localized: "Учусь слепой печати в «Десять пальцев»", bundle: bundle)
    }

    private static func layoutName(_ language: Language, bundle: Bundle, locale: Locale) -> String {
        switch language {
        case .ru: String(localized: "Русская раскладка", bundle: bundle, locale: locale)
        case .en: String(localized: "Английская раскладка", bundle: bundle, locale: locale)
        }
    }

    private static func speedSubtitle(unit: SpeedUnit, language: Language, bundle: Bundle, locale: Locale) -> String {
        switch (unit, language) {
        case (.cpm, .ru): String(localized: "знаков в минуту, русская раскладка", bundle: bundle, locale: locale)
        case (.cpm, .en): String(localized: "знаков в минуту, английская раскладка", bundle: bundle, locale: locale)
        case (.wpm, .ru): String(localized: "слов в минуту, русская раскладка", bundle: bundle, locale: locale)
        case (.wpm, .en): String(localized: "слов в минуту, английская раскладка", bundle: bundle, locale: locale)
        }
    }
}
