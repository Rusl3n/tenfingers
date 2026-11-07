import Foundation
import TypingCore

/// Тосты «года» (6e, решение 14): новый уровень и выполненные испытания недели и месяца. Что уже показано — в
/// `UserDefaults` вне архива (`yearAnnouncedLevel`, `yearAnnouncedChallenges`). Показ только после сохранения
/// упражнения; при запуске состояние лишь запоминается, тостов за прошлое нет.
@MainActor
enum YearAnnouncer {
    /// Больше трёх тостов испытаний за раз не показывается (отмечены в `UserDefaults` все).
    static let maxChallengeToasts = 3

    /// Выполненное испытание текущего периода: ключ `<период>#<id>`, награда опыта.
    private struct Done {
        let key: String
        let id: ChallengeId
        let bonus: Int
    }

    /// Выполненные испытания текущих недели и месяца в порядке показа: неделя, потом месяц.
    private static func completed(_ state: YearState) -> [Done] {
        var done: [Done] = []
        for (period, bonus) in [(state.week, Experience.challengeWeekBonus), (state.month, Experience.challengeMonthBonus)] {
            guard let period else { continue }
            let finished = period.results.filter { $0.completedAt != nil }
            // Испытание, закрывающее неделю (все три выполнены), даёт ещё награду за все три (решение 10): тост — полная
            // сумма. При одинаковых датах закрывающим считается последнее в списке.
            var closing: ChallengeId?
            if case .week = period.period, let allDone = period.allDoneAt {
                closing = finished.last { $0.completedAt == allDone }?.id
            }
            for result in finished {
                let total = result.id == closing ? bonus + Experience.challengeWeekAllBonus : bonus
                done.append(Done(key: "\(period.period.key)#\(result.id.rawValue)", id: result.id, bonus: total))
            }
        }
        return done
    }

    /// Запуск приложения: уровень и выполненные испытания запоминаются как показанные, тостов нет.
    static func launch(state: YearState, defaults: UserDefaults = ProfileDefaults.current) {
        defaults.set(state.level, forKey: SettingsKey.yearAnnouncedLevel)
        defaults.set(completed(state).map(\.key), forKey: SettingsKey.yearAnnouncedChallenges)
    }

    /// После сохранения показанный уровень только растёт: уровень может упасть (поднята цель — старые дни без
    /// записанной цели берут текущую), и без этого тост того же уровня показался бы снова. Загрузка другого
    /// прогресса идёт через `launch`, там базовая линия следует за состоянием.
    private static func rememberLevel(_ level: Int, defaults: UserDefaults) {
        let announced = defaults.object(forKey: SettingsKey.yearAnnouncedLevel) as? Int
        defaults.set(max(level, announced ?? level), forKey: SettingsKey.yearAnnouncedLevel)
    }

    /// После сохранения упражнения: уровень выше показанного — один тост (скачок на несколько уровней — тост
    /// последнего), затем по тосту на каждое новое выполненное испытание (не больше трёх). `UserDefaults` обновляется;
    /// ключи прошлых периодов отбрасываются. Без базовой линии (запуск ещё не выставил ключи) только запоминает.
    /// Возвращает число показанных тостов; звук ачивки — один раз, если хоть один тост показан.
    @discardableResult
    static func afterSave(state: YearState, toasts: ToastCenter, sound: SoundPlayer?,
                          defaults: UserDefaults = ProfileDefaults.current) -> Int {
        var queue: [Toast] = []
        if let announced = defaults.object(forKey: SettingsKey.yearAnnouncedLevel) as? Int, state.level > announced {
            queue.append(ToastCenter.levelToast(level: state.level, title: state.title))
        }
        rememberLevel(state.level, defaults: defaults)

        let done = completed(state)
        if let known = defaults.stringArray(forKey: SettingsKey.yearAnnouncedChallenges) {
            let fresh = done.filter { !known.contains($0.key) }.prefix(maxChallengeToasts)
            queue.append(contentsOf: fresh.map { ToastCenter.challengeToast($0.id, bonus: $0.bonus) })
        }
        defaults.set(done.map(\.key), forKey: SettingsKey.yearAnnouncedChallenges)

        guard !queue.isEmpty else { return 0 }
        toasts.enqueue(queue, duration: AchievementToasts.duration, step: AchievementToasts.step)
        sound?.play(.achievement)
        return queue.count
    }
}
