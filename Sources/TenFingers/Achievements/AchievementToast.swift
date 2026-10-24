import SwiftUI
import TypingCore

/// Что из полученного показывать: с выключенным «Взрослым юмором» ачивки с `adult` скрыты
/// (из тостов, строки итога, списка и карточек), но выдаются как обычно.
enum AchievementVisibility {
    static func visible(_ achievements: [Achievement], adultHumor: Bool) -> [Achievement] {
        adultHumor ? achievements : achievements.filter { !$0.adult }
    }

    /// «Новые ачивки: Ночная сова, Стальные мизинцы» для экранов итога; `nil`, если показывать нечего.
    static func resultLine(_ achievements: [Achievement], adultHumor: Bool) -> String? {
        let shown = visible(achievements, adultHumor: adultHumor)
        guard !shown.isEmpty else { return nil }
        let titles = shown.map(\.title).joined(separator: ", ")
        return String(localized: "Новые ачивки: \(titles)")
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
        let share = shareAchievement
        let toasts = AchievementVisibility.visible(achievements, adultHumor: adultHumor).map { achievement in
            let title = achievement.title
            return Toast(icon: achievement.icon, message: String(localized: "Новая ачивка: \(title)"),
                         tint: AchievementToasts.tint,
                         action: share.map { share in
                             ToastAction(title: String(localized: "Поделиться")) { share(achievement) }
                         })
        }
        guard !toasts.isEmpty else { return }
        enqueue(toasts, duration: AchievementToasts.duration, step: AchievementToasts.step)
    }

    /// Одна сводка вместо лавины тостов при выдаче задним числом (§20).
    func showBackfillSummary(count: Int, open: @escaping @MainActor () -> Void) {
        let toast = Toast(icon: "trophy.fill", message: Formatting.backfillSummary(count),
                          tint: AchievementToasts.tint,
                          action: ToastAction(title: String(localized: "Посмотреть"), perform: open))
        enqueue([toast], duration: AchievementToasts.summaryDuration, step: AchievementToasts.summaryDuration)
    }
}

/// Строка «Новые ачивки: …» на экране итога урока или порции (ачивки последнего сохранения).
struct NewAchievementsLine: View {
    let achievements: [Achievement]
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor

    var body: some View {
        if let line = AchievementVisibility.resultLine(achievements, adultHumor: adultHumor) {
            // Текст основным цветом (жёлтый плохо читается на светлых палитрах), жёлтая только иконка.
            Label {
                Text(line).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(AchievementToasts.tint)
            }
            .font(.title3)
            .multilineTextAlignment(.center)
        }
    }
}

/// Проверка ачивок вне упражнения: при запуске и после загрузки прогресса из файла.
@MainActor
enum AchievementAnnouncer {
    /// Выданные задним числом — одна сводка с кнопкой (`open`); прочие новые — обычные тосты (без звука:
    /// занятия не было).
    @discardableResult
    static func launchCheck(service: AchievementService, toasts: ToastCenter, adultHumor: Bool,
                            open: @escaping @MainActor () -> Void) -> AchievementService.Outcome {
        let outcome = service.checkLogging(reason: .launch)
        if outcome.isBackfill {
            let count = AchievementVisibility.visible(outcome.new, adultHumor: adultHumor).count
            if count > 0 { toasts.showBackfillSummary(count: count, open: open) }
        } else {
            toasts.showAchievements(outcome.new, adultHumor: adultHumor)
        }
        return outcome
    }

    /// Прогресс заменён загрузкой из файла: кэш фактов устарел, ачивки проверяются заново.
    @discardableResult
    static func progressReplaced(service: AchievementService, toasts: ToastCenter, adultHumor: Bool,
                                 open: @escaping @MainActor () -> Void) -> AchievementService.Outcome {
        service.cache.invalidate()
        return launchCheck(service: service, toasts: toasts, adultHumor: adultHumor, open: open)
    }
}
