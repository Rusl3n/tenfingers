import Foundation

/// Почему вид текста недоступен (для неактивной кнопки с подсказкой).
public enum MeasureAvailability: Equatable, Sendable {
    case available
    case needsLetters
    case needsCapitals
    case needsPunctuation
    case needsDigits
}

/// Текст замера из открытых клавиш.
public enum MeasureText {
    /// Длина текста «Текст 300 знаков» и допуск.
    public static let text300Length = 300
    public static let text300Tolerance = 15
    /// Знаков на минуту, с которых считают запас текста таймера, и коэффициент запаса.
    public static let masterCPM = 1000
    public static let reserve = 1.5

    /// Сколько знаков нужно, чтобы текст заведомо не кончился за время таймера.
    public static func minimumLength(for duration: MeasureDuration) -> Int {
        switch duration {
        case .text300: text300Length
        case .seconds(let s): Int((Double(masterCPM) * Double(s) / 60 * reserve).rounded(.up))
        }
    }

    /// Все клавиши замера: буквы языка, цифры и основные знаки, заглавные — всегда, независимо от курса
    /// (решение пользователя: иначе замер не измеряет слепую печать в целом).
    public static func allKeys(language: Language) -> (open: Set<Character>, capitalsLearned: Bool) {
        (language.letters.union("0123456789").union(".,!?:;()\""), true)
    }

    private static func isPunctuation(_ c: Character) -> Bool { !c.isLetter && !c.isNumber && c != " " }

    public static func availability(kind: MeasureTextKind, language: Language, open: Set<Character>,
                                    capitalsLearned: Bool) -> MeasureAvailability {
        let lower = Set(open.flatMap { $0.lowercased() })
        guard !lower.intersection(language.letters).isEmpty else { return .needsLetters }
        switch kind {
        case .plain: return .available
        case .capsPunctuation:
            if !capitalsLearned { return .needsCapitals }
            return open.contains(where: isPunctuation) ? .available : .needsPunctuation
        case .digits:
            return open.contains(where: \.isNumber) ? .available : .needsDigits
        }
    }

    /// Текст замера; `nil`, если вид пока недоступен. `open` — открытые клавиши (буквы, знаки, цифры;
    /// пробел доступен всегда), `capitalsLearned` — пройден ли урок с заглавными.
    /// Отклонение от плана: вместо `stageReached` — `open` и `capitalsLearned`, добавлен `generator`.
    public static func make(variant: MeasureVariant, open: Set<Character>, capitalsLearned: Bool,
                            generator: TextGenerator, seed: UInt64) -> String? {
        guard availability(kind: variant.kind, language: variant.language, open: open,
                           capitalsLearned: capitalsLearned) == .available else { return nil }
        let letters = Set(open.flatMap { $0.lowercased() }).intersection(variant.language.letters)
        let digits = open.filter(\.isNumber).sorted()
        let marks = Set(open.filter(isPunctuation))
        let length = minimumLength(for: variant.duration)
        var rng = SeededGenerator(seed: seed)

        let pool = generator.pool(letters: letters, kind: .all)
        let usePseudo = pool.count < TextGenerator.minimumRealWords
        func word(_ rng: inout SeededGenerator) -> String {
            if pool.isEmpty || (usePseudo && Bool.random(using: &rng)) {
                return generator.pseudoWord(letters: letters, rng: &rng)
            }
            return pool.randomElement(using: &rng)!
        }

        var tokens: [String] = []
        var total = 0
        func add(_ token: String) {
            guard !token.isEmpty else { return }
            tokens.append(token)
            total += token.count + 1
        }

        switch variant.kind {
        case .plain:
            while total <= length { add(word(&rng)) }
        case .digits:
            while total <= length {
                if Double.random(in: 0..<1, using: &rng) < 0.35 {
                    let count = Int.random(in: 1...4, using: &rng)
                    var number = String((0..<count).map { _ in digits.randomElement(using: &rng)! })
                    // Ведущий ноль не нужен, если есть другие цифры.
                    if number.count > 1, number.first == "0", let other = digits.first(where: { $0 != "0" }) {
                        number = String(other) + number.dropFirst()
                    }
                    add(number)
                } else {
                    add(word(&rng))
                }
            }
        case .capsPunctuation:
            let enders = [".", "!", "?"].filter { marks.contains(Character($0)) }
            let inner = marks.subtracting(["(", ")", "[", "]", "\"", ".", "!", "?", ","]).sorted()
            while total <= length {
                var sentence: [String] = []
                for i in 0..<Int.random(in: 4...9, using: &rng) {
                    var w = word(&rng)
                    if i == 0, let f = w.first, f != "ё" {
                        w = f.uppercased() + w.dropFirst()
                    } else if i == 0 { w = "Е" + w.dropFirst() }
                    sentence.append(w)
                }
                if marks.contains(","), sentence.count > 1 {
                    for i in 0..<(sentence.count - 1) where Double.random(in: 0..<1, using: &rng) < 0.15 {
                        sentence[i] += ","
                    }
                }
                if let m = inner.randomElement(using: &rng), sentence.count > 2,
                   Double.random(in: 0..<1, using: &rng) < 0.3 {
                    let i = Int.random(in: 0..<(sentence.count - 1), using: &rng)
                    sentence[i] += String(m)
                }
                if marks.contains("("), marks.contains(")"), sentence.count > 3,
                   Double.random(in: 0..<1, using: &rng) < 0.15 {
                    sentence[1] = "(" + sentence[1]
                    sentence[2] += ")"
                }
                var text = sentence.joined(separator: " ")
                if let end = enders.randomElement(using: &rng) { text += end }
                add(text)
            }
        }
        var text = tokens.joined(separator: " ")
        if variant.duration == .text300 { text = trimmed(text) }
        return text
    }

    /// Обрезка до последнего слова так, чтобы длина была не больше 300 знаков.
    private static func trimmed(_ text: String) -> String {
        guard text.count > text300Length else { return text }
        var cut = String(text.prefix(text300Length))
        // Слово, которое обрезали, отбрасываем целиком, если следующий знак не пробел.
        if text[text.index(text.startIndex, offsetBy: text300Length)] != " ", let space = cut.lastIndex(of: " ") {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces)
    }
}
