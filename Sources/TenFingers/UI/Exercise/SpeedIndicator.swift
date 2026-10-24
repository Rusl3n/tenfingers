import SwiftUI

enum SpeedState: Equatable { case neutral, ahead, behind }

enum SpeedIndicator {
    /// Пока набрано меньше знаков или чистое время меньше, скорость не оценивается: на старте она скачет.
    static let minimumChars = 10
    static let minimumSeconds: Double = 3

    /// Пока данных мало, вместо числа показывается прочерк (тот же порог, что и у цвета).
    static func isMeasuring(typedChars: Int, activeSeconds: Double) -> Bool {
        typedChars < minimumChars || activeSeconds < minimumSeconds
    }

    /// Текст крупной скорости: число с единицей или «— зн/мин», пока скорость ещё считается.
    static func speedText(cpm: Double, typedChars: Int, activeSeconds: Double, unit: SpeedUnit) -> String {
        isMeasuring(typedChars: typedChars, activeSeconds: activeSeconds) ? unit.placeholder : unit.format(cpm)
    }

    static func state(cpm: Double, target: Double?, typedChars: Int, activeSeconds: Double) -> SpeedState {
        guard let target, typedChars >= minimumChars, activeSeconds >= minimumSeconds else { return .neutral }
        return cpm >= target ? .ahead : .behind
    }

    /// Несвязанный с цветом признак состояния: стрелка вверх при цели или быстрее, вниз — медленнее.
    static func symbolName(for state: SpeedState) -> String? {
        switch state {
        case .neutral: nil
        case .ahead: "arrow.up"
        case .behind: "arrow.down"
        }
    }

    static func accessibilityLabel(cpm: Double, target: Double?, state: SpeedState, unit: SpeedUnit,
                                   measuring: Bool = false) -> String {
        if measuring { return String(localized: "Скорость ещё считается") }
        let speed = unit.format(cpm)
        guard let target else { return String(localized: "Скорость \(speed)") }
        let goal = unit.format(target)
        switch state {
        case .neutral: return String(localized: "Скорость \(speed), цель \(goal)")
        case .ahead: return String(localized: "Скорость \(speed), цель \(goal), быстрее цели")
        case .behind: return String(localized: "Скорость \(speed), цель \(goal), медленнее цели")
        }
    }
}

/// Крупная скорость по центру шапки: зелёная при цели или быстрее, красная медленнее, цель мелко под числом.
struct SpeedIndicatorView: View {
    let cpm: Double
    let target: Double?
    let typedChars: Int
    let activeSeconds: Double
    let unit: SpeedUnit

    private var state: SpeedState {
        SpeedIndicator.state(cpm: cpm, target: target, typedChars: typedChars, activeSeconds: activeSeconds)
    }

    private var measuring: Bool {
        SpeedIndicator.isMeasuring(typedChars: typedChars, activeSeconds: activeSeconds)
    }

    private var color: Color {
        switch state {
        case .neutral: .primary
        case .ahead: .green
        case .behind: .red
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(SpeedIndicator.speedText(cpm: cpm, typedChars: typedChars, activeSeconds: activeSeconds, unit: unit))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .animation(.easeOut(duration: 0.2), value: state)
            if let target {
                let goal = unit.format(target)
                HStack(spacing: 3) {
                    if let symbol = SpeedIndicator.symbolName(for: state) {
                        Image(systemName: symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color)
                    }
                    Text("Цель: \(goal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpeedIndicator.accessibilityLabel(cpm: cpm, target: target, state: state, unit: unit,
                                                              measuring: measuring))
    }
}
