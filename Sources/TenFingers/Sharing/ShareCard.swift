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
    /// «Сертификат»: курс издания 2 пройден, `averageCpm` — средняя скорость лучших проверок этапов (знаков в минуту,
    /// не ниже `Certificate.minimumAverageCpm`).
    case certificate(language: Language, averageCpm: Double)
    /// «Мой прогресс»: серия, календарь месяца или года и итоги периода.
    case progress(ProgressCardData)

    /// Дата самого события; `nil` — событие «сейчас» (серия, этап, курс).
    var date: Date? {
        switch self {
        case .achievement(_, let date), .speedRecord(_, _, let date): date
        case .streak, .stage, .course, .certificate, .progress: nil
        }
    }

    /// Имя SF Symbol крупной иконки карточки.
    var icon: String {
        switch self {
        case .achievement(let achievement, _): achievement.icon
        case .streak, .progress: "flame.fill"
        case .speedRecord: "speedometer"
        case .stage: "flag.checkered"
        case .course: "graduationcap.fill"
        case .certificate: "rosette"
        }
    }

    /// Данные календаря у «Мой прогресс».
    var progressData: ProgressCardData? {
        if case .progress(let data) = self { data } else { nil }
    }

    /// Основа имени файла (ASCII): `tenfingers-streak-30`.
    var fileStem: String {
        switch self {
        case .achievement(let achievement, _): "tenfingers-achievement-\(achievement.id)"
        case .streak(let days, _): "tenfingers-streak-\(days)"
        case .speedRecord(let language, let cpm, _): "tenfingers-speed-\(language.rawValue)-\(Int(cpm.rounded()))"
        case .stage(let id, _, _): "tenfingers-stage-\(id)"
        case .course(let language): "tenfingers-course-\(language.rawValue)"
        case .certificate(let language, _): "tenfingers-certificate-\(language.rawValue)"
        case .progress(let data): "tenfingers-progress-\(data.today)"
        }
    }

    /// Что предложить на экране итога урока. Издание 1: последний урок этапа пройден — этап, последний урок курса —
    /// курс. Издание 2: этап засчитывает проверка этапа со звёздами не ниже порога (`Stage.gate`); курс — любая попытка,
    /// которой курс становится пройденным (`Course.isCompleted`: до попытки нет, после есть) — итоговая проверка или
    /// последний пропущенный урок после неё. Проверка этапа, с которой курс пройден, даёт карточку курса и без этого
    /// условия «до», а у последнего этапа без карточки курса — ничего.
    /// `passed` и `checkStars` — прогресс до попытки: сама попытка (урок, звёзды проверки) добавляется здесь.
    static func completion(course: Course, lessonId: String, stars: Int, passed: Set<String>,
                           checkStars: [String: Int]) -> ShareEvent? {
        guard stars > 0, let stage = course.stage(of: lessonId) else { return nil }
        guard course.edition >= 2 else {
            guard stage.lessons.last?.id == lessonId else { return nil }
            if course.lessons.last?.id == lessonId { return .course(language: course.language) }
            return .stage(id: stage.id, title: stage.localizedTitle, language: course.language)
        }
        let attempt = CourseGate.withAttempt(course: course, lessonId: lessonId, stars: stars, passed: passed,
                                             checkStars: checkStars)
        let completes = course.isCompleted(passed: attempt.passed, checkStars: attempt.checkStars)
        guard stage.checkLesson?.id == lessonId else {
            // Обычный урок: карточка курса — только если именно эта попытка закрыла курс.
            let wasCompleted = course.isCompleted(passed: passed, checkStars: checkStars)
            return completes && !wasCompleted ? .course(language: course.language) : nil
        }
        guard stars >= stage.gate else { return nil }
        if completes { return .course(language: course.language) }
        if stage.id == course.stages.last?.id { return nil }
        return .stage(id: stage.id, title: stage.localizedTitle, language: course.language)
    }

    /// Сертификат — второе предложение рядом с карточкой курса: итоговая проверка взяла порог (`completion` — `.course`)
    /// и условие сертификата выполнено (`average` — `Certificate.eligibleAverage`, иначе `nil`).
    static func certificateOffer(after completion: ShareEvent?, language: Language, average: Double?) -> ShareEvent? {
        guard case .course? = completion, let average else { return nil }
        return .certificate(language: language, averageCpm: average)
    }

    /// Повтор одного шага: этап или курс засчитывает только проверка, в том числе «Освежить» (`isLessonCheck`:
    /// её звёзды тоже идут в гейт); `stars` — звёзды проверки.
    static func stepCompletion(course: Course, lessonId: String, kind: ExerciseKind, stars: Int?, passed: Set<String>,
                               checkStars: [String: Int]) -> ShareEvent? {
        guard kind.isLessonCheck, let stars else { return nil }
        return completion(course: course, lessonId: lessonId, stars: stars, passed: passed, checkStars: checkStars)
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
    /// 1080×1920 — вертикальная «сторис».
    case story
    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .wide: CGSize(width: 1200, height: 630)
        case .square: CGSize(width: 1080, height: 1080)
        case .story: CGSize(width: 1080, height: 1920)
        }
    }

    var title: String {
        switch self {
        case .wide: String(localized: "Широкая 1200×630")
        case .square: String(localized: "Квадрат 1080×1080")
        case .story: String(localized: "Сторис 1080×1920")
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

/// Что показывать на карточке ачивки: иконка и название есть всегда, шутка, «За что» и дата получения — по выбору.
struct AchievementCardContent: Equatable {
    /// Подзаголовок — шутка (`detail`).
    var showsJoke = true
    /// Мелкая строка «За что: …». По умолчанию выключена: «иконка и название» выглядит чище.
    var showsReason = false
    /// Дата получения под подписью. По умолчанию включена (как было до переключателя).
    var showsDate = true

    static func load(from defaults: UserDefaults) -> AchievementCardContent {
        AchievementCardContent(
            showsJoke: defaults.object(forKey: SettingsKey.shareAchievementShowJoke) as? Bool ?? true,
            showsReason: defaults.object(forKey: SettingsKey.shareAchievementShowReason) as? Bool ?? false,
            showsDate: defaults.object(forKey: SettingsKey.shareAchievementShowDate) as? Bool ?? true)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(showsJoke, forKey: SettingsKey.shareAchievementShowJoke)
        defaults.set(showsReason, forKey: SettingsKey.shareAchievementShowReason)
        defaults.set(showsDate, forKey: SettingsKey.shareAchievementShowDate)
    }
}

/// Настройки карточки; запоминаются между открытиями листа.
struct ShareOptions: Equatable {
    var signature: ShareSignature
    var theme: ShareTheme
    var background: ShareBackground
    var format: ShareFormat
    /// QR-код со ссылкой на приложение в углу.
    var showsQR = false
    /// Период карточки «Мой прогресс»: месяц, год или «Без календаря» (у остальных событий не используется).
    var progressPeriod = ProgressPeriod.month
    /// Что показывать на карточке «Мой прогресс» (у остальных событий не используется).
    var progressContent = ProgressCardContent()
    /// Что показывать на карточке ачивки (у остальных событий не используется).
    var achievementContent = AchievementCardContent()

    /// Карточка получилась бы пустой, и делиться ей нечем: у «Мой прогресс» всё выключено и нет календаря.
    func hasNothingToShow(for event: ShareEvent) -> Bool {
        guard case .progress = event else { return false }
        return progressContent.isEmpty && !progressPeriod.showsCalendar
    }

    /// Сохранённые опции; подпись, для которой в профиле больше нет данных, — подпись по умолчанию.
    static func load(_ defaults: UserDefaults = .standard, profile: ShareProfile) -> ShareOptions {
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        let stored: ShareSignature? = defaults.string(forKey: SettingsKey.shareSignature).flatMap(ShareSignature.init(rawValue:))
        let signature = stored.flatMap { profile.available.contains($0) ? $0 : nil } ?? profile.defaultSignature
        return ShareOptions(signature: signature, theme: value(SettingsKey.shareTheme, ShareTheme.light),
                            background: value(SettingsKey.shareBackground, ShareBackground.colored),
                            format: value(SettingsKey.shareFormat, ShareFormat.wide),
                            showsQR: defaults.bool(forKey: SettingsKey.shareQR),
                            progressPeriod: value(SettingsKey.shareProgressPeriod, ProgressPeriod.month),
                            progressContent: ProgressCardContent.load(from: defaults),
                            achievementContent: AchievementCardContent.load(from: defaults))
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(signature.rawValue, forKey: SettingsKey.shareSignature)
        defaults.set(theme.rawValue, forKey: SettingsKey.shareTheme)
        defaults.set(background.rawValue, forKey: SettingsKey.shareBackground)
        defaults.set(format.rawValue, forKey: SettingsKey.shareFormat)
        defaults.set(showsQR, forKey: SettingsKey.shareQR)
        defaults.set(progressPeriod.rawValue, forKey: SettingsKey.shareProgressPeriod)
        progressContent.save(to: defaults)
        achievementContent.save(to: defaults)
    }
}

/// Чем можно делиться: ачивки с `adult` при выключенном «Взрослом юморе» — нет.
enum ShareAvailability {
    static func canShare(_ achievement: Achievement, adultHumor: Bool) -> Bool {
        adultHumor || !achievement.adult
    }
}

private extension Achievement {
    /// Условие как утверждение («Открыты буквы: П И Ц А») на языке карточки; язык вне ru/en — язык системы.
    func earnedConditionText(locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier
        return AchievementConditionText.describe(condition, display: lettersDisplay,
                                                 localization: code.flatMap { ["ru", "en"].contains($0) ? $0 : nil },
                                                 earned: true)
    }
}

/// Тексты карточки на языке интерфейса (`bundle` и `locale` подменяются в тестах и при рендере картинок README).
struct ShareCardText: Equatable {
    let header: String
    let headline: String
    let subtitle: String?
    /// Мелкая строка под подзаголовком: у ачивки — «За что: …» (условие утверждением), у прочих `nil`.
    let footnote: String?
    /// Календарь, показатели и переключатели содержимого карточки «Мой прогресс»; у прочих событий `nil`.
    let progress: ProgressCardText?
    let signature: String?
    /// «Уровень N» под подписью — только у «Мой прогресс» (всегда, без переключателя).
    let levelLine: String?
    let date: String
    /// Показывать дату: только у карточки ачивки её можно выключить (`AchievementCardContent.showsDate`).
    let showsDate: Bool
    /// Водяной знак: название приложения на языке карточки и ссылка на проект двумя строками.
    let appName: String
    let link = ShareCardText.projectLink

    init(card: ShareCard, options: ShareOptions, profile: ShareProfile, unit: SpeedUnit,
         bundle: Bundle = .main, locale: Locale? = nil) {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        var progress: ProgressCardText?
        switch card.event {
        case .achievement(let achievement, _):
            header = String(localized: "Новая ачивка", bundle: bundle, locale: locale)
            headline = achievement.title
            subtitle = options.achievementContent.showsJoke ? achievement.detail : nil
            let reason = achievement.earnedConditionText(locale: locale)
            footnote = options.achievementContent.showsReason
                ? String(localized: "За что: \(reason)", bundle: bundle, locale: locale) : nil
        case .streak(let days, let full):
            let count = Formatting.days(days, bundle: bundle, locale: locale)
            header = String(localized: "Серия занятий", bundle: bundle, locale: locale)
            headline = String(localized: "\(count) подряд", bundle: bundle, locale: locale)
            subtitle = String(localized: "Полных дней: \(full)", bundle: bundle, locale: locale)
            footnote = nil
        case .speedRecord(let language, let cpm, _):
            header = String(localized: "Рекорд скорости", bundle: bundle, locale: locale)
            headline = "\(unit.wholeValue(cpm))"
            subtitle = Self.speedSubtitle(unit: unit, language: language, bundle: bundle, locale: locale)
            footnote = nil
        case .stage(_, let title, let language):
            header = String(localized: "Этап пройден", bundle: bundle, locale: locale)
            headline = title
            subtitle = Self.layoutName(language, bundle: bundle, locale: locale)
            footnote = nil
        case .course(let language):
            header = String(localized: "Курс пройден", bundle: bundle, locale: locale)
            headline = Self.layoutName(language, bundle: bundle, locale: locale)
            subtitle = String(localized: "Все уроки курса пройдены", bundle: bundle, locale: locale)
            footnote = nil
        case .certificate(let language, let averageCpm):
            header = String(localized: "Сертификат", bundle: bundle, locale: locale)
            headline = Self.layoutName(language, bundle: bundle, locale: locale)
            let name = Self.languageName(language, bundle: bundle, locale: locale)
            let speed = unit.format(averageCpm)
            subtitle = String(localized: "Курс «Десять пальцев» (\(name)) пройден · средняя скорость проверок этапов \(speed)",
                              bundle: bundle, locale: locale)
            footnote = nil
        case .progress(let data):
            let count = Formatting.days(data.streak, bundle: bundle, locale: locale)
            header = String(localized: "Мой прогресс", bundle: bundle, locale: locale)
            headline = String(localized: "\(count) подряд", bundle: bundle, locale: locale)
            let lines = ProgressCardText.subtitleLines(data: data, content: options.progressContent, bundle: bundle,
                                                       locale: locale)
            subtitle = lines.isEmpty ? nil : lines.joined(separator: "\n")
            footnote = nil
            progress = ProgressCardText(data: data, period: options.progressPeriod, content: options.progressContent,
                                        unit: unit, bundle: bundle, locale: locale)
        }
        self.progress = progress
        signature = profile.text(for: options.signature)
        if case .progress(let data) = card.event, let level = data.level {
            levelLine = String(localized: "Уровень \(level)", bundle: bundle, locale: locale)
        } else {
            levelLine = nil
        }
        date = card.date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
        if case .achievement = card.event { showsDate = options.achievementContent.showsDate } else { showsDate = true }
        appName = String(localized: "Десять пальцев", bundle: bundle, locale: locale)
    }

    static let projectLink = "github.com/Rusl3n/tenfingers"

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

    /// Название языка на языке карточки («Русский» / "Russian").
    private static func languageName(_ language: Language, bundle: Bundle, locale: Locale) -> String {
        switch language {
        case .ru: String(localized: "Русский", bundle: bundle, locale: locale)
        case .en: String(localized: "English", bundle: bundle, locale: locale)
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
