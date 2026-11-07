import Foundation
import Observation

/// Расписание и тон напоминаний в том виде, в каком они хранятся в `UserDefaults` (как у `@AppStorage`):
/// черновик в «Настройки → Напоминания» до нажатия «Сохранить». Включение напоминаний сюда не входит —
/// переключатель действует сразу.
struct ReminderDraft: Equatable {
    var schedule: String
    var hour: Int
    var minute: Int
    var time1: Int
    var time2: Int
    var time3: Int
    var fromHour: Int
    var toHour: Int
    var intervalHours: Int
    var tone: String
    var escalating: Bool

    static func load(_ defaults: UserDefaults) -> ReminderDraft {
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }
        return ReminderDraft(
            schedule: defaults.string(forKey: SettingsKey.reminderSchedule) ?? SettingsDefault.reminderSchedule,
            hour: int(SettingsKey.reminderHour, SettingsDefault.reminderHour),
            minute: int(SettingsKey.reminderMinute, SettingsDefault.reminderMinute),
            time1: int(SettingsKey.reminderTime1, SettingsDefault.reminderTime1),
            time2: int(SettingsKey.reminderTime2, SettingsDefault.reminderTime2),
            time3: int(SettingsKey.reminderTime3, SettingsDefault.reminderTime3),
            fromHour: int(SettingsKey.reminderFromHour, SettingsDefault.reminderFromHour),
            toHour: int(SettingsKey.reminderToHour, SettingsDefault.reminderToHour),
            intervalHours: int(SettingsKey.reminderIntervalHours, SettingsDefault.reminderIntervalHours),
            tone: defaults.string(forKey: SettingsKey.reminderTone) ?? SettingsDefault.reminderTone,
            escalating: defaults.object(forKey: SettingsKey.reminderEscalating) as? Bool
                ?? SettingsDefault.reminderEscalating)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(schedule, forKey: SettingsKey.reminderSchedule)
        defaults.set(hour, forKey: SettingsKey.reminderHour)
        defaults.set(minute, forKey: SettingsKey.reminderMinute)
        defaults.set(time1, forKey: SettingsKey.reminderTime1)
        defaults.set(time2, forKey: SettingsKey.reminderTime2)
        defaults.set(time3, forKey: SettingsKey.reminderTime3)
        defaults.set(fromHour, forKey: SettingsKey.reminderFromHour)
        defaults.set(toHour, forKey: SettingsKey.reminderToHour)
        defaults.set(intervalHours, forKey: SettingsKey.reminderIntervalHours)
        defaults.set(tone, forKey: SettingsKey.reminderTone)
        defaults.set(escalating, forKey: SettingsKey.reminderEscalating)
    }

    /// Смена «С» зажимает «До»: «До» всегда позже.
    mutating func setFromHour(_ value: Int) {
        fromHour = value
        if toHour <= fromHour { toHour = min(fromHour + 1, 23) }
    }

    /// Перенос черновика на новые сохранённые значения: берутся только поля, изменённые относительно прежних
    /// сохранённых (`old`), поверх новых (`new`).
    static func rebase(_ draft: ReminderDraft, from old: ReminderDraft, onto new: ReminderDraft) -> ReminderDraft {
        var result = new
        func carry<Value: Equatable>(_ path: WritableKeyPath<ReminderDraft, Value>) {
            if draft[keyPath: path] != old[keyPath: path] { result[keyPath: path] = draft[keyPath: path] }
        }
        carry(\.schedule)
        carry(\.hour)
        carry(\.minute)
        carry(\.time1)
        carry(\.time2)
        carry(\.time3)
        carry(\.fromHour)
        carry(\.toHour)
        carry(\.intervalHours)
        carry(\.tone)
        carry(\.escalating)
        return result
    }

    /// Есть ли несохранённые изменения: черновик есть и отличается от сохранённого.
    static func isDirty(draft: ReminderDraft?, saved: ReminderDraft) -> Bool {
        draft.map { $0 != saved } ?? false
    }
}

/// Черновик настроек напоминаний, пока открыто окно: переживает уход в другой раздел и обратно.
/// Ничего не пишет в `UserDefaults` и не пересчитывает напоминания до `save`.
@MainActor @Observable
final class ReminderDraftStore {
    @ObservationIgnored private let defaults: UserDefaults
    /// Сохранённые значения на момент последнего `reload` / `save`.
    private(set) var saved: ReminderDraft
    /// `nil` — изменений нет.
    private(set) var draft: ReminderDraft?

    init(defaults: UserDefaults = ProfileDefaults.current) {
        self.defaults = defaults
        saved = .load(defaults)
    }

    /// Что показывать: черновик или сохранённое.
    var current: ReminderDraft { draft ?? saved }

    var isDirty: Bool { ReminderDraft.isDirty(draft: draft, saved: saved) }

    /// Правка черновика; вернулись к сохранённому — черновика больше нет.
    func edit(_ change: (inout ReminderDraft) -> Void) {
        var next = current
        change(&next)
        draft = next == saved ? nil : next
    }

    /// «Отменить»: черновик выбрасывается.
    func revert() { draft = nil }

    /// Перечитывает сохранённое (настройки могли смениться загрузкой прогресса или сбросом). Черновик переносится
    /// на новые значения: свои правки остаются, остальное — новое; совпал с сохранённым — черновика нет.
    func reload() {
        let old = saved
        saved = .load(defaults)
        guard let draft else { return }
        let rebased = ReminderDraft.rebase(draft, from: old, onto: saved)
        self.draft = rebased == saved ? nil : rebased
    }

    /// «Сохранить»: черновик записывается, напоминания пересчитываются один раз.
    func save(rescheduling scheduler: ReminderScheduler) async {
        guard let draft else { return }
        draft.save(to: defaults)
        saved = draft
        self.draft = nil
        await scheduler.reschedule()
    }
}
