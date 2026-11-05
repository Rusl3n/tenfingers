import SwiftUI
import TypingCore

/// Полосы скорости слева направо по ходу текста; над каждой — её скорость числом, медленные — оранжевым.
/// Читается без наведения мыши; при наведении — слова отрезка (или номер шага).
struct SpeedBars: View {
    /// Скорость каждой полосы; `nil` — пропуск (по отрезку нет времени).
    let values: [Double?]
    let slow: Set<Int>
    let unit: SpeedUnit
    /// Подсказка при наведении на полосу `index` (слова отрезка или номер шага).
    let help: (Int) -> String?
    /// Подписи под левым и правым краем («начало» / «конец», «шаг 1» / «шаг N»); `nil` — без подписей.
    var ends: (String, String)? = nil
    var height: CGFloat = 28

    var body: some View {
        let top = values.compactMap { $0 }.max() ?? 1
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { index in
                    bar(index, top: top)
                }
            }
            if let ends {
                HStack {
                    Text(ends.0)
                    Spacer()
                    Text(ends.1)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: 320)
        .accessibilityElement(children: .contain)
    }

    private func bar(_ index: Int, top: Double) -> some View {
        let value = values[index]
        let share = value.map { max(0.08, $0 / top) } ?? 0.08
        let isSlow = slow.contains(index)
        return VStack(spacing: 2) {
            Text(value.map { "\(unit.wholeValue($0))" } ?? "–")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isSlow ? Color.orange : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            RoundedRectangle(cornerRadius: 2)
                .fill(value == nil ? Color.secondary.opacity(0.25) : isSlow ? Color.orange : Color.accentColor.opacity(0.55))
                .frame(height: height * share)
                .frame(height: height, alignment: .bottom)
        }
        .frame(maxWidth: .infinity)
        .help(help(index) ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label(index)))
    }

    private func label(_ index: Int) -> String {
        let number = index + 1
        guard let value = values[index] else { return String(localized: "Отрезок \(number): нет данных") }
        let speed = unit.format(value)
        return slow.contains(index) ? String(localized: "Отрезок \(number): \(speed), медленно")
            : String(localized: "Отрезок \(number): \(speed)")
    }
}

/// Мини-график шага: «Темп по ходу текста» — скорость по кускам текста от начала к концу; медленные места
/// оранжевым с пояснением, в подсказке — слова куска.
struct SpeedSegmentsChart: View {
    let screen: StepReviewScreen
    let unit: SpeedUnit

    var body: some View {
        if screen.showsChart, let segments = screen.segments {
            VStack(spacing: 4) {
                Text("Темп по ходу текста").font(.caption).foregroundStyle(.secondary)
                SpeedBars(values: segments.map(\.cpm), slow: Set(screen.slow), unit: unit,
                          help: { segments[$0].words(in: screen.text) },
                          ends: (String(localized: "начало"), String(localized: "конец")))
                if !screen.slow.isEmpty {
                    Text("Оранжевым — где вы замедлились").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Строки разбора шага (и строка допуска, если она есть).
struct StepReviewLines: View {
    let screen: StepReviewScreen
    /// Строку «Ошибки на буквах» не показывать: ниже уже стоят плашки ошибочных букв.
    var hidesLetters = false

    var body: some View {
        let lines = hidesLetters ? screen.lines.filter { $0.key != "review.letters" } : screen.lines
        VStack(spacing: 4) {
            ForEach(lines.indices, id: \.self) { index in
                Text(ReviewText.text(lines[index]))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
