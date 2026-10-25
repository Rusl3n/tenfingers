import AppKit
import SwiftUI
import TypingCore

/// Раздел «Напоминания»: включение, расписание, тон и состояние разрешения на уведомления.
/// Расписание и тон правятся черновиком (`ReminderDraftStore`) и применяются кнопкой «Сохранить»: каждый шаг
/// степпера не дёргает систему уведомлений. Переключатель «Напоминать заниматься» действует сразу.
struct ReminderSettingsView: View {
    @AppStorage(SettingsKey.remindersEnabled) private var enabled = SettingsDefault.remindersEnabled
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @Environment(ReminderScheduler.self) private var scheduler
    @Environment(ReminderDraftStore.self) private var store

    private var draft: ReminderDraft { store.current }
    private var mode: ReminderScheduleMode { ReminderScheduleMode(rawValue: draft.schedule) ?? .once }

    /// Поле черновика как `Binding`.
    private func field<Value>(_ path: WritableKeyPath<ReminderDraft, Value>) -> Binding<Value> {
        Binding(get: { store.current[keyPath: path] }, set: { value in store.edit { $0[keyPath: path] = value } })
    }

    /// Время в `DatePicker`: часы и минуты хранятся отдельно, дата не важна.
    private var time: Binding<Date> {
        Binding(
            get: { Self.date(minuteOfDay: draft.hour * 60 + draft.minute) },
            set: { value in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                store.edit {
                    $0.hour = parts.hour ?? SettingsDefault.reminderHour
                    $0.minute = parts.minute ?? SettingsDefault.reminderMinute
                }
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
        Binding(get: { min(store.current.fromHour, 22) }, set: { value in store.edit { $0.setFromHour(value) } })
    }

    private var to: Binding<Int> {
        Binding(get: { min(max(store.current.toHour, from.wrappedValue + 1), 23) },
                set: { value in store.edit { $0.toHour = value } })
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
                            Toggle("Нарастающее", isOn: field(\.escalating))
                            InfoButton(text: HelpText.reminderEscalating)
                        }
                        if draft.escalating {
                            Text(HelpText.reminderEscalatingSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .help(HelpText.reminderEscalating)
                }
                .disabled(!enabled)
                saveRow
                status
                scheduledLine
                Button("Проверить напоминание") { Task { await scheduler.sendTest() } }
                    .disabled(scheduler.authorization != .authorized)
                    .help(HelpText.reminderTest)
            } footer: {
                Text("Напоминание придёт, только если сегодня ещё не набран полный огонь.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            store.reload()
            await scheduler.refreshStatus()
        }
        // Вернулись из «Системных настроек» (разрешение могли дать или отозвать): статус обновляется сразу.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await scheduler.refreshStatus() }
        }
        .onChange(of: enabled) { _, isOn in
            // Разрешение запрашивается только здесь, при включении.
            Task { if isOn { await scheduler.enable() } else { await scheduler.reschedule() } }
        }
    }

    /// «Отменить» и «Сохранить» — только при несохранённых изменениях. Return нажимает «Сохранить», пока виден
    /// этот раздел и есть что сохранять (в других разделах кнопки нет в иерархии).
    private var saveRow: some View {
        HStack {
            if store.isDirty {
                Text("Есть несохранённые изменения")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Отменить") { store.revert() }
                .disabled(!store.isDirty)
            Button("Сохранить") { Task { await store.save(rescheduling: scheduler) } }
                .keyboardShortcut(store.isDirty ? .defaultAction : nil)
                .disabled(!store.isDirty)
        }
    }

    /// «Запланировано: N, ближайшее — …» по настоящим ожидающим уведомлениям; обновляется после каждого пересчёта.
    @ViewBuilder private var scheduledLine: some View {
        if enabled, scheduler.authorization == .authorized, let scheduled = scheduler.scheduled {
            let line = ReminderStatus.line(scheduled: scheduled, now: .now, gaveUp: scheduler.retriesExhausted)
            Label(line.text, systemImage: line.isWarning ? "exclamationmark.triangle" : "clock")
                .foregroundStyle(line.isWarning ? Color.orange : Color.secondary)
            if let capacity = scheduler.capacity {
                Label(ReminderStatus.limitLine(capacity: capacity), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                if let note = ReminderStatus.limitNote(capacity: capacity) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Подпись под временем раньше начала дня: напоминание относится к предыдущему дню.
    @ViewBuilder private func previousDayCaption(_ minuteOfDay: Int) -> some View {
        if let note = ReminderStatus.previousDayNote(minuteOfDay: minuteOfDay, dayStartHour: dayStartHour) {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var schedulePicker: some View {
        Picker("Расписание", selection: field(\.schedule)) {
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
            previousDayCaption(draft.hour * 60 + draft.minute)
        case .thrice:
            DatePicker("Первое", selection: time(field(\.time1)), displayedComponents: .hourAndMinute)
            previousDayCaption(draft.time1)
            DatePicker("Второе", selection: time(field(\.time2)), displayedComponents: .hourAndMinute)
            previousDayCaption(draft.time2)
            DatePicker("Третье", selection: time(field(\.time3)), displayedComponents: .hourAndMinute)
            previousDayCaption(draft.time3)
        case .interval:
            Picker("С часа", selection: from) {
                ForEach(0...22, id: \.self) { Text(Self.hourTitle($0)).tag($0) }
            }
            previousDayCaption(from.wrappedValue * 60)
            Picker("До часа", selection: to) {
                ForEach((from.wrappedValue + 1)...23, id: \.self) { Text(Self.hourTitle($0)).tag($0) }
            }
            Picker("Интервал", selection: field(\.intervalHours)) {
                ForEach(1...4, id: \.self) { Text("\($0) ч").tag($0) }
            }
        }
    }

    private var tonePicker: some View {
        Picker("Тон", selection: field(\.tone)) {
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
