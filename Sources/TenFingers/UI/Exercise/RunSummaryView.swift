import SwiftUI
import TypingCore

/// Итог порции или сессии: заголовок, метрики, пояснения и кнопки. Общий для тренировки и практики.
struct RunSummaryView: View {
    struct Metric {
        let title: LocalizedStringKey
        let value: String
    }

    let title: String
    var leadingMetrics: [Metric] = []
    var speedTitle: LocalizedStringKey = "Скорость"
    let cpm: Double
    let accuracy: Double
    var lines: [String] = []
    /// Ачивки этой порции; у итога «Слабых мест» — всей тренировки (`runAchievements`).
    var newAchievements: [Achievement] = []
    let primaryTitle: LocalizedStringKey
    let onPrimary: () -> Void
    var secondaryTitle: LocalizedStringKey?
    var onSecondary: (() -> Void)?

    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue

    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        VStack(spacing: 20) {
            Text(title).font(.largeTitle.bold())
            HStack(spacing: 32) {
                ForEach(Array(leadingMetrics.enumerated()), id: \.offset) { _, metric in
                    metricView(metric.title, metric.value)
                }
                metricView(speedTitle, unit.format(cpm))
                metricView("Точность", Formatting.percent(accuracy))
            }
            if !lines.isEmpty {
                VStack(spacing: 6) {
                    ForEach(lines, id: \.self) { Text($0).font(.title3) }
                }
            }
            NewAchievementCards(achievements: newAchievements)
            HStack(spacing: 12) {
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                }
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }

    private func metricView(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
    }
}
