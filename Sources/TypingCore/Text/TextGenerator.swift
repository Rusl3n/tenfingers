/// Генерирует тексты упражнений только из разрешённых символов.
public struct TextGenerator: Sendable {
    /// Если реальных слов меньше, к ним подмешиваются псевдослова.
    public static let minimumRealWords = 30

    public let wordList: WordList
    /// Цепь Маркова 2-го порядка: контекст из двух символов → следующий символ ("$" — конец слова).
    private let transitions: [String: [Character: Int]]

    private static let pairs: [Character: (open: Character, close: Character)] = [
        "(": ("(", ")"), ")": ("(", ")"), "[": ("[", "]"), "]": ("[", "]"),
        "\"": ("\"", "\""), "'": ("'", "'"),
    ]
    private static let infix: Set<Character> = ["-", "_", "/", "@", "&", "=", "+", "\\", "|"]
    private static let prefix: Set<Character> = ["№", "#", "$"]
    private static let numberSuffix: Set<Character> = ["%"]

    public init(wordList: WordList, markovSample: Int = 5000) {
        self.wordList = wordList
        var table: [String: [Character: Int]] = [:]
        for word in wordList.words.prefix(markovSample) {
            let chars = Array("^^" + word + "$")
            for i in 2..<chars.count {
                table[String(chars[i - 2...i - 1]), default: [:]][chars[i], default: 0] += 1
            }
        }
        transitions = table
    }

    // MARK: - Упражнения

    /// Группы из одних новых клавиш: «аааа оооо аоао …».
    public func drill<G: RandomNumberGenerator>(keys: [Character], length: Int, rng: inout G) -> String {
        guard !keys.isEmpty else { return "" }
        var initial = keys.map { String(repeating: $0, count: 4) }
        if keys.count > 1 { initial.append(String((0..<4).map { keys[$0 % keys.count] })) }
        return fill(length: length, initial: initial, rng: &rng) { rng in
            String((0..<Int.random(in: 2...5, using: &rng)).map { _ in keys.randomElement(using: &rng)! })
        }
    }

    /// Короткие сочетания: каждое содержит хотя бы одну новую клавишу.
    public func combos<G: RandomNumberGenerator>(
        newKeys: [Character], allowed: Set<Character>, length: Int, rng: inout G
    ) -> String {
        let known = allowed.filter(\.isLetter).sorted()
        let newLetters = newKeys.filter(\.isLetter)
        let newSymbols = newKeys.filter { !$0.isLetter }
        guard !known.isEmpty, !newKeys.isEmpty else { return "" }
        return fill(length: length, initial: [], rng: &rng) { rng in
            if !newLetters.isEmpty {
                var chars = [newLetters.randomElement(using: &rng)!]
                for _ in 0..<Int.random(in: 1...3, using: &rng) { chars.append(known.randomElement(using: &rng)!) }
                chars.shuffle(using: &rng)
                return String(chars)
            }
            let word = pseudoWord(letters: Set(known), maxLength: 4, rng: &rng)
            let partner = pseudoWord(letters: Set(known), maxLength: 4, rng: &rng)
            return decorate(word, symbol: newSymbols.randomElement(using: &rng)!,
                            allowed: allowed, partner: partner, rng: &rng)
        }
    }

    /// Реальные слова из разрешённых букв (псевдослова, если слов мало), с фокусом на `focus`.
    public func words<G: RandomNumberGenerator>(
        allowed: Set<Character>, focus: Set<Character>, length: Int, capitalRate: Double, rng: inout G
    ) -> String {
        let letters = allowed.filter(\.isLetter)
        let symbols = allowed.filter { !$0.isLetter && $0 != " " }.sorted()
        let focusLetters = focus.filter(\.isLetter)
        let focusSymbols = focus.filter { !$0.isLetter && allowed.contains($0) }.sorted()
        let pool = Array(wordList.words(using: letters).prefix(2000))
        // Слова по каждой фокусной букве отдельно: редкая буква не должна тонуть среди частых.
        let focusSorted = focusLetters.sorted()
        let focusedByLetter: [Character: [String]] = Dictionary(
            uniqueKeysWithValues: focusSorted.map { letter in (letter, pool.filter { $0.contains(letter) }) })
        let usePseudo = pool.count < Self.minimumRealWords
        let decorateRate = focusSymbols.isEmpty ? 0.2 : 0.6
        guard !letters.isEmpty else { return "" }

        var focusTurn = 0
        return fill(length: length, initial: [], rng: &rng) { rng in
            var word: String
            if pool.isEmpty || (usePseudo && Bool.random(using: &rng)) {
                word = pseudoWord(letters: letters, focus: focusLetters, rng: &rng)
            } else if !focusSorted.isEmpty && Double.random(in: 0..<1, using: &rng) < 0.6 {
                let letter = focusSorted.randomElement(using: &rng)!
                if let candidates = focusedByLetter[letter], !candidates.isEmpty {
                    word = candidates.randomElement(using: &rng)!
                } else {
                    word = pseudoWord(letters: letters, focus: [letter], rng: &rng)
                }
            } else {
                word = pool.randomElement(using: &rng)!
            }
            // «Ё» не капитализируем: Shift+ё в RussianWin даёт не Ё (U+00CB), напечатать её нельзя.
            if capitalRate > 0 && word.first != "ё" && Double.random(in: 0..<1, using: &rng) < capitalRate {
                word = word.prefix(1).uppercased() + word.dropFirst()
            }
            if !symbols.isEmpty && Double.random(in: 0..<1, using: &rng) < decorateRate {
                let symbol: Character
                if !focusSymbols.isEmpty && Double.random(in: 0..<1, using: &rng) < 0.7 {
                    // По кругу, чтобы каждый новый символ гарантированно встретился.
                    symbol = focusSymbols[focusTurn % focusSymbols.count]
                    focusTurn += 1
                } else {
                    symbol = symbols.randomElement(using: &rng)!
                }
                let partner = pool.isEmpty
                    ? pseudoWord(letters: letters, rng: &rng)
                    : pool.randomElement(using: &rng)!
                word = decorate(word, symbol: symbol, allowed: allowed, partner: partner, rng: &rng)
            }
            return word
        }
    }

    /// Правдоподобное псевдослово из заданных букв (цепь Маркова по словарю).
    public func pseudoWord<G: RandomNumberGenerator>(
        letters: Set<Character>, focus: Set<Character> = [], maxLength: Int = 7, rng: inout G
    ) -> String {
        let sortedLetters = letters.sorted()
        guard !sortedLetters.isEmpty else { return "" }
        let targetLength = Int.random(in: 2...max(2, maxLength), using: &rng)
        var chars: [Character] = []
        var context = "^^"
        while chars.count < targetLength {
            let options = (transitions[context] ?? [:]).filter {
                letters.contains($0.key) || ($0.key == "$" && chars.count >= 2)
            }
            let next = options.isEmpty ? sortedLetters.randomElement(using: &rng)! : weightedPick(options, rng: &rng)
            if next == "$" { break }
            chars.append(next)
            context = String(context.last!) + String(next)
        }
        let usableFocus = focus.filter(letters.contains).sorted()
        if !usableFocus.isEmpty, !chars.contains(where: usableFocus.contains) {
            chars[Int.random(in: 0..<chars.count, using: &rng)] = usableFocus.randomElement(using: &rng)!
        }
        return String(chars)
    }

    // MARK: - Вспомогательное

    private func fill<G: RandomNumberGenerator>(
        length: Int, initial: [String], rng: inout G, next: (inout G) -> String
    ) -> String {
        var tokens = initial
        var total = tokens.reduce(0) { $0 + $1.count + 1 }
        while total < length {
            let token = next(&rng)
            if token.isEmpty { break }
            tokens.append(token)
            total += token.count + 1
        }
        return tokens.joined(separator: " ")
    }

    private func decorate<G: RandomNumberGenerator>(
        _ word: String, symbol: Character, allowed: Set<Character>, partner: String, rng: inout G
    ) -> String {
        let digits = allowed.filter(\.isNumber).sorted()
        func number(_ rng: inout G) -> String {
            String((0..<Int.random(in: 1...3, using: &rng)).map { _ in digits.randomElement(using: &rng)! })
        }
        if symbol.isNumber {
            // Число обязательно содержит саму запрошенную цифру.
            var chars = Array(number(&rng))
            chars[Int.random(in: 0..<chars.count, using: &rng)] = symbol
            return String(chars)
        }
        if let pair = Self.pairs[symbol] {
            if allowed.contains(pair.open) && allowed.contains(pair.close) {
                return "\(pair.open)\(word)\(pair.close)"
            }
            return word + String(symbol)
        }
        if Self.infix.contains(symbol) { return word + String(symbol) + partner }
        if Self.prefix.contains(symbol) { return String(symbol) + (digits.isEmpty ? word : number(&rng)) }
        if Self.numberSuffix.contains(symbol) { return (digits.isEmpty ? word : number(&rng)) + String(symbol) }
        return word + String(symbol)
    }

    private func weightedPick<G: RandomNumberGenerator>(_ options: [Character: Int], rng: inout G) -> Character {
        let sorted = options.sorted { $0.key < $1.key }
        var roll = Int.random(in: 0..<sorted.reduce(0) { $0 + $1.value }, using: &rng)
        for (key, weight) in sorted {
            if roll < weight { return key }
            roll -= weight
        }
        return sorted.last!.key
    }
}
