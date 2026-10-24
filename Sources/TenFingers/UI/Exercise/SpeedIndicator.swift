import SwiftUI

enum SpeedState: Equatable { case neutral, ahead, behind }

enum SpeedIndicator {
    /// Пока набрано меньше знаков или чистое время меньше, скорость не оценивается: на старте она скачет.
    static let minimumChars = 10
    static let minimumSeconds: Double = 3

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

    static func accessibilityLabel(cpm: Double, target: Double?, state: SpeedState, unit: SpeedUnit) -> String {
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

    private var color: Color {
        switch state {
        case .neutral: .primary
        case .ahead: .green
        case .behind: .red
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(unit.format(cpm))
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
        .accessibilityLabel(SpeedIndicator.accessibilityLabel(cpm: cpm, target: target, state: state, unit: unit))
    }
}
