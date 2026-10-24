import SwiftUI

/// Раздел «Обучение»: подсказки, скорость, цель тренировки и день.
struct LearningSettingsView: View {
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var adaptiveTarget = SettingsDefault.adaptiveTargetCpm
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = SettingsDefault.dailyGoalMinutes
    @AppStorage(SettingsKey.spaceThumbHint) private var spaceThumbHint = SettingsDefault.spaceThumbHint
    @Environment(ReminderScheduler.self) private var reminders

    private var speedUnitValue: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        Form {
            Section {
                Picker("Подсказки", selection: $hintMode) {
                    ForEach(HintMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Подсказка для пробела (противоположный большой палец)", isOn: $spaceThumbHint)
                Picker("Скорость", selection: $speedUnit) {
                    ForEach(SpeedUnit.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Цель тренировки", selection: $adaptiveTarget) {
                    ForEach(SettingsDefault.adaptiveTargetOptions, id: \.self) {
                        Text(speedUnitValue.format(Double($0))).tag($0)
                    }
                }
            }
            Section("День") {
                Picker("Дневная цель", selection: $dailyGoal) {
                    ForEach(SettingsDefault.dailyGoalOptions, id: \.self) { Text("\($0) мин").tag($0) }
                }
                Stepper("Новый день начинается в \(dayStartHour):00", value: $dayStartHour, in: 0...6)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Цель и начало дня влияют на текст и дни напоминаний.
        .onChange(of: dailyGoal) { reminders.rescheduleSoon() }
        .onChange(of: dayStartHour) { reminders.rescheduleSoon() }
    }
}
