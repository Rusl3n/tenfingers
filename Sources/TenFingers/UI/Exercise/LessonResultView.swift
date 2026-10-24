import SwiftUI
import TypingCore

struct LessonResultView: View {
    let summary: ExerciseSummary
    let stars: Int
    let targetCpm: Int
    let hasNext: Bool
    /// Ачивки, полученные за весь урок (и на промежуточных шагах).
    var newAchievements: [Achievement] = []
    /// Пройден последний урок этапа или курса (`ShareEvent.completion`): строка с предложением поделиться.
    var completion: ShareEvent?
    let onRetry: () -> Void
    let onNext: () -> Void
    let onExit: () -> Void

    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue

    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        VStack(spacing: 20) {
            Text(stars > 0 ? String(localized: "Урок пройден") : String(localized: "Нужна точность от 96%"))
                .font(.largeTitle.bold())
            // «?» сбоку, чтобы звёзды остались по центру.
            StarsView(count: stars, size: 34)
                .overlay(alignment: .trailing) {
                    StarsHelpButton(targetCpm: targetCpm, unit: unit, size: 17).offset(x: 30)
                }
            HStack(spacing: 32) {
                metric("Скорость", unit.format(summary.cpm))
                metric("Точность", Formatting.percent(summary.accuracy))
                if targetCpm > 0 { metric("Цель", unit.format(Double(targetCpm))) }
            }
            NextStarHintView(cpm: summary.cpm, accuracy: summary.accuracy, targetCpm: targetCpm, unit: unit)
            NewAchievementCards(achievements: newAchievements)
            if let completion { CompletionShareLine(event: completion) }
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

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
    }
}
