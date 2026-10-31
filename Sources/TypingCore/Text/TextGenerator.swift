/// Генерирует тексты упражнений только из разрешённых символов.
public struct TextGenerator: Sendable {
    /// Если реальных слов меньше, к ним подмешиваются псевдослова.
    public static let minimumRealWords = 30

    /// Словарь без слов из списка-исключения (`WordFilter`): отсюда берут слова все генераторы и `SymbolDrill`.
    public let wordList: WordList
    /// Цепь Маркова 2-го порядка: контекст из двух символов → следующий символ ("$" — конец слова).
    private let transitions: [String: [Character: Int]]

    private static let pairs: [Character: (open: Character, close: Character)] = [
        "(": ("(", ")"), ")": ("(", ")"), "[": ("[", "]"), "]": ("[", "]"),
        "\"": ("\"", "\""),
    ]
    /// Апостроф — не кавычка: только внутри слова, как в сокращениях (it's, we'll, they're, i'd, we've).
    private static let apostropheEndings = ["s", "ll", "re", "d", "ve"]
    private static let infix: Set<Character> = ["-", "_", "/", "@", "&", "=", "+", "\\", "|"]
    private static let prefix: Set<Character> = ["№", "#", "$"]
    private static let numberSuffix: Set<Character> = ["%"]

    public init(wordList: WordList, markovSample: Int = 5000) {
        let wordList = WordList(words: WordFilter.clean(wordList.words))
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
        if keys.count > 1 {
            // Смесь первых клавиш по порядку; если она складывается в слово из списка-исключения — со сдвигом.
            let mixes = (0..<keys.count).lazy.map { shift in String((0..<4).map { keys[($0 + shift) % keys.count] }) }
            if let mix = mixes.first(where: { !WordFilter.isBlocked($0) }) { initial.append(mix) }
        }
        return fill(length: length, initial: initial, rng: &rng) { rng in
            unblocked(&rng) { rng in
                String((0..<Int.random(in: 2...5, using: &rng)).map { _ in keys.randomElement(using: &rng)! })
            }
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
            unblocked(&rng) { rng in
                if !newLetters.isEmpty {
                    var chars = [newLetters.randomElement(using: &rng)!]
                    for _ in 0..<Int.random(in: 1...3, using: &rng) {
                        chars.append(known.randomElement(using: &rng)!)
                    }
                    chars.shuffle(using: &rng)
                    return String(chars)
                }
                let word = pseudoWord(letters: Set(known), maxLength: 4, rng: &rng)
                let partner = pseudoWord(letters: Set(known), maxLength: 4, rng: &rng)
                return decorate(word, symbol: newSymbols.randomElement(using: &rng)!,
                                allowed: allowed, partner: partner, rng: &rng)
            }
        }
    }

    /// Реальные слова из разрешённых букв (псевдослова, если слов мало), с фокусом на `focus`.
    /// `pool` — пул слов (§2.6, решение 10); `extraWords` — слова сверх словаря (английские сокращения
    /// с апострофом): каждый токен с вероятностью 0,5 берётся из них, а их знаки к словам не приставляются.
    public func words<G: RandomNumberGenerator>(
        allowed: Set<Character>, focus: Set<Character>, length: Int, capitalRate: Double,
        minimumRealWords: Int = TextGenerator.minimumRealWords, pool kind: WordPool = .all,
        extraWords: [String] = [], rng: inout G
    ) -> String {
        words(allowed: allowed, focus: focus, length: length, capitalRate: capitalRate,
              minimumRealWords: minimumRealWords, pool: pool(letters: allowed.filter(\.isLetter), kind: kind),
              extraWords: extraWords, rng: &rng)
    }

    /// То же с готовым пулом (`pool(letters:kind:)` из букв `allowed`): планировщик считает его один раз на урок.
    /// `focusedByLetter` — готовые слова пула с каждой фокусной буквой (`pool.filter { $0.contains(буква) }`);
    /// буквы, которых в нём нет, считаются здесь. `decorations` — знаки, которые можно приставлять к словам
    /// (`nil` — все открытые): при пунктуации этапа `none` планировщик издания 2 оставляет только новые знаки урока.
    public func words<G: RandomNumberGenerator>(
        allowed: Set<Character>, focus: Set<Character>, length: Int, capitalRate: Double,
        minimumRealWords: Int = TextGenerator.minimumRealWords, pool: [String],
        extraWords: [String] = [], focusedByLetter given: [Character: [String]]? = nil,
        decorations: Set<Character>? = nil, rng: inout G
    ) -> String {
        let letters = allowed.filter(\.isLetter)
        let extra = extraWords.filter { $0.allSatisfy(allowed.contains) }
        let extraSymbols = Set(extra.joined()).filter { !$0.isLetter }
        func decorates(_ c: Character) -> Bool {
            !c.isLetter && c != " " && allowed.contains(c) && !extraSymbols.contains(c) && decorations?.contains(c) ?? true
        }
        let symbols = allowed.filter(decorates).sorted()
        let focusLetters = focus.filter(\.isLetter)
        let focusSymbols = focus.filter(decorates).sorted()
        // Слова по каждой фокусной букве отдельно: редкая буква не должна тонуть среди частых.
        let focusSorted = focusLetters.sorted()
        let focusedByLetter: [Character: [String]] = Dictionary(
            uniqueKeysWithValues: focusSorted.map { letter in
                (letter, given?[letter] ?? pool.filter { $0.contains(letter) })
            })
        let usePseudo = pool.count < minimumRealWords
        let decorateRate = focusSymbols.isEmpty ? 0.2 : 0.6
        guard !letters.isEmpty else { return "" }

        var focusTurn = 0
        return fill(length: length, initial: [], rng: &rng) { rng in
            var word: String
            if !extra.isEmpty && Bool.random(using: &rng) {
                word = extra.randomElement(using: &rng)!
            } else if pool.isEmpty || (usePseudo && Bool.random(using: &rng)) {
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

    /// Правдоподобное псевдослово из заданных букв (цепь Маркова по словарю); слово из списка-исключения
    /// (`WordFilter`) случайно получиться может — тогда пробуем ещё раз.
    public func pseudoWord<G: RandomNumberGenerator>(
        letters: Set<Character>, focus: Set<Character> = [], maxLength: Int = 7, rng: inout G
    ) -> String {
        unblocked(&rng) { rng in markovWord(letters: letters, focus: focus, maxLength: maxLength, rng: &rng) }
    }

    private func markovWord<G: RandomNumberGenerator>(
        letters: Set<Character>, focus: Set<Character>, maxLength: Int, rng: inout G
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

    /// Слова из всего словаря с упором на слабые клавиши и сочетания (≈75% слов содержат фокус).
    /// Цели (клавиши и биграммы) чередуются по кругу, чтобы частые не заглушали редкие.
    /// `pool` — готовый `focusPool(letters:)` (планировщик считает его один раз на урок); нет — считается здесь.
    /// `wordsByTarget` — готовые слова пула с каждой целью (`pool.filter { $0.contains(цель) }`); цели, которых
    /// в нём нет, считаются здесь.
    public func focusedWords<G: RandomNumberGenerator>(letters: Set<Character>, focusKeys: [Character],
                                                       focusBigrams: [String], length: Int, pool: [String]? = nil,
                                                       wordsByTarget given: [String: [String]]? = nil,
                                                       rng: inout G) -> String {
        let pool = pool ?? focusPool(letters: letters)
        guard !pool.isEmpty else { return "" }
        let plain = Array(pool.prefix(2000))
        // Повторы убираем: иначе одна цель получала бы вдвое больше слов.
        let targets = Set(focusKeys).sorted().map { String($0) } + Set(focusBigrams).sorted()
        let wordsByTarget: [String: [String]] = Dictionary(
            targets.map { target in (target, given?[target] ?? pool.filter { $0.contains(target) }) },
            uniquingKeysWith: { first, _ in first })
        var turn = 0
        return fill(length: length, initial: [], rng: &rng) { rng in
            if !targets.isEmpty && Double.random(in: 0..<1, using: &rng) < 0.75 {
                // Берём следующую цель по кругу; цель без слов и без возможности замены пропускаем.
                for _ in 0..<targets.count {
                    let target = targets[turn % targets.count]
                    turn += 1
                    if let candidates = wordsByTarget[target], !candidates.isEmpty {
                        return candidates.randomElement(using: &rng)!
                    }
                    if target.count == 1, let key = target.first, letters.contains(key) {
                        let word = pseudoWord(letters: letters, focus: [key], rng: &rng)
                        if !word.isEmpty { return word }
                    }
                }
            }
            return plain.randomElement(using: &rng)!
        }
    }

    /// Слова для занятия по пальцу (§6.4): из открытых букв `letters`, в каждом не меньше 40% букв из `fingerLetters`.
    /// Таких слов меньше 20 — `focusedWords` с упором на буквы пальца; нет и обычных слов — псевдослова.
    /// `pool` — готовый `focusPool(letters:)`. Текст не короче `length`.
    public func fingerWords<G: RandomNumberGenerator>(letters: Set<Character>, fingerLetters: Set<Character>,
                                                      length: Int, pool: [String]? = nil, rng: inout G) -> String {
        let pool = pool ?? focusPool(letters: letters)
        let matching = pool.filter { word in
            Double(word.filter(fingerLetters.contains).count) >= Self.fingerWordShare * Double(word.count)
        }
        if matching.count >= Self.minimumFingerWords {
            return fill(length: length + 1, initial: [], rng: &rng) { rng in matching.randomElement(using: &rng)! }
        }
        let text = focusedWords(letters: letters, focusKeys: fingerLetters.sorted(), focusBigrams: [],
                                length: length + 1, pool: pool, rng: &rng)
        if !text.isEmpty { return text }
        return words(allowed: letters.union([" "]), focus: fingerLetters, length: length + 1, capitalRate: 0,
                     minimumRealWords: Self.minimumRealWords, rng: &rng)
    }

    static let fingerWordShare = 0.4
    static let minimumFingerWords = 20

    /// Пул `focusedWords` и `errorWords`: первые 8000 слов словаря из букв `letters`.
    public func focusPool(letters: Set<Character>) -> [String] {
        Array(wordList.words.lazy.filter { $0.allSatisfy(letters.contains) }.prefix(8000))
    }

    // MARK: - Вспомогательное

    /// Токен из случайных букв может сложиться в слово из списка-исключения (`WordFilter`): тогда он строится
    /// заново, до 5 раз. Лишние случайные числа берутся только в этом случае — иначе тексты по семени прежние.
    private func unblocked<G: RandomNumberGenerator>(_ rng: inout G, _ make: (inout G) -> String) -> String {
        var token = make(&rng)
        for _ in 0..<5 where WordFilter.isBlocked(token) { token = make(&rng) }
        return token
    }

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
        if symbol == "'" {
            // Окончание сокращения из открытых букв; нет такого — апостроф между словом и вторым словом.
            let endings = Self.apostropheEndings.filter { $0.allSatisfy(allowed.contains) }
            return word + "'" + (endings.randomElement(using: &rng) ?? partner)
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

// MARK: - Генераторы издания 2 (спецификация фазы 6, §2.2, §2.4)
// `fill` считает пробел и после последнего токена; генераторы издания 2 просят `length + 1`,
// чтобы текст был не короче `length`.

extension TextGenerator {
    /// Пул реальных слов из букв `letters` (как раньше `words(using:)`), по виду: all — первые 2000, frequent — первые
    /// 1000, long — от 7 букв среди первых 8000. Считать один раз на урок (Task 3 кэширует).
    public func pool(letters: Set<Character>, kind: WordPool) -> [String] {
        let matching = wordList.words.lazy.filter { $0.allSatisfy(letters.contains) }
        switch kind {
        case .all: return Array(matching.prefix(2000))
        case .frequent: return Array(matching.prefix(1000))
        case .long: return matching.prefix(8000).filter { $0.count >= 7 }
        }
    }

    /// Слова, где доля букв из `rowLetters` не меньше `minShare` (§2.4): меньше 30 слов — порог −0,1 до 0,5;
    /// и тогда меньше 30 — половина токенов псевдословами только из `rowLetters`. `pairs` (два непустых множества) —
    /// не меньше 40% слов содержат буквы обоих (если такие слова есть).
    /// `minShare` 1,0 — «только ряд»: порог не снижается, недостачу восполняют псевдослова из букв ряда.
    /// `selection` — готовый `rowWordsSelection` с теми же параметрами (планировщик считает его один раз на шаг);
    /// тогда `rowLetters`, `allowed`, `minShare`, `pairs` и `pool` не используются.
    public func rowWords<G: RandomNumberGenerator>(rowLetters: Set<Character>, allowed: Set<Character>, minShare: Double,
                                                   length: Int, pairs: (Set<Character>, Set<Character>)? = nil,
                                                   pool: [String]? = nil, selection: RowWordsSelection? = nil,
                                                   rng: inout G) -> String {
        guard let selection = selection ?? rowWordsSelection(rowLetters: rowLetters, allowed: allowed,
                                                             minShare: minShare, pairs: pairs, pool: pool)
        else { return "" }
        let matching = selection.matching, bothWords = selection.bothWords
        var both = 0, count = 0
        return fill(length: length + 1, initial: [], rng: &rng) { rng in
            let word: String
            if !bothWords.isEmpty && Double(both) < 0.4 * Double(count + 1) {
                word = bothWords.randomElement(using: &rng)!
            } else if matching.isEmpty || (selection.usePseudo && Bool.random(using: &rng)) {
                word = pseudoWord(letters: selection.pseudoLetters, rng: &rng)
            } else {
                word = matching.randomElement(using: &rng)!
            }
            count += 1
            if selection.hasBoth(word) { both += 1 }
            return word
        }
    }

    /// Отбор слов `rowWords` (от семени не зависит); `nil` — открытых строчных букв нет.
    public struct RowWordsSelection: Sendable {
        let matching: [String]
        let usePseudo: Bool
        let pseudoLetters: Set<Character>
        let pair: (Set<Character>, Set<Character>)?
        /// Слова `matching` с буквами обоих множеств пары.
        let bothWords: [String]

        func hasBoth(_ word: String) -> Bool { Self.hasBoth(word, pair: pair) }

        static func hasBoth(_ word: String, pair: (Set<Character>, Set<Character>)?) -> Bool {
            guard let pair else { return false }
            return word.contains(where: pair.0.contains) && word.contains(where: pair.1.contains)
        }
    }

    /// Слова пула для `rowWords` с теми же параметрами: доля ряда, снижение порога, пары рядов.
    public func rowWordsSelection(rowLetters: Set<Character>, allowed: Set<Character>, minShare: Double,
                                  pairs: (Set<Character>, Set<Character>)? = nil,
                                  pool: [String]? = nil) -> RowWordsSelection? {
        let letters = Self.lowercaseLetters(allowed)
        let row = rowLetters.intersection(letters)
        guard !letters.isEmpty else { return nil }
        let base = (pool ?? self.pool(letters: letters, kind: .all)).filter { $0.allSatisfy(letters.contains) }
        func share(_ word: String) -> Double { Double(word.filter(row.contains).count) / Double(max(word.count, 1)) }

        var threshold = minShare
        var matching = row.isEmpty ? base : base.filter { share($0) >= threshold - 1e-9 }
        while !row.isEmpty && matching.count < Self.minimumRealWords && minShare < 1 && threshold > 0.5 + 1e-9 {
            threshold = max(0.5, threshold - 0.1)
            matching = base.filter { share($0) >= threshold - 1e-9 }
        }
        // Пары рядов: слова с буквами обоих множеств подмешиваются, пока их доля ниже 40%.
        let pair = pairs.flatMap { $0.0.isEmpty || $0.1.isEmpty ? nil : $0 }
        return RowWordsSelection(matching: matching, usePseudo: matching.count < Self.minimumRealWords,
                                 pseudoLetters: row.isEmpty ? letters : row, pair: pair,
                                 bothWords: matching.filter { RowWordsSelection.hasBoth($0, pair: pair) })
    }

    /// Фразы: группы по 3–6 слов из пула `frequent` (60% слов — с фокусными буквами), без знаков и заглавных.
    /// `focusedByLetter` — готовые слова пула с каждой фокусной буквой; буквы, которых в нём нет, считаются здесь.
    public func phrases<G: RandomNumberGenerator>(allowed: Set<Character>, focus: Set<Character>, length: Int,
                                                  pool: [String]? = nil,
                                                  focusedByLetter given: [Character: [String]]? = nil,
                                                  rng: inout G) -> String {
        let letters = Self.lowercaseLetters(allowed)
        guard !letters.isEmpty else { return "" }
        let words = (pool ?? self.pool(letters: letters, kind: .frequent)).filter { $0.allSatisfy(letters.contains) }
        let focusSorted = focus.filter(letters.contains).sorted()
        let focusedByLetter: [Character: [String]] = Dictionary(
            uniqueKeysWithValues: focusSorted.map { letter in
                (letter, given?[letter] ?? words.filter { $0.contains(letter) })
            })
        let usePseudo = words.count < Self.minimumRealWords

        func word(_ rng: inout G) -> String {
            if !focusSorted.isEmpty && Double.random(in: 0..<1, using: &rng) < 0.6 {
                let letter = focusSorted.randomElement(using: &rng)!
                if let candidates = focusedByLetter[letter], !candidates.isEmpty,
                   !(usePseudo && Bool.random(using: &rng)) {
                    return candidates.randomElement(using: &rng)!
                }
                return pseudoWord(letters: letters, focus: [letter], rng: &rng)
            }
            if words.isEmpty || (usePseudo && Bool.random(using: &rng)) {
                return pseudoWord(letters: letters, rng: &rng)
            }
            return words.randomElement(using: &rng)!
        }

        // Без знаков границ фраз в тексте не видно: последняя фраза обрывается, как только текст дотянул до длины,
        // и перебор — не больше одного слова (§2.6). Группы по 3–6 слов остаются только ради последовательности
        // случайных чисел (тексты на тех же семенах не меняются): не упрощать до одного цикла по словам.
        var tokens: [String] = []
        var total = -1  // без пробела перед первым словом
        while total < length {
            for _ in 0..<Int.random(in: 3...6, using: &rng) where total < length {
                let next = word(&rng)
                tokens.append(next)
                total += next.count + 1
            }
        }
        return tokens.joined(separator: " ")
    }

    /// «Слова с ошибками» (§2.2): 8–10 разных слов, каждое с буквой из `targets` (по кругу), каждое дважды подряд:
    /// «вода вода лук лук …»; разных слов — столько, чтобы текст был не короче `length`, но в пределах 8…10.
    /// `pool` — готовый `focusPool(letters:)` из строчных букв `letters`; нет — считается здесь.
    /// `wordsByTarget` — готовые слова пула с каждой целью; цели, которых в нём нет, считаются здесь.
    public func errorWords<G: RandomNumberGenerator>(letters: Set<Character>, targets: [Character], length: Int,
                                                     pool: [String]? = nil,
                                                     wordsByTarget given: [Character: [String]]? = nil,
                                                     rng: inout G) -> String {
        let letterSet = Self.lowercaseLetters(letters)
        guard !letterSet.isEmpty else { return "" }
        let pool = pool ?? focusPool(letters: letterSet)
        var seenTargets: Set<Character> = []
        let usable = targets.filter { letterSet.contains($0) && seenTargets.insert($0).inserted }
        let byTarget: [Character: [String]] = Dictionary(
            uniqueKeysWithValues: usable.map { target in
                (target, given?[target] ?? pool.filter { $0.contains(target) })
            })
        let plain = Array(pool.prefix(2000))

        var chosen: [String] = []
        var used: Set<String> = []
        var textLength = -1
        var turn = 0
        while chosen.count < 8 || (textLength < length && chosen.count < 10) {
            let target: Character? = usable.isEmpty ? nil : usable[turn % usable.count]
            turn += 1
            let candidates = (target.map { byTarget[$0] ?? [] } ?? plain).filter { !used.contains($0) }
            var word = candidates.randomElement(using: &rng)
            // Слов с целью не осталось — псевдослово с ней; повторы не берём.
            for _ in 0..<10 where word == nil {
                let pseudo = pseudoWord(letters: letterSet, focus: target.map { [$0] } ?? [], rng: &rng)
                if !pseudo.isEmpty && !used.contains(pseudo) { word = pseudo }
            }
            guard let word else { break }
            chosen.append(word)
            used.insert(word)
            textLength += 2 * (word.count + 1)
        }
        return chosen.flatMap { [$0, $0] }.joined(separator: " ")
    }

    /// Слова с заглавной: каждое начинается с буквы из `initials` (реальное слово, иначе псевдослово), первая буква
    /// заглавная; «ё» в начало не ставится. Для уроков Shift (решение 10, поле `focus`).
    public func capitalWords<G: RandomNumberGenerator>(initials: Set<Character>, allowed: Set<Character>, length: Int,
                                                       rng: inout G) -> String {
        let letters = Self.lowercaseLetters(allowed)
        // Shift+ё в RussianWin не даёт «Ё»: с неё слово не начинаем.
        let starts = initials.filter { letters.contains($0) && $0 != "ё" }.sorted()
        guard !starts.isEmpty else { return "" }
        let pool = self.pool(letters: letters, kind: .all)
        let byInitial: [Character: [String]] = Dictionary(
            uniqueKeysWithValues: starts.map { initial in (initial, pool.filter { $0.first == initial }) })
        return fill(length: length + 1, initial: [], rng: &rng) { rng in
            let initial = starts.randomElement(using: &rng)!
            let word: String
            if let candidates = byInitial[initial], !candidates.isEmpty {
                word = candidates.randomElement(using: &rng)!
            } else {
                // Своя первая буква к псевдослову может сложить слово из списка-исключения.
                word = unblocked(&rng) { rng in
                    String(initial) + pseudoWord(letters: letters, rng: &rng).dropFirst()
                }
            }
            return word.prefix(1).uppercased() + word.dropFirst()
        }
    }

    /// Строчные буквы набора: генераторы издания 2 строят слова только из них.
    private static func lowercaseLetters(_ allowed: Set<Character>) -> Set<Character> {
        allowed.filter { $0.isLetter && !$0.isUppercase }
    }
}
