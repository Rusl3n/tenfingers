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
    /// форматируется), а не при каждой отрисовке значка. `lockedText` и `title` задают только тесты вёрстки и картинки README (язык).
    let lockedText: String
    /// Название на языке системы, как `lockedText` — один раз.
    let title: String

    init(achievement: Achievement, unlockedAt: Date?, seen: Bool, lockedText: String? = nil, title: String? = nil) {
        self.achievement = achievement
        self.title = title ?? achievement.title
        self.unlockedAt = unlockedAt
        self.seen = seen
        self.lockedText = lockedText ?? achievement.conditionText
    }

    var id: String { achievement.id }
    var isEarned: Bool { unlockedAt != nil }
    /// Описание полученной (у «Теперь вы можете…» — шутка).
    var earnedText: String { achievement.detail }
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

    static func filtered(_ entries: [AchievementEntry], category: AchievementCategory?) -> [AchievementEntry] {
        guard let category else { return entries }
        return entries.filter { $0.achievement.category == category }
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

    /// Самая недавно полученная видимая ачивка (при равных датах — более поздняя в каталоге).
    static func latest(_ entries: [AchievementEntry]) -> AchievementEntry? {
        entries.filter(\.isEarned).enumerated()
            .max { ($0.element.unlockedAt!, $0.offset) < ($1.element.unlockedAt!, $1.offset) }?.element
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
