import AppKit
import SwiftUI

/// Раздел «Напоминания»: включение, время и состояние разрешения на уведомления.
struct ReminderSettingsView: View {
    @AppStorage(SettingsKey.remindersEnabled) private var enabled = SettingsDefault.remindersEnabled
    @AppStorage(SettingsKey.reminderHour) private var hour = SettingsDefault.reminderHour
    @AppStorage(SettingsKey.reminderMinute) private var minute = SettingsDefault.reminderMinute
    @Environment(ReminderScheduler.self) private var scheduler

    /// Время в `DatePicker`: часы и минуты хранятся отдельно, дата не важна.
    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                hour = parts.hour ?? SettingsDefault.reminderHour
                minute = parts.minute ?? SettingsDefault.reminderMinute
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Напоминать заниматься", isOn: $enabled)
                DatePicker("Время напоминания", selection: time, displayedComponents: .hourAndMinute)
                    .disabled(!enabled)
                status
            } footer: {
                Text("Напоминание придёт, только если сегодня ещё не набран полный огонь.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { await scheduler.refreshAuthorization() }
        .onChange(of: enabled) { _, isOn in
            // Разрешение запрашивается только здесь, при включении.
            Task { if isOn { await scheduler.enable() } else { await scheduler.reschedule() } }
        }
        .onChange(of: hour) { scheduler.rescheduleSoon() }
        .onChange(of: minute) { scheduler.rescheduleSoon() }
    }

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
