import SwiftUI
import TypingCore

/// Строка уровня под огнём (§10.3, решение 17): «Уровень 12 · Ученик», тонкая полоска до следующего уровня и
/// подсказка «340 / 1 200 опыта».
struct LevelLine: Equatable {
    let text: String
    /// Доля пути до следующего уровня, 0…1.
    let fraction: Double
    let help: String

    static func make(level: Int, title: LevelTitle, gained: Int, needed: Int,
                     locale: Locale = Formatting.interfaceLocale()) -> LevelLine {
        let have = gained.formatted(.number.locale(locale)), need = needed.formatted(.number.locale(locale))
        return LevelLine(text: YearText.levelLine(level: level, title: title),
                         fraction: needed > 0 ? min(max(Double(gained) / Double(needed), 0), 1) : 0,
                         help: String(localized: "\(have) / \(need) опыта", locale: locale))
    }

    static func make(_ state: YearState) -> LevelLine {
        make(level: state.level, title: state.title, gained: state.gained, needed: state.needed)
    }
}

struct LevelLineView: View {
    let line: LevelLine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: line.text).font(.subheadline.weight(.semibold))
                InfoButton(text: HelpText.level)
            }
            HeaderBar(fraction: line.fraction)
        }
        .help(line.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line.text))
        .accessibilityValue(Text(verbatim: line.help))
    }
}

/// Полоса под строкой шапки главной (уровень, цель дня): одна высота и цвет у обеих.
struct HeaderBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Color.orange).frame(width: proxy.size.width * fraction)
                }
            }
    }
}
