/// Предложения из открытых слов, когда корпус не подходит по буквам (§2.5, п. 4).
public struct SentenceGenerator: Sendable {
    /// Знаки, которые могут войти в цифровой токен предложения: даты, время, проценты, номера, цены.
    private static let digitSymbols: Set<Character> = [".", ":", "%", "№", "$"]
    /// Генератор без словаря для цифровых токенов: `SymbolDrill` не перебирает 20 000 слов ради шаблонов без слов.
    private static let digitTokens = TextGenerator(wordList: WordList(words: []))

    public let generator: TextGenerator

    public init(generator: TextGenerator) {
        self.generator = generator
    }

    /// 4–9 слов из пула; первое — с заглавной, если `capitals`; «.» в конце, если точка открыта; запятая после
    /// слова (не последнего) с вероятностью 0,12, если открыта; цифровой токен `SymbolDrill` вместо слова
    /// с вероятностью 0,15, если `digits` и цифры открыты. 60% слов — с буквами `focus`, если они есть в пуле.
    public func sentence<G: RandomNumberGenerator>(language: Language, allowed: Set<Character>, capitals: Bool,
                                                   digits: Bool, focus: Set<Character>, pool: [String],
                                                   rng: inout G) -> String {
        Words(allowed: allowed, focus: focus, pool: pool)
            .sentence(generator: generator, language: language, capitals: capitals, digits: digits, rng: &rng)
    }

    /// Предложения через пробел, пока не набрано `length` знаков.
    public func text<G: RandomNumberGenerator>(language: Language, allowed: Set<Character>, capitals: Bool,
                                               digits: Bool, focus: Set<Character>, pool: [String], length: Int,
                                               rng: inout G) -> String {
        let words = Words(allowed: allowed, focus: focus, pool: pool)
        var sentences: [String] = []
        var total = 0  // с пробелом после каждого предложения: текст на 1 короче
        while total <= length {
            let sentence = words.sentence(generator: generator, language: language, capitals: capitals,
                                          digits: digits, rng: &rng)
            if sentence.isEmpty { break }
            sentences.append(sentence)
            total += sentence.count + 1
        }
        return sentences.joined(separator: " ")
    }

    /// Слова пула, отобранные один раз на текст.
    private struct Words {
        let allowed: Set<Character>
        let letters: Set<Character>
        let focus: Set<Character>
        let all: [String]
        let focused: [String]

        init(allowed: Set<Character>, focus: Set<Character>, pool: [String]) {
            self.allowed = allowed
            letters = allowed.filter { $0.isLetter && !$0.isUppercase }
            self.focus = focus.intersection(letters)
            all = pool.filter { [letters] in $0.allSatisfy(letters.contains) }
            focused = all.filter { [focus = self.focus] in $0.contains(where: focus.contains) }
        }

        func sentence<G: RandomNumberGenerator>(generator: TextGenerator, language: Language, capitals: Bool,
                                                digits: Bool, rng: inout G) -> String {
            let useDigits = digits && allowed.contains(where: \.isNumber)
            let digitAllowed = allowed.filter { $0.isNumber || SentenceGenerator.digitSymbols.contains($0) }
            let count = Int.random(in: 4...9, using: &rng)
            var tokens: [String] = []
            for _ in 0..<count {
                var token = ""
                if useDigits && Double.random(in: 0..<1, using: &rng) < 0.15 {
                    token = SymbolDrill.text(language: language, allowed: digitAllowed,
                                             generator: SentenceGenerator.digitTokens, length: 1, rng: &rng)
                }
                if token.isEmpty {
                    if !focused.isEmpty && Double.random(in: 0..<1, using: &rng) < 0.6 {
                        token = focused.randomElement(using: &rng)!
                    } else if !all.isEmpty {
                        token = all.randomElement(using: &rng)!
                    } else {
                        token = generator.pseudoWord(letters: letters, focus: focus, rng: &rng)
                    }
                }
                if !token.isEmpty { tokens.append(token) }
            }
            guard !tokens.isEmpty else { return "" }

            if capitals, let first = tokens[0].first, first.isLetter {
                // Shift+ё в RussianWin не даёт «Ё»: в начале предложения пишется «Е».
                tokens[0] = (first == "ё" ? "Е" : first.uppercased()) + tokens[0].dropFirst()
            }
            if allowed.contains(",") {
                for index in tokens.indices.dropLast() where Double.random(in: 0..<1, using: &rng) < 0.12 {
                    tokens[index] += ","
                }
            }
            var sentence = tokens.joined(separator: " ")
            if allowed.contains(".") { sentence += "." }
            return sentence
        }
    }
}
