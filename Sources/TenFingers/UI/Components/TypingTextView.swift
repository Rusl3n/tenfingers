import AppKit
import SwiftUI

/// Набранное — серым, текущий символ подсвечен (красным после ошибки), остальное — обычным цветом.
/// Строки переносятся по словам сами; если все не помещаются по высоте, видно окно вокруг курсора
/// (строка перед курсором и следующие), а не обрезанный многоточием конец.
struct TypingTextView: View {
    let target: [Character]
    let position: Int
    let errorAtCursor: Bool

    private static let fontSize: CGFloat = 26
    private static let lineGap: CGFloat = 10
    private static let maxWidth: CGFloat = 820

    /// Ширина знака и высота строки SF Mono того же кегля, что у `.system(design: .monospaced)`.
    private static let metrics: (advance: CGFloat, lineHeight: CGFloat) = {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let advance = ("M" as NSString).size(withAttributes: [.font: font]).width
        return (advance, ceil(NSLayoutManager().defaultLineHeight(for: font)))
    }()

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, Self.maxWidth)
            // Знак про запас: глифы вне SF Mono (№, «) могут оказаться чуть шире.
            let lines = Self.wrap(target, width: max(Int(width / Self.metrics.advance) - 1, 1))
            let capacity = Int((proxy.size.height + Self.lineGap) / (Self.metrics.lineHeight + Self.lineGap))
            let cursor = min(position, target.count)
            let shown = Self.visibleLines(total: lines.count, cursorLine: Self.lineIndex(of: cursor, in: lines),
                                          capacity: capacity)
            VStack(alignment: .leading, spacing: Self.lineGap) {
                ForEach(shown, id: \.self) { index in
                    Text(attributed(lines[index], cursor: cursor))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.system(size: Self.fontSize, design: .monospaced))
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: Self.metrics.lineHeight * 2 + Self.lineGap)
        .accessibilityElement()
        .accessibilityLabel(String(target))
    }

    private func attributed(_ line: Range<Int>, cursor: Int) -> AttributedString {
        let doneEnd = min(max(cursor, line.lowerBound), line.upperBound)
        var done = AttributedString(String(target[line.lowerBound..<doneEnd]))
        done.foregroundColor = .secondary

        var current = AttributedString(line.contains(cursor) ? String(target[cursor]) : "")
        current.backgroundColor = errorAtCursor ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.25)
        current.foregroundColor = errorAtCursor ? .red : .primary
        current.underlineStyle = .single

        let restStart = min(max(cursor + 1, line.lowerBound), line.upperBound)
        var rest = AttributedString(String(target[restStart..<line.upperBound]))
        rest.foregroundColor = .primary
        return done + current + rest
    }

    /// Перенос по словам: пробел остаётся в конце строки, слово длиннее строки режется.
    /// Ширина `width` — в знаках, без учёта пробела в конце строки.
    nonisolated static func wrap(_ text: [Character], width: Int) -> [Range<Int>] {
        guard !text.isEmpty else { return [0..<0] }
        var lines: [Range<Int>] = []
        var start = 0
        while start < text.count {
            var end = min(start + width, text.count)
            if end < text.count {
                if text[end] == " " {
                    end += 1
                } else if let space = text[start..<end].lastIndex(of: " ") {
                    end = space + 1
                }
            }
            lines.append(start..<end)
            start = end
        }
        return lines
    }

    /// Строка с позицией курсора; курсор в конце текста — последняя строка.
    nonisolated static func lineIndex(of position: Int, in lines: [Range<Int>]) -> Int {
        lines.firstIndex { $0.contains(position) } ?? lines.count - 1
    }

    /// Видимые строки: все, если помещаются; иначе от строки перед курсором (при месте на 3 и больше)
    /// или от строки курсора, не дальше конца текста. Хотя бы строка курсора видна всегда.
    nonisolated static func visibleLines(total: Int, cursorLine: Int, capacity: Int) -> Range<Int> {
        let capacity = max(capacity, 1)
        guard total > capacity else { return 0..<total }
        let first = min(max(cursorLine - (capacity >= 3 ? 1 : 0), 0), total - capacity)
        return first..<first + capacity
    }
}

#Preview {
    TypingTextView(target: Array("fjf jfj dkd kdk"), position: 9, errorAtCursor: true).padding()
}
