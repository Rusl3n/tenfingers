import AppKit
import SwiftUI
import TypingCore

/// Раздел «Напоминания»: включение, расписание, тон и состояние разрешения на уведомления.
struct ReminderSettingsView: View {
    @AppStorage(SettingsKey.remindersEnabled) private var enabled = SettingsDefault.remindersEnabled
    @AppStorage(SettingsKey.reminderHour) private var hour = SettingsDefault.reminderHour
    @AppStorage(SettingsKey.reminderMinute) private var minute = SettingsDefault.reminderMinute
    @AppStorage(SettingsKey.reminderSchedule) private var schedule = SettingsDefault.reminderSchedule
    @AppStorage(SettingsKey.reminderTime1) private var time1 = SettingsDefault.reminderTime1
    @AppStorage(SettingsKey.reminderTime2) private var time2 = SettingsDefault.reminderTime2
    @AppStorage(SettingsKey.reminderTime3) private var time3 = SettingsDefault.reminderTime3
    @AppStorage(SettingsKey.reminderFromHour) private var fromHour = SettingsDefault.reminderFromHour
    @AppStorage(SettingsKey.reminderToHour) private var toHour = SettingsDefault.reminderToHour
    @AppStorage(SettingsKey.reminderIntervalHours) private var intervalHours = SettingsDefault.reminderIntervalHours
    @AppStorage(SettingsKey.reminderTone) private var tone = SettingsDefault.reminderTone
    @AppStorage(SettingsKey.reminderEscalating) private var escalating = SettingsDefault.reminderEscalating
    @Environment(ReminderScheduler.self) private var scheduler

    private var mode: ReminderScheduleMode { ReminderScheduleMode(rawValue: schedule) ?? .once }

    /// Время в `DatePicker`: часы и минуты хранятся отдельно, дата не важна.
    private var time: Binding<Date> {
        Binding(
            get: { Self.date(minuteOfDay: hour * 60 + minute) },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                hour = parts.hour ?? SettingsDefault.reminderHour
                minute = parts.minute ?? SettingsDefault.reminderMinute
            })
    }

    /// Время суток в минутах как `Date` для `DatePicker` и обратно.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Self.date(minuteOfDay: minutes.wrappedValue) },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }

    private static func date(minuteOfDay: Int) -> Date {
        Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: .now) ?? .now
    }

    /// «С» — 0…22, «До» — от «С» + 1 до 23: значения вне диапазона (из старого файла) показываются зажатыми.
    private var from: Binding<Int> {
        Binding(get: { min(fromHour, 22) }, set: { fromHour = $0 })
    }

    private var to: Binding<Int> {
        Binding(get: { min(max(toHour, from.wrappedValue + 1), 23) }, set: { toHour = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Напоминать заниматься", isOn: $enabled)
                Group {
                    schedulePicker
                    timeRows
                    tonePicker
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Toggle("Нарастающее", isOn: $escalating)
                            InfoButton(text: HelpText.reminderEscalating)
                        }
                        if escalating {
                            Text(HelpText.reminderEscalatingSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .help(HelpText.reminderEscalating)
                }
                .disabled(!enabled)
                status
            } footer: {
                Text("Напоминание придёт, только если сегодня ещё не набран полный огонь.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { await scheduler.refreshAuthorization() }
        // Вернулись из «Системных настроек» (разрешение могли дать или отозвать): статус обновляется сразу.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await scheduler.refreshAuthorization() }
        }
        .onChange(of: enabled) { _, isOn in
            // Разрешение запрашивается только здесь, при включении.
            Task { if isOn { await scheduler.enable() } else { await scheduler.reschedule() } }
        }
        .onChange(of: fromHour) {
            // Смена «С» зажимает «До»: «До» всегда позже.
            if toHour <= fromHour { toHour = min(fromHour + 1, 23) }
            scheduler.rescheduleSoon()
        }
        .onChange(of: scheduleSignature) { scheduler.rescheduleSoon() }
    }

    /// Всё, что меняет расписание или тексты (кроме «С» и включения — они обрабатываются отдельно).
    private var scheduleSignature: [String] {
        [schedule, tone, "\(hour):\(minute)", "\(time1)/\(time2)/\(time3)", "\(toHour)/\(intervalHours)", "\(escalating)"]
    }

    private var schedulePicker: some View {
        Picker("Расписание", selection: $schedule) {
            Text("Один раз в день").tag(ReminderScheduleMode.once.rawValue)
            Text("3 раза в день").tag(ReminderScheduleMode.thrice.rawValue)
            Text("Каждые N часов").tag(ReminderScheduleMode.interval.rawValue)
        }
        .help(HelpText.reminderSchedule)
    }

    @ViewBuilder private var timeRows: some View {
        switch mode {
        case .once:
            DatePicker("Время напоминания", selection: time, displayedComponents: .hourAndMinute)
        case .thrice:
            DatePicker("Первое", selection: time($time1), displayedComponents: .hourAndMinute)
            DatePicker("Второе", selection: time($time2), displayedComponents: .hourAndMinute)
            DatePicker("Третье", selection: time($time3), displayedComponents: .hourAndMinute)
        case .interval:
            Picker("С часа", selection: from) {
                ForEach(0...22, id: \.self) { Text(Self.hourTitle($0)).tag($0) }
            }
            Picker("До часа", selection: to) {
                ForEach((from.wrappedValue + 1)...23, id: \.self) { Text(Self.hourTitle($0)).tag($0) }
            }
            Picker("Интервал", selection: $intervalHours) {
                ForEach(1...4, id: \.self) { Text("\($0) ч").tag($0) }
            }
        }
    }

    private var tonePicker: some View {
        Picker("Тон", selection: $tone) {
            Text("Обычный").tag(ReminderTone.normal.rawValue)
            Text("Шуточный").tag(ReminderTone.funny.rawValue)
            Text("Вперемешку").tag(ReminderTone.mixed.rawValue)
        }
        .help(HelpText.reminderTone)
    }

    private static func hourTitle(_ hour: Int) -> String { String(format: "%d:00", hour) }

    @ViewBuilder private var status: some View {
        switch scheduler.authorization {
        case .authorized:
            Label("Уведомления разрешены", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .notDetermined:
            Label("Разрешение будет запрошено при включении", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .denied:
            Label("Уведомления выключены в системных настройках", systemImage: "bell.slash")
                .foregroundStyle(.orange)
            Button("Открыть настройки уведомлений") { Self.openSystemSettings() }
        case .unavailable:
            Label("Уведомления недоступны в этой сборке", systemImage: "bell.slash")
                .foregroundStyle(.secondary)
        }
    }

    static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!

    private static func openSystemSettings() {
        NSWorkspace.shared.open(systemSettingsURL)
    }
}
