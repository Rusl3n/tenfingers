import SwiftUI

/// Раздел «Обучение»: подсказки, скорость, цель тренировки и день.
struct LearningSettingsView: View {
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var adaptiveTarget = SettingsDefault.adaptiveTargetCpm
    @AppStorage(SettingsKey.trainingLetters) private var trainingLetters = SettingsDefault.trainingLetters
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.firstWeekday) private var firstWeekday = SettingsDefault.firstWeekday
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = SettingsDefault.dailyGoalMinutes
    @AppStorage(SettingsKey.spaceThumbHint) private var spaceThumbHint = SettingsDefault.spaceThumbHint
    @Environment(ReminderScheduler.self) private var reminders
    @Environment(\.modelContext) private var modelContext

    private var speedUnitValue: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        Form {
            Section {
                Picker("Подсказки", selection: $hintMode) {
                    ForEach(HintMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .help(HelpText.hintMode)
                Toggle("Подсказка для пробела (противоположный большой палец)", isOn: $spaceThumbHint)
                    .help(HelpText.spaceThumb)
                Picker("Скорость", selection: $speedUnit) {
                    ForEach(SpeedUnit.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .help(HelpText.speedUnits)
                Picker("Цель тренировки", selection: $adaptiveTarget) {
                    ForEach(SettingsDefault.adaptiveTargetOptions, id: \.self) {
                        Text(speedUnitValue.format(Double($0))).tag($0)
                    }
                }
                .help(HelpText.adaptiveTarget)
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Буквы в тренировках", selection: $trainingLetters) {
                        ForEach(TrainingLetters.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text(HelpText.trainingLettersSetting)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(HelpText.trainingLettersSetting)
            }
            Section("День") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Дневная цель", selection: $dailyGoal) {
                        ForEach(SettingsDefault.dailyGoalOptions, id: \.self) { Text("\($0) мин").tag($0) }
                    }
                    Text(HelpText.dailyGoalChange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(HelpText.dailyGoal + " " + HelpText.dailyGoalChange)
                Stepper("Новый день начинается в \(dayStartHour):00", value: $dayStartHour, in: 0...6)
                    .help(HelpText.dayStart)
                Picker("Первый день недели", selection: $firstWeekday) {
                    ForEach(FirstWeekday.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .help(HelpText.firstWeekday)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Цель и начало дня влияют на текст и дни напоминаний. Новая цель действует с сегодняшнего дня:
        // дни без цели получают прежнюю, запись сегодняшнего дня следует новой, прошлые остаются со своей.
        .onChange(of: dailyGoal) { old, _ in
            DayGoals.goalChangedLogging(context: modelContext, previousGoalSeconds: Double(old) * 60)
            reminders.rescheduleSoon()
        }
        .onChange(of: dayStartHour) { reminders.rescheduleSoon() }
    }
}
