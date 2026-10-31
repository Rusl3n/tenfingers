import SwiftUI
import TypingCore

/// Что из полученного показывать: с выключенным «Взрослым юмором» ачивки с `adult` скрыты
/// (из тостов, карточек итога, списка и карточек «Поделиться»), но выдаются как обычно.
enum AchievementVisibility {
    static func visible(_ achievements: [Achievement], adultHumor: Bool) -> [Achievement] {
        adultHumor ? achievements : achievements.filter { !$0.adult }
    }

    static func visible(_ cards: [EarnedCard], adultHumor: Bool) -> [EarnedCard] {
        adultHumor ? cards : cards.filter { !$0.achievement.adult }
    }
}

/// Тосты ачивок: каждая новая — 4 с, несколько подряд — очередь по 1,5 с; сводка «задним числом» — дольше
/// и с кнопкой «Посмотреть».
enum AchievementToasts {
    static let duration = Duration.seconds(4)
    static let step = Duration.milliseconds(1500)
    static let summaryDuration = Duration.seconds(8)
    static let tint = Color.yellow
}

extension ToastCenter {
    /// «Новая ачивка: <название>» для каждой видимой ачивки, по очереди после текущего сообщения;
    /// с кнопкой «Поделиться», если задан `shareAchievement`.
    func showAchievements(_ achievements: [Achievement], adultHumor: Bool) {
        showAchievements(achievements.map { EarnedCard($0) }, adultHumor: adultHumor)
    }

    /// Тосты по карточкам: «Новая ачивка: …», «Повтор ×N: …», у рекорда — «Новый рекорд: 231 зн/мин».
    func showAchievements(_ cards: [EarnedCard], unit: SpeedUnit? = nil, adultHumor: Bool) {
        let share = shareAchievement
        let unit = unit ?? SpeedUnit(rawValue: UserDefaults.standard.string(forKey: SettingsKey.speedUnit) ?? "") ?? .cpm
        let toasts = AchievementVisibility.visible(cards, adultHumor: adultHumor).map { card in
            let achievement = card.achievement
            return Toast(icon: achievement.icon, message: Self.message(card, unit: unit),
                         tint: AchievementToasts.tint,
                         action: share.map { share in
                             ToastAction(title: String(localized: "Поделиться")) { share(achievement) }
                         })
        }
        guard !toasts.isEmpty else { return }
        enqueue(toasts, duration: AchievementToasts.duration, step: AchievementToasts.step)
    }

    /// Текст тоста карточки.
    static func message(_ card: EarnedCard, unit: SpeedUnit) -> String {
        let title = card.achievement.title
        if card.achievement.id == "speed.record", let line = card.valueLine(unit: unit) { return line }
        if let count = card.repeatCount { return String(localized: "Повтор ×\(count): \(title)") }
        return String(localized: "Новая ачивка: \(title)")
    }

    /// Одна сводка вместо лавины тостов при выдаче задним числом (§20).
    func showBackfillSummary(count: Int, open: @escaping @MainActor () -> Void) {
        let toast = Toast(icon: "trophy.fill", message: Formatting.backfillSummary(count),
                          tint: AchievementToasts.tint,
                          action: ToastAction(title: String(localized: "Посмотреть"), perform: open))
        enqueue([toast], duration: AchievementToasts.summaryDuration, step: AchievementToasts.summaryDuration)
    }
}

/// Проверка ачивок вне упражнения: при запуске и после загрузки прогресса из файла.
@MainActor
enum AchievementAnnouncer {
    /// Выданные задним числом — одна сводка с кнопкой (`open`); N — новые ачивки и выдачи повторяемых. Прочие новые (например, новые ачивки после
    /// обновления, найденные по истории): две и больше видимых — тоже одна сводка, одна — обычный тост
    /// (без звука: занятия не было). Ачивки после обновления остаются непросмотренными (точки на значках).
    @discardableResult
    static func launchCheck(service: AchievementService, toasts: ToastCenter, adultHumor: Bool,
                            open: @escaping @MainActor () -> Void) -> AchievementService.Outcome {
        let outcome = service.checkLogging(reason: .launch)
        let total = summaryCount(outcome, adultHumor: adultHumor)
        if outcome.isBackfill || outcome.isGrantBackfill {
            if total > 0 { toasts.showBackfillSummary(count: total, open: open) }
        } else if total >= 2 {
            toasts.showBackfillSummary(count: total, open: open)
        } else {
            toasts.showAchievements(EarnedCard.cards(from: outcome), adultHumor: adultHumor)
        }
        return outcome
    }

    /// Число для сводки: видимые новые и выдачи повторяемых. Выдачи скрытых «взрослых» не считаются; первая выдача
    /// новой повторяемой — та же ачивка, что в `new`, и дважды не считается.
    static func summaryCount(_ outcome: AchievementService.Outcome, adultHumor: Bool) -> Int {
        let newIds = Set(outcome.new.map(\.id))
        let grants = outcome.grants.filter {
            (adultHumor || !$0.achievement.adult) && !($0.count == 1 && newIds.contains($0.achievement.id))
        }.count
        return AchievementVisibility.visible(outcome.new, adultHumor: adultHumor).count + grants
    }

    /// Прогресс заменён загрузкой из файла: кэш фактов устарел, ачивки проверяются заново.
    @discardableResult
    static func progressReplaced(service: AchievementService, toasts: ToastCenter, adultHumor: Bool,
                                 open: @escaping @MainActor () -> Void) -> AchievementService.Outcome {
        service.cache.invalidate()
        return launchCheck(service: service, toasts: toasts, adultHumor: adultHumor, open: open)
    }
}
