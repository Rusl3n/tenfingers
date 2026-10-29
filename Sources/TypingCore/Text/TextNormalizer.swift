import Foundation

/// Приводит произвольный текст к символам, которые можно набрать на клавиатуре курса.
public enum TextNormalizer {
    private static let replacements: [Character: String] = [
        "«": "\"", "»": "\"", "„": "\"", "“": "\"", "”": "\"", "‘": "'", "’": "'",
        "—": "-", "–": "-", "−": "-", "…": "...", "Ё": "ё",
        "\u{00A0}": " ", "\t": " ", "\n": " ", "\r": " ", "\r\n": " ",
    ]

    /// Невидимые символы нулевой ширины: из текста убираются.
    private static let invisible: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD]

    /// Юникодные пробелы (тонкий, узкий неразрывный, ем, идеографический и т. п.) и разделители строк.
    private static func isUnicodeSpace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            [.spaceSeparator, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
        }
    }

    /// Убирает комбинирующие знаки (U+0300–U+036F), остальное собирает обратно.
    private static func strippingCombiningMarks(_ text: String) -> String {
        let scalars = text.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !(0x0300...0x036F).contains($0.value) }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars)
        return String(result).precomposedStringWithCanonicalMapping
    }

    /// Во что превращается один символ ввода. Сначала он в канонически собранном виде: «й» и «ё» остаются
    /// как есть, если они есть в раскладке, а ударение или диакритика (а́, é) снимаются, только когда
    /// иначе символ не набрать.
    private static func mapped(_ character: Character, allowed: Set<Character>) -> String {
        if character.unicodeScalars.allSatisfy({ invisible.contains($0.value) }) { return "" }
        if isUnicodeSpace(character) { return " " }
        let composed = Character(String(character).precomposedStringWithCanonicalMapping)
        if let replacement = replacements[composed] { return replacement }
        if allowed.contains(composed) { return String(composed) }
        let stripped = strippingCombiningMarks(String(composed))
        return stripped.map { replacements[$0] ?? String($0) }.joined()
    }

    public static func typeable(_ text: String, allowed: Set<Character>) -> String {
        var output = ""
        var lastWasSpace = true
        for character in text {
            let mapped = mapped(character, allowed: allowed)
            for c in mapped where allowed.contains(c) {
                if c == " " {
                    if lastWasSpace { continue }
                    lastWasSpace = true
                } else {
                    lastWasSpace = false
                }
                output.append(c)
            }
        }
        while output.last == " " { output.removeLast() }
        return output
    }

    /// Язык по преобладающим буквам (кириллица или латиница).
    public static func dominantLanguage(_ text: String) -> Language? {
        var cyrillic = 0, latin = 0
        for scalar in text.lowercased().unicodeScalars {
            if (0x430...0x44F).contains(scalar.value) || scalar.value == 0x451 { cyrillic += 1 }
            else if (0x61...0x7A).contains(scalar.value) { latin += 1 }
        }
        if cyrillic == 0 && latin == 0 { return nil }
        return cyrillic >= latin ? .ru : .en
    }
}

// MARK: - Стиль этапа (решение 9) и предложения отрывка

extension TextNormalizer {
    /// Знаки конца предложения и то, что может идти за ними в том же предложении.
    private static let terminals: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["»", "\"", "”", "’", "'", ")", "]"]

    /// Решение 9. `nil` — предложение не годится (символ не открыт, цифра при digits == false).
    /// Кавычки, тире и многоточие — как в `typeable`; заглавная «Ё» → «Е» (Shift+ё в RussianWin не печатается);
    /// `lower` — всё строчными; `punctuation: none` — убрать знаки, кроме апострофа между буквами, если «'» открыт
    /// (дефис между буквами становится пробелом: «кто-то» → «кто то», а не «ктото»).
    public static func styled(_ text: String, style: TextStyle, allowed: Set<Character>, capitals: Bool) -> String? {
        var mappedText = ""
        for character in text {
            // Быстрый путь: один скаляр ASCII или кириллицы (U+0400–U+04FF) — NFC его не меняет, ударений в нём нет;
            // невидимых и юникодных пробелов, кроме « », в этих диапазонах нет. Вывод тот же, что у общего пути.
            if character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
               scalar.value < 0x80 || (0x400...0x4FF).contains(scalar.value) {
                if character == " " || character.isNewline { mappedText.append(" ") }
                else if character == "Ё" { mappedText.append("Е") }
                else if let replacement = replacements[character] { mappedText.append(replacement) }
                else { mappedText.append(character) }
                continue
            }
            if character.unicodeScalars.allSatisfy({ invisible.contains($0.value) }) { continue }
            if isUnicodeSpace(character) || character.isNewline { mappedText.append(" "); continue }
            let composed = Character(String(character).precomposedStringWithCanonicalMapping)
            if composed == "Ё" { mappedText.append("Е"); continue }
            if let replacement = replacements[composed] { mappedText.append(replacement); continue }
            // Ударения (а́) снимаются; прочие символы остаются как есть и проверяются ниже.
            mappedText.append(String(composed.unicodeScalars.filter { $0.value != 0x0301 && $0.value != 0x0300 }
                .map(Character.init)))
        }
        if !style.digits && mappedText.contains(where: { $0.isASCII && $0.isWholeNumber }) { return nil }
        if style.case == .lower { mappedText = mappedText.lowercased() }

        if style.punctuation == .none {
            let chars = Array(mappedText)
            var kept = ""
            for (index, c) in chars.enumerated() {
                if c.isLetter || c.isNumber || c == " " { kept.append(c); continue }
                let betweenLetters = index > 0 && index + 1 < chars.count
                    && chars[index - 1].isLetter && chars[index + 1].isLetter
                if c == "'" && betweenLetters && allowed.contains("'") { kept.append(c) }
                else if c == "-" && betweenLetters { kept.append(" ") }
            }
            mappedText = kept
        }

        let result = mappedText.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !result.isEmpty else { return nil }
        for c in result where c != " " {
            if c.isUppercase {
                guard capitals, c.lowercased().allSatisfy(allowed.contains) else { return nil }
            } else if !allowed.contains(c) {
                return nil
            }
        }
        return result
    }

    /// Предложения отрывка: разрез после «.», «!», «?», «…» (и их повторов, кавычки/скобки за ними — в том же
    /// предложении) перед пробелом; пробелы схлопнуты, пустые выброшены.
    public static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current: [Substring] = []
        for token in text.split(whereSeparator: { $0.isWhitespace || isUnicodeSpace($0) }) {
            current.append(token)
            let core = token.reversed().drop(while: closers.contains)
            if let last = core.first, terminals.contains(last) {
                result.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { result.append(current.joined(separator: " ")) }
        return result
    }
}
