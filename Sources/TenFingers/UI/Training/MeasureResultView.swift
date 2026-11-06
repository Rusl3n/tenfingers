import SwiftUI
import TypingCore

/// Итог замера: числа, сравнение с первым и прошлым замером варианта, график варианта.
struct MeasureOutcome: Equatable {
    let cpm: Double
    let accuracy: Double
    let errors: Int
    let chars: Int
}

/// Тексты сравнения итога (чистые функции: без экрана).
enum MeasureResultText {
    /// «+12 зн/мин», «−3 зн/мин», «0 зн/мин».
    static func delta(_ value: Int, unit: SpeedUnit) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "")
        return sign + unit.format(Double(abs(value)))
    }

    static func lines(_ comparison: MeasureComparison, unit: SpeedUnit) -> [String] {
        guard let first = comparison.toFirst else {
            return [String(localized: "Первый замер этого варианта: дальше будет с чем сравнить")]
        }
        let toFirst = delta(first, unit: unit)
        var lines = [String(localized: "К первому замеру: \(toFirst)")]
        if let previous = comparison.toPrevious {
            let toPrevious = delta(previous, unit: unit)
            lines.append(String(localized: "К прошлому замеру: \(toPrevious)"))
        }
        return lines
    }
}

struct MeasureResultView: View {
    let outcome: MeasureOutcome
    let comparison: MeasureComparison
    let history: [MeasureHistoryEntry]
    var newAchievements: [EarnedCard] = []
    var fullFlame: FullFlame?
    /// Повтор этого замера (экран повтора — задача 17): без обработчика кнопки «Повтор» нет.
    var onReplay: (() -> Void)? = nil
    let onDone: () -> Void

    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RunSummaryView(title: String(localized: "Замер скорости"),
                               leadingMetrics: [.init(title: "Знаков", value: "\(outcome.chars)")],
                               cpm: outcome.cpm, accuracy: outcome.accuracy, errors: outcome.errors,
                               lines: MeasureResultText.lines(comparison, unit: unit),
                               newAchievements: newAchievements, fullFlame: fullFlame,
                               primaryTitle: "Готово", onPrimary: onDone,
                               secondaryTitle: onReplay == nil ? nil : "Смотреть запись", onSecondary: onReplay)
                if history.count > 1 { MeasureHistoryChart(entries: history, unit: unit).frame(maxWidth: 420) }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
