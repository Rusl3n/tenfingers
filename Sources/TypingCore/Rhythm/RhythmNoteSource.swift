import Foundation

public enum RhythmNoteMode: String, CaseIterable, Sendable {
    case open, closed, problem, words
}

/// Набор нот режима: буквы (для `words` — открытые буквы, из которых слова) и слова.
public struct RhythmNoteSource: Sendable {
    public enum Unavailable: Error, Equatable, Sendable {
        case tooFewLetters, tooFewWords, noStats
    }

    public static let minLetters = 3
    public static let minWords = 20
    public static let maxProblemLetters = 8
    public static let wordLengths = 2...7

    public let mode: RhythmNoteMode
    public let letters: [Character]
    public let words: [String]

    public init(mode: RhythmNoteMode, letters: [Character], words: [String] = []) {
        self.mode = mode
        self.letters = letters
        self.words = words
    }

    /// Собирает набор нот или сообщает, почему режим недоступен. Только строчные символы с пальцем.
    /// - `weak` — слабые буквы по порядку (худшая первая); `errorRates` — доля ошибок по буквам.
    public static func make(
        mode: RhythmNoteMode,
        language: Language,
        open: Set<Character>,
        weak: [Character],
        errorRates: [Character: Double],
        words: [String],
        fingers: [Character: Finger]
    ) throws(Unavailable) -> RhythmNoteSource {
        let playableOpen = open.filter { isPlayable($0, fingers) }.sorted()
        switch mode {
        case .open:
            guard playableOpen.count >= minLetters else { throw .tooFewLetters }
            return RhythmNoteSource(mode: mode, letters: playableOpen)
        case .closed:
            let closed = language.letters.subtracting(open).filter { isPlayable($0, fingers) }.sorted()
            guard closed.count >= minLetters else { throw .tooFewLetters }
            return RhythmNoteSource(mode: mode, letters: closed)
        case .problem:
            let openSet = Set(playableOpen)
            var chosen: [Character] = []
            for letter in weak where openSet.contains(letter) && !chosen.contains(letter) {
                chosen.append(letter)
                if chosen.count == maxProblemLetters { break }
            }
            let rated = errorRates.filter { openSet.contains($0.key) && $0.value > 0 }
            guard !chosen.isEmpty || !rated.isEmpty else { throw .noStats }
            if chosen.count < minLetters {
                let extra = rated.keys
                    .filter { !chosen.contains($0) }
                    .sorted { rated[$0]! != rated[$1]! ? rated[$0]! > rated[$1]! : $0 < $1 }
                chosen += extra.prefix(minLetters - chosen.count)
            }
            guard chosen.count >= minLetters else { throw .tooFewLetters }
            return RhythmNoteSource(mode: mode, letters: chosen)
        case .words:
            let openSet = Set(playableOpen)
            let usable = WordFilter.clean(words).filter { word in
                wordLengths.contains(word.count) && word.allSatisfy { openSet.contains($0) }
            }
            guard usable.count >= minWords else { throw .tooFewWords }
            return RhythmNoteSource(mode: mode, letters: playableOpen, words: usable)
        }
    }

    /// Строчная буква с пальцем (большой палец — только у пробела, он в набор не входит).
    private static func isPlayable(_ character: Character, _ fingers: [Character: Finger]) -> Bool {
        guard character.isLetter, String(character).lowercased() == String(character),
              let finger = fingers[character] else { return false }
        return finger != .thumb
    }
}
