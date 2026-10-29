/// Упражнение на цифры и знаки: числа, даты, время, скобки, кавычки, препинание и т. п.
public enum SymbolDrill {
    private static let digitSet: Set<Character> = Set("0123456789")

    /// Токены по шаблонам через пробел, не короче `length`.
    /// Шаблон используется, только если все его символы есть в `allowed`.
    public static func text<G: RandomNumberGenerator>(
        language: Language, allowed: Set<Character>, generator: TextGenerator, length: Int, rng: inout G
    ) -> String {
        let letters = language.letters.intersection(allowed)
        let words = Array(generator.wordList.words.lazy
            .filter { (3...6).contains($0.count) && $0.allSatisfy(letters.contains) }
            .prefix(500))

        func word(_ rng: inout G) -> String { words.randomElement(using: &rng)! }
        func number(_ rng: inout G) -> String {
            let digits = Int.random(in: 1...4, using: &rng)
            let low = [0, 10, 100, 1000][digits - 1]
            let high = [9, 99, 999, 9999][digits - 1]
            return String(Int.random(in: low...high, using: &rng))
        }
        func padded(_ range: ClosedRange<Int>, _ rng: inout G) -> String {
            let value = Int.random(in: range, using: &rng)
            return value < 10 ? "0\(value)" : "\(value)"
        }
        func between(_ symbol: String) -> (inout G) -> String {
            { rng in word(&rng) + symbol + word(&rng) }
        }
        func after(_ symbol: String) -> (inout G) -> String {
            { rng in word(&rng) + symbol }
        }

        // Шаблоны: нужные символы, нужны ли слова, построение токена. Порядок фиксирован.
        let patterns: [(requires: Set<Character>, usesWords: Bool, make: (inout G) -> String)] = [
            (digitSet, false, { rng in number(&rng) }),
            (digitSet.union("."), false, { rng in
                "\(padded(1...28, &rng)).\(padded(1...12, &rng)).\(Int.random(in: 1900...2030, using: &rng))"
            }),
            (digitSet.union(":"), false, { rng in "\(padded(0...23, &rng)):\(padded(0...59, &rng))" }),
            (digitSet.union("%"), false, { rng in "\(Int.random(in: 1...99, using: &rng))%" }),
            (digitSet.union("№"), false, { rng in "№\(Int.random(in: 1...99, using: &rng))" }),
            (digitSet.union("$"), false, { rng in "$\(Int.random(in: 1...99, using: &rng))" }),
            (Set("()"), true, { rng in "(\(word(&rng)))" }),
            (Set("\""), true, { rng in "\"\(word(&rng))\"" }),
            (Set("'s"), true, { rng in "\(word(&rng))'s" }),  // апостроф — не кавычка: только внутри слова
            (Set("[]"), true, { rng in "[\(word(&rng))]" }),
            (Set(","), true, after(",")),
            (Set("."), true, after(".")),
            (Set("!"), true, after("!")),
            (Set("?"), true, after("?")),
            (Set(";"), true, after(";")),
            (Set(":"), true, after(":")),
            (Set("-"), true, between("-")),
            (Set("_"), true, between("_")),
            (Set("/"), true, between("/")),
            (Set("@"), true, between("@")),
            (Set("#"), true, { rng in "#" + word(&rng) }),
            (digitSet.union("^"), true, { rng in "\(word(&rng))^\(Int.random(in: 2...9, using: &rng))" }),
            (Set("&"), true, between("&")),
            (digitSet.union("*"), false, { rng in
                "\(Int.random(in: 10...99, using: &rng))*\(Int.random(in: 2...9, using: &rng))"
            }),
            (Set("="), true, between("=")),
            (Set("+"), true, between("+")),
            // Пункты списков (урок «Списки»): «3) слово», «2. слово».
            (digitSet.union(")"), true, { rng in "\(Int.random(in: 1...9, using: &rng))) \(word(&rng))" }),
            (digitSet.union("."), true, { rng in "\(Int.random(in: 1...9, using: &rng)). \(word(&rng))" }),
        ]
        let available = patterns.filter { $0.requires.isSubset(of: allowed) && (!$0.usesWords || !words.isEmpty) }
        guard !available.isEmpty else { return "" }

        var result = ""
        while result.count < length {
            let token = available.randomElement(using: &rng)!.make(&rng)
            if !result.isEmpty { result.append(" ") }
            result.append(token)
        }
        return result
    }
}
