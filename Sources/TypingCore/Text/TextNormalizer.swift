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
