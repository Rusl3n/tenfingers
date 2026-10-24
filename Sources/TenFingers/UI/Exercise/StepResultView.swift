import SwiftUI
import TypingCore

/// Итог повтора одного шага урока: точность, ошибки, скорость и «Лучший результат!», если стало лучше.
struct StepResultView: View {
    let kind: ExerciseKind
    let summary: ExerciseSummary
    let errors: Int
    let improved: Bool
    /// Звёзды, если повторяли проверочный шаг.
    let stars: Int?
    /// Цель этапа урока: для объяснения звёзд и подсказки до следующей звезды.
    let targetCpm: Int
    /// Ачивки, полученные в сохранении этого шага.
    var newAchievements: [Achievement] = []
    /// Проверка засчитала последний урок этапа или курса (`ShareEvent.stepCompletion`).
    var completion: ShareEvent?
    let onRetry: () -> Void
    let onExit: () -> Void

    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue

    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        VStack(spacing: 20) {
            Text(kind.localizedTitle).font(.largeTitle.bold())
            if improved {
                Label("Лучший результат!", systemImage: "trophy.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
            }
            if let stars {
                StarsView(count: stars, size: 34)
                    .overlay(alignment: .trailing) {
                        StarsHelpButton(targetCpm: targetCpm, unit: unit, size: 17).offset(x: 30)
                    }
            }
            HStack(spacing: 32) {
                metric("Точность", Formatting.percent(summary.accuracy))
                metric("Ошибки", "\(errors)")
                metric("Скорость", unit.format(summary.cpm))
            }
            if stars != nil {
                NextStarHintView(cpm: summary.cpm, accuracy: summary.accuracy, targetCpm: targetCpm, unit: unit)
            }
            NewAchievementsLine(achievements: newAchievements)
            if let completion { CompletionShareLine(event: completion) }
            if !summary.topErrors.isEmpty {
                HStack(spacing: 12) {
                    ForEach(summary.topErrors, id: \.self) { error in
                        Text("\(error.character) × \(error.count)")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            HStack(spacing: 12) {
                Button("К курсу", action: onExit)
                Button("Ещё раз", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
    }
}
