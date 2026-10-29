import Foundation

/// Список-исключение грубой лексики (`blocklist.txt`, общий со `scripts/prepare-sentences.py`):
/// такие слова не попадают в тексты упражнений, даже если они есть в частотном словаре.
public enum WordFilter {
    /// Буквы слова для границ «с начала слова» и «слово целиком».
    private static let letter = "[a-zа-яё]"

    /// Одно выражение на весь список; `nil` — список не прочитан (тогда ничего не отсеивается).
    private static let expression: NSRegularExpression? = {
        guard let url = try? CoreResources.url("blocklist", "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try? NSRegularExpression(pattern: pattern(fromList: text))
    }()

    /// Выражение по тексту списка: строки «any|start|word фрагмент», «#» — комментарий.
    static func pattern(fromList text: String) -> String {
        var parts: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2, !fields[0].hasPrefix("#") else { continue }
            switch fields[0] {
            case "any": parts.append("(?:\(fields[1]))")
            case "start": parts.append("(?<!\(letter))(?:\(fields[1]))")
            case "word": parts.append("(?<!\(letter))(?:\(fields[1]))(?!\(letter))")
            default: continue
            }
        }
        return parts.joined(separator: "|")
    }

    /// Есть ли в тексте слово из списка (регистр не важен).
    public static func isBlocked(_ text: String) -> Bool {
        guard let expression else { return false }
        let lower = text.lowercased()
        return expression.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil
    }

    /// Слова без отсеянных (порядок сохраняется).
    public static func clean(_ words: [String]) -> [String] {
        words.filter { !isBlocked($0) }
    }
}
