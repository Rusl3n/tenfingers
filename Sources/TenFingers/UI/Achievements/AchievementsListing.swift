import Foundation
import SwiftData
import TypingCore

/// Полученная ачивка, как она хранится (`AchievementRecord` без привязки к SwiftData: чистые функции
/// списка работают и в тестах без базы).
struct StoredAchievement: Equatable {
    let id: String
    let unlockedAt: Date
    let seen: Bool

    init(id: String, unlockedAt: Date, seen: Bool) {
        self.id = id
        self.unlockedAt = unlockedAt
        self.seen = seen
    }

    init(_ record: AchievementRecord) {
        self.init(id: record.achievementId, unlockedAt: record.unlockedAt, seen: record.seen)
    }
}

/// Одна ачивка на экране: из каталога, с датой получения (если получена).
struct AchievementEntry: Identifiable, Equatable {
    let achievement: Achievement
    /// `nil` — ещё не получена.
    let unlockedAt: Date?
    /// Показана ли пользователю; у неполученной точки нет, поэтому `true`.
    let seen: Bool

    /// Условие получения: у неполученной показывается вместо описания, у «Теперь вы можете…» описание —
    /// шутка, которая раскрыла бы ответ. Считается один раз при создании записи (строка собирается из ресурсов и
    /// форматируется), а не при каждой отрисовке значка. `lockedText`, `title` и `earnedText` задают только тесты
    /// вёрстки и картинки README (язык).
    let lockedText: String
    /// Название на языке системы, как `lockedText` — один раз.
    let title: String
    /// Описание полученной (у «Теперь вы можете…» — шутка), как `lockedText` — один раз.
    let earnedText: String
    /// Условие как утверждение («Открыты буквы: П И Ц А») для «За что» у полученной; у нейтральных условий
    /// совпадает с `lockedText`. «Как получить» у неполученной остаётся просьбой (`lockedText`).
    let reasonText: String

    init(achievement: Achievement, unlockedAt: Date?, seen: Bool, lockedText: String? = nil, title: String? = nil,
         earnedText: String? = nil, reasonText: String? = nil) {
        self.achievement = achievement
        self.title = title ?? achievement.title
        self.unlockedAt = unlockedAt
        self.seen = seen
        self.lockedText = lockedText ?? achievement.conditionText
        self.earnedText = earnedText ?? achievement.detail
        self.reasonText = reasonText ?? achievement.earnedConditionText
    }

    var id: String { achievement.id }
    var isEarned: Bool { unlockedAt != nil }
}

extension AchievementEntry {
    /// Секретная и ещё не получена: ничего не раскрываем (ни название, ни значок, ни условие).
    var isConcealed: Bool { achievement.secret && !isEarned }
    /// «???» у скрытой (без перевода), иначе название.
    var displayTitle: String { isConcealed ? "???" : title }
    /// Замок у скрытой, иначе значок ачивки.
    var displayIcon: String { isConcealed ? "lock.fill" : achievement.icon }
    /// Строка под названием на значке: полученная — шутка; скрытая — «Секретная ачивка»; иначе «Как получить: …».
    var badgeCaption: String {
        if isEarned { return earnedText }
        if isConcealed { return String(localized: "Секретная ачивка") }
        return String(localized: "Как получить: \(lockedText)")
    }
    /// «За что: <условие как утверждение>» — в подробностях полученной.
    var reasonLine: String { String(localized: "За что: \(reasonText)") }
}

/// Фильтр экрана «Ачивки» по состоянию; сочетается с категорией.
enum AchievementsFilter: String, CaseIterable, Identifiable {
    case all, earned, locked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "Все")
        case .earned: String(localized: "Полученные")
        case .locked: String(localized: "Не полученные")
        }
    }
}

/// Список экрана «Ачивки», карточка на главной и счётчик в боковой панели: чистые функции над каталогом и записями.
/// С выключенным «Взрослым юмором» ачивки с `adult` не показываются совсем (ни полученные, ни нет) и не входят в итог.
enum AchievementsListing {
    /// Видимые ачивки каталога в его порядке; записи с неизвестным id (из более новой версии) пропускаются.
    static func entries(catalog: [Achievement], earned: [StoredAchievement], adultHumor: Bool) -> [AchievementEntry] {
        let stored = Dictionary(earned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return AchievementVisibility.visible(catalog, adultHumor: adultHumor).map { achievement in
            let record = stored[achievement.id]
            return AchievementEntry(achievement: achievement, unlockedAt: record?.unlockedAt,
                                    seen: record?.seen ?? true)
        }
    }

    /// Выбранная категория, если в списке ещё есть её ачивки; иначе `nil` («Все»). Категория пропадает, когда
    /// «Взрослый юмор» выключен, а выбрана та, где все ачивки скрыты: иначе остался бы пустой экран без фильтра.
    static func resolvedCategory(_ category: AchievementCategory?, in entries: [AchievementEntry]) -> AchievementCategory? {
        guard let category, categories(of: entries).contains(category) else { return nil }
        return category
    }

    /// Записи выбранной категории (`nil` — любой), прошедшие фильтр по состоянию.
    static func filtered(_ entries: [AchievementEntry], category: AchievementCategory?,
                         filter: AchievementsFilter) -> [AchievementEntry] {
        entries.filter { entry in
            if let category, entry.achievement.category != category { return false }
            switch filter {
            case .all: return true
            case .earned: return entry.isEarned
            case .locked: return !entry.isEarned
            }
        }
    }

    /// Категории, в которых есть что показать, в порядке `AchievementCategory`.
    static func categories(of entries: [AchievementEntry]) -> [AchievementCategory] {
        let present = Set(entries.map(\.achievement.category))
        return AchievementCategory.allCases.filter(present.contains)
    }

    /// «Получено N из M».
    static func progress(_ entries: [AchievementEntry]) -> (earned: Int, total: Int) {
        (entries.filter(\.isEarned).count, entries.count)
    }

    /// Самая недавно полученная видимая ачивка (при равных датах — более поздняя в каталоге). Сначала выбирается
    /// запись, потом строится одна `AchievementEntry`, а не весь список. Повтор id — первая запись, как в `entries`.
    static func latest(catalog: [Achievement], earned: [StoredAchievement], adultHumor: Bool) -> AchievementEntry? {
        let visible = AchievementVisibility.visible(catalog, adultHumor: adultHumor)
        let position = Dictionary(visible.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stored = Dictionary(earned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let best = stored.values.compactMap { record in position[record.id].map { (record, $0) } }
            .max { ($0.0.unlockedAt, $0.1) < ($1.0.unlockedAt, $1.1) }
        guard let (record, index) = best else { return nil }
        return AchievementEntry(achievement: visible[index], unlockedAt: record.unlockedAt, seen: record.seen)
    }

    /// Id видимых ачивок каталога, которые пользователь ещё не видел (точки на значках и счётчик в боковой панели).
    /// Скрытые «взрослые» остаются непросмотренными, пока выключен юмор: включишь — увидишь их новыми.
    static func unseenIds(catalog: [Achievement], earned: [StoredAchievement], adultHumor: Bool) -> Set<String> {
        let visible = Set(AchievementVisibility.visible(catalog, adultHumor: adultHumor).map(\.id))
        return Set(earned.filter { !$0.seen && visible.contains($0.id) }.map(\.id))
    }
}

extension AchievementsListing {
    /// Помечает просмотренными записи с этими id одной транзакцией; при ошибке сохранения откатывает все.
    @MainActor
    static func markSeen(_ ids: Set<String>, in recorder: ResultRecorder) throws {
        guard !ids.isEmpty else { return }
        try recorder.commit {
            for record in try recorder.context.fetch(FetchDescriptor<AchievementRecord>()) where ids.contains(record.achievementId) {
                record.seen = true
            }
        }
    }
}
