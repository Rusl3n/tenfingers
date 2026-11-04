import Foundation

/// Снимок для виджета: приложение пишет его в `widget.json`, виджет читает. Только Foundation.
/// Виджет ничего не пересчитывает, а показывает то, что записано в файле.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Версия формата файла; виджет не читает файлы с незнакомым форматом.
    public static let currentFormat = 1
    /// Имя файла в папке данных приложения (`~/Library/Application Support/TenFingers`).
    public static let fileName = "widget.json"
    /// Снимок старше этого срока (36 часов) считается давно не обновлявшимся.
    public static let staleAfter: TimeInterval = 36 * 3600

    /// Состояние огня сегодня: полный день, половинный или ещё не занимались.
    public enum FireToday: String, Codable, Sendable {
        case full, half, none
    }

    public struct Fire: Codable, Equatable, Sendable {
        public var days: Int
        public var today: FireToday
        public var freezes: Int

        public init(days: Int, today: FireToday, freezes: Int) {
            self.days = days
            self.today = today
            self.freezes = freezes
        }
    }

    /// «Искра»: дни подряд с занятиями и засчитан ли сегодня.
    public struct Spark: Codable, Equatable, Sendable {
        public var days: Int
        public var today: Bool

        public init(days: Int, today: Bool) {
            self.days = days
            self.today = today
        }
    }

    public struct Goal: Codable, Equatable, Sendable {
        public var goalMinutes: Int
        public var doneMinutes: Int

        public init(goalMinutes: Int, doneMinutes: Int) {
            self.goalMinutes = goalMinutes
            self.doneMinutes = doneMinutes
        }
    }

    /// Следующий шаг «Продолжить».
    public struct Next: Codable, Equatable, Sendable {
        public var title: String
        /// Язык курса: `ru` или `en`.
        public var courseLanguage: String

        public init(title: String, courseLanguage: String) {
            self.title = title
            self.courseLanguage = courseLanguage
        }
    }

    /// Полученная ачивка: название уже на языке интерфейса, символ — имя SF Symbol.
    public struct Item: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var symbol: String
        public var date: Date
        /// «Взрослый юмор»: виджет решает, показывать ли её.
        public var adult: Bool

        public init(id: String, title: String, symbol: String, date: Date, adult: Bool) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.date = date
            self.adult = adult
        }
    }

    public var format: Int
    public var writtenAt: Date
    /// Логический день записи, `yyyy-MM-dd`.
    public var logicalDay: String
    /// Час начала логического дня в приложении: по нему виджет решает, сегодняшний ли снимок.
    public var dayStartHour: Int
    /// Язык интерфейса приложения: `ru` или `en`.
    public var language: String
    public var adultHumor: Bool
    public var fire: Fire
    public var spark: Spark
    public var goal: Goal
    /// `nil` — вести некуда (курс пройден или не загружен).
    public var next: Next?
    /// До пяти последних полученных, новые первыми.
    public var achievements: [Item]

    public init(format: Int = WidgetSnapshot.currentFormat, writtenAt: Date, logicalDay: String,
                dayStartHour: Int = WidgetTimeline.defaultDayStartHour, language: String, adultHumor: Bool, fire: Fire, spark: Spark, goal: Goal, next: Next? = nil,
                achievements: [Item] = []) {
        self.format = format
        self.writtenAt = writtenAt
        self.logicalDay = logicalDay
        self.dayStartHour = dayStartHour
        self.language = language
        self.adultHumor = adultHumor
        self.fire = fire
        self.spark = spark
        self.goal = goal
        self.next = next
        self.achievements = achievements
    }

    /// `dayStartHour` необязателен: в файле без этого поля берётся 4 (`WidgetTimeline.defaultDayStartHour`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Int.self, forKey: .format)
        writtenAt = try container.decode(Date.self, forKey: .writtenAt)
        logicalDay = try container.decode(String.self, forKey: .logicalDay)
        dayStartHour = try container.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? WidgetTimeline.defaultDayStartHour
        language = try container.decode(String.self, forKey: .language)
        adultHumor = try container.decode(Bool.self, forKey: .adultHumor)
        fire = try container.decode(Fire.self, forKey: .fire)
        spark = try container.decode(Spark.self, forKey: .spark)
        goal = try container.decode(Goal.self, forKey: .goal)
        next = try container.decodeIfPresent(Next.self, forKey: .next)
        achievements = try container.decode([Item].self, forKey: .achievements)
    }

    public enum DecodeError: Error, Equatable {
        /// Файл записан другой версией формата.
        case unsupportedFormat(Int)
    }

    private struct Header: Decodable {
        let format: Int
    }

    /// Кодирование файла: даты ISO 8601 (до секунды), ключи по алфавиту.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    /// Разбор файла. Незнакомый `format` — ошибка (новые поля читает только новый виджет).
    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(Header.self, from: data)
        guard header.format == currentFormat else { throw DecodeError.unsupportedFormat(header.format) }
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Файл записан больше 36 часов назад.
    public func isStale(now: Date) -> Bool {
        now.timeIntervalSince(writtenAt) > Self.staleAfter
    }

    /// Логическая дата файла совпадает с переданной (сегодняшней): иначе «сегодня» считается несделанным.
    public func isToday(_ logicalDay: String) -> Bool {
        self.logicalDay == logicalDay
    }
}
