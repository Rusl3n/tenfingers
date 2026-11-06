import Foundation

/// Слово или фраза из целевого текста с признаком «были ошибки».
public struct WordHit: Equatable, Sendable {
    public let text: String
    public let isPhrase: Bool
    public let hadError: Bool

    public init(text: String, isPhrase: Bool, hadError: Bool) {
        self.text = text
        self.isPhrase = isPhrase
        self.hadError = hadError
    }
}

/// Какие записи вправе жить в списке «слов с ошибками»: только настоящие слова из частотного словаря.
public enum ErrorWordFilter {
    /// Фраз нет. Слово — если есть в словаре целиком; с дефисом — ещё и если каждая часть (от двух букв) есть в словаре.
    public static func isAllowed(text: String, isPhrase: Bool, vocabulary: Set<String>) -> Bool {
        if isPhrase { return false }
        let word = text.lowercased()
        if vocabulary.contains(word) { return true }
        guard word.contains("-") else { return false }
        let parts = word.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        return parts.count > 1 && parts.allSatisfy { part in
            part.filter(\.isLetter).count >= ErrorWordTracker.minimumLetters && vocabulary.contains(part)
        }
    }
}

/// Делит целевой текст на слова и сопоставляет их с позициями ошибок.
public enum ErrorWordTracker {
    /// Слова короче этого числа букв не хранятся.
    static let minimumLetters = 2

    /// Слова (буквы, дефис и апостроф между буквами, нижний регистр) из словаря: по хиту на каждое вхождение,
    /// в порядке текста. Фраз нет. Слово короче двух букв или не из словаря не хранится.
    public static func hits(text: String, errorPositions: Set<Int>, vocabulary: Set<String>) -> [WordHit] {
        var result: [WordHit] = []
        var current = ""
        var hadError = false
        var started = false
        func flush() {
            guard started else { return }
            var token = current
            while token.hasPrefix("-") { token.removeFirst() }
            while token.hasSuffix("-") { token.removeLast() }
            // Типографский апостроф хранится прямым: так слово набирается с клавиатуры.
            token = token.replacingOccurrences(of: "\u{2019}", with: "'")
            // Ошибка на дефисе по краю тоже считается ошибкой слова.
            if token.filter(\.isLetter).count >= minimumLetters,
               ErrorWordFilter.isAllowed(text: token, isPhrase: false, vocabulary: vocabulary) {
                result.append(WordHit(text: token.lowercased(), isPhrase: false, hadError: hadError))
            }
            current = ""; hadError = false; started = false
        }
        let chars = Array(text)
        // Апостроф между двумя буквами — часть слова («you're»); по краям — пунктуация.
        func isInnerApostrophe(_ index: Int) -> Bool {
            (chars[index] == "'" || chars[index] == "\u{2019}") && index > 0 && index + 1 < chars.count
                && chars[index - 1].isLetter && chars[index + 1].isLetter
        }
        for (index, char) in chars.enumerated() {
            if char.isLetter || char == "-" || isInnerApostrophe(index) {
                current.append(char)
                started = true
                if errorPositions.contains(index) { hadError = true }
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}
