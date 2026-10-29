import SwiftUI
import TypingCore

struct LessonResultView: View {
    let summary: ExerciseSummary
    let stars: Int
    /// Шаги урока: от них зависит пятая звезда и подсказка к ней.
    let steps: [StepStat]
    let targetCpm: Int
    let hasNext: Bool
    /// Ачивки, полученные за весь урок (и на промежуточных шагах).
    var newAchievements: [Achievement] = []
    /// Полный огонь на любом шаге этого прохода урока.
    var fullFlame: FullFlame?
    /// Пройден последний урок этапа или курса (`ShareEvent.completion`): строка с предложением поделиться.
    var completion: ShareEvent?
    /// Курс пройден и средняя скорость проверок не ниже 120 зн/мин (`ShareEvent.certificateOffer`): вторая строка «Поделиться».
    var certificate: ShareEvent? = nil
    /// Итог урока «Ускорение» против ориентира до попытки: строка под метриками.
    var speedup: SpeedupReference.Outcome? = nil
    /// Проверка этапа засчитана, но порог не взят (`GateHint.text`): строка под звёздами.
    var gateText: String? = nil
    /// «Потренировать слабые буквы» — «Повтор» этого этапа (`GateHint.reviewLesson`); `nil` — кнопки нет.
    var onPracticeWeak: (() -> Void)? = nil
    let onRetry: () -> Void
    let onNext: () -> Void
    let onExit: () -> Void

    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue

    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    /// «Нужно не больше 4 ошибок на 100 знаков».
    private var failedTitle: String {
        let rule = StarHintText.errorsRule(accuracy: LessonScoring.passAccuracy)
        return String(localized: "Нужно \(rule)")
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(stars > 0 ? String(localized: "Урок пройден") : failedTitle)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            // «?» сбоку, чтобы звёзды остались по центру.
            StarsView(count: stars, size: 34)
                .overlay(alignment: .trailing) {
                    StarsHelpButton(targetCpm: targetCpm, unit: unit, size: 17).offset(x: 30)
                }
            if let gateText {
                Text(gateText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
            }
            HStack(spacing: 32) {
                metric("Скорость", unit.format(summary.cpm))
                metric("Ошибки", "\(summary.errors)")
                if targetCpm > 0 { metric("Цель", unit.format(Double(targetCpm))) }
            }
            if let speedup { SpeedupOutcomeLine(outcome: speedup, unit: unit) }
            NextStarHintView(cpm: summary.cpm, accuracy: summary.accuracy, errors: summary.errors, chars: summary.chars,
                             targetCpm: targetCpm, steps: steps, unit: unit)
            NewAchievementCards(achievements: newAchievements, fullFlame: fullFlame)
            if let completion { CompletionShareLine(event: completion) }
            if let certificate { CompletionShareLine(event: certificate) }
            if !summary.topErrors.isEmpty {
                VStack(spacing: 6) {
                    Text("Больше всего ошибок").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(summary.topErrors, id: \.self) { error in
                            Text("\(error.character) × \(error.count)")
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            if gateText != nil, let onPracticeWeak {
                Button("Потренировать слабые буквы", action: onPracticeWeak)
                    .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 12) {
                Button("К курсу", action: onExit)
                Button("Ещё раз", action: onRetry)
                    .keyboardShortcut(stars > 0 && hasNext ? nil : .defaultAction)
                if stars > 0 && hasNext {
                    Button("Следующий урок", action: onNext)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
    }

    /// «Рекорд побит: +6%» или «До рекорда не хватило 4 зн/мин»; нехватка в выбранной единице округляется вверх.
    nonisolated static func speedupText(_ outcome: SpeedupReference.Outcome, unit: SpeedUnit) -> String {
        switch outcome {
        case .beaten(let percent):
            return String(localized: "Рекорд побит: +\(percent)%")
        case .short(let cpm):
            let gap = unit.format(Double(cpm), rounding: .up)
            return String(localized: "До рекорда не хватило \(gap)")
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
    }
}

/// Строка итога «Ускорения» против ориентира: «Рекорд побит: +6%» (зелёная) или «До рекорда не хватило 4 зн/мин».
/// Одна на итоге урока и на итоге повтора его проверки.
struct SpeedupOutcomeLine: View {
    let outcome: SpeedupReference.Outcome
    let unit: SpeedUnit

    var body: some View {
        Text(LessonResultView.speedupText(outcome, unit: unit))
            .font(.title3.weight(.semibold))
            .foregroundStyle(isBeaten ? Color.green : Color.secondary)
    }

    private var isBeaten: Bool {
        if case .beaten = outcome { return true }
        return false
    }
}
