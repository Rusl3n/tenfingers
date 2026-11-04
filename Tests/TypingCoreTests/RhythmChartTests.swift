import Foundation
import Testing
@testable import TypingCore

private let ruFingers: [Character: Finger] = [
    "ф": .leftPinky, "ы": .leftRing, "в": .leftMiddle, "а": .leftIndex,
    "о": .rightIndex, "л": .rightMiddle, "д": .rightRing, "ж": .rightPinky,
]
private let enFingers: [Character: Finger] = [
    "a": .leftPinky, "s": .leftRing, "d": .leftMiddle, "f": .leftIndex,
    "j": .rightIndex, "k": .rightMiddle, "l": .rightRing, ";": .rightPinky,
]
private let ruHome = Array("фываолдж")

private func make(
    _ mode: RhythmNoteMode, language: Language = .ru, open: Set<Character> = [],
    weak: [Character] = [], errorRates: [Character: Double] = [:], words: [String] = [],
    fingers: [Character: Finger] = ruFingers
) throws(RhythmNoteSource.Unavailable) -> RhythmNoteSource {
    try RhythmNoteSource.make(mode: mode, language: language, open: open, weak: weak,
                              errorRates: errorRates, words: words, fingers: fingers)
}

/// Причина недоступности режима или `nil`, если набор собран.
private func failure(
    _ mode: RhythmNoteMode, language: Language = .ru, open: Set<Character> = [],
    weak: [Character] = [], errorRates: [Character: Double] = [:], words: [String] = [],
    fingers: [Character: Finger] = ruFingers
) -> RhythmNoteSource.Unavailable? {
    do {
        _ = try make(mode, language: language, open: open, weak: weak, errorRates: errorRates,
                     words: words, fingers: fingers)
        return nil
    } catch { return error }
}

/// Не меньше 20 разных трёхбуквенных «слов» из домашних букв.
private func homeWords() -> [String] {
    var result: [String] = []
    for a in ruHome { for b in ruHome where b != a { for c in ruHome where c != a && c != b {
        result.append(String([a, b, c]))
    } } }
    return Array(result.prefix(60))
}

// MARK: дорожки

@Test func rhythmLanesFollowGivenFingerMap() {
    #expect(RhythmLane.fingerOrder.count == 8)
    #expect(!RhythmLane.fingerOrder.contains(.thumb))
    for (index, letter) in ruHome.enumerated() {
        #expect(RhythmLane.lane(for: letter, fingers: ruFingers) == .finger(index))
    }
    for (index, letter) in Array("asdfjkl;").enumerated() {
        #expect(RhythmLane.lane(for: letter, fingers: enFingers) == .finger(index))
    }
    #expect(RhythmLane.lane(for: " ", fingers: ruFingers) == .space)
    #expect(RhythmLane.lane(for: "я", fingers: ruFingers) == nil)
    #expect(RhythmLane.lane(for: "я", fingers: ["я": .thumb]) == nil)
}

// MARK: набор нот

@Test func rhythmClosedLettersAreLanguageMinusOpen() throws {
    let all = Language.en.letters
    let fingers = Dictionary(uniqueKeysWithValues: all.sorted().map { ($0, Finger.leftIndex) })
    let open = Set("etaoin")
    let source = try make(.closed, language: .en, open: open, fingers: fingers)
    #expect(Set(source.letters) == all.subtracting(open))
    #expect(source.letters == source.letters.sorted())
    #expect(failure(.closed, language: .en, open: all, fingers: fingers) == .tooFewLetters)
    #expect(failure(.closed, language: .en, open: all.subtracting("xy"), fingers: fingers) == .tooFewLetters)
}

@Test func rhythmOpenLettersDropUppercaseAndFingerless() throws {
    let source = try make(.open, open: Set("фываолдж").union(["Ы", "я"]))
    #expect(Set(source.letters) == Set(ruHome))
    #expect(failure(.open, open: ["ф", "ы", "я"]) == .tooFewLetters)
    #expect(failure(.open, open: []) == .tooFewLetters)
}

@Test func rhythmProblemNeedsStatsAndTopsUp() throws {
    let open = Set(ruHome)
    #expect(failure(.problem, open: open) == .noStats)
    // Статистика только по закрытым буквам — как отсутствие статистики.
    #expect(failure(.problem, open: open, weak: ["я"], errorRates: ["я": 0.5]) == .noStats)

    let topped = try make(.problem, open: open, weak: ["а"], errorRates: ["в": 0.2, "о": 0.4, "л": 0.4, "ф": 0.1])
    #expect(topped.letters == ["а", "л", "о"])  // добор: 0,4 (равенство — по символу «л» < «о»), потом 0,4

    let enough = try make(.problem, open: open, weak: ["а", "о", "в", "ы"], errorRates: ["ж": 0.9])
    #expect(enough.letters == ["а", "о", "в", "ы"])

    #expect(failure(.problem, open: open, weak: ["а"], errorRates: ["в": 0.2]) == .tooFewLetters)
    #expect(failure(.problem, open: open, weak: ["а"]) == .tooFewLetters)
    let capped = try make(.problem, open: open, weak: ruHome + ruHome)
    #expect(capped.letters.count == 8)
}

@Test func rhythmWordsFilterAndRequireTwentyWords() throws {
    let open = Set(ruHome)
    let good = homeWords()
    let dirty = ["Вал", "вала!", "я", "в", "фываолдж", "фыва", "ваяла"]
    let source = try make(.words, open: open, words: good + dirty)
    #expect(source.mode == .words)
    #expect(Set(source.words) == Set(good).union(["фыва"]))
    #expect(source.words.allSatisfy { (2...7).contains($0.count) })
    #expect(failure(.words, open: open, words: Array(good.prefix(18)) + dirty) == .tooFewWords)
    #expect(failure(.words, open: open, words: Array(good.prefix(20))) == nil)
}

// MARK: расстановка

private func buildLetters(seed: UInt64, level: RhythmLevel = .preset(.hard)) throws -> RhythmChart {
    let source = try make(.open, open: Set(ruHome))
    return RhythmChartBuilder.build(source: source, level: level, fingers: ruFingers, seed: seed)
}

@Test func rhythmChartIsDeterministicPerSeed() throws {
    let a = try buildLetters(seed: 7)
    #expect(a == (try buildLetters(seed: 7)))
    #expect(a != (try buildLetters(seed: 8)))
    #expect(a.duration == RhythmChartBuilder.trackSeconds)
    #expect(a.level == .preset(.hard))
}

@Test func rhythmChartTimesFillEveryBeat() throws {
    for level in [RhythmLevel.preset(.easy), .preset(.expert)] {
        let chart = try buildLetters(seed: 3, level: level)
        let interval = level.noteInterval
        #expect(!chart.notes.isEmpty)
        for (index, note) in chart.notes.enumerated() {
            #expect(note.index == index)
            #expect(note.time == RhythmChartBuilder.leadIn + Double(index) * interval)
            #expect(note.time < RhythmChartBuilder.trackSeconds)
            #expect(note.lane == RhythmLane.lane(for: note.character, fingers: ruFingers))
        }
        // Следующая доля уже не влезает в трек.
        let next = RhythmChartBuilder.leadIn + Double(chart.notes.count) * interval
        #expect(next >= RhythmChartBuilder.trackSeconds)
        #expect(chart.notes.first?.time == RhythmChartBuilder.leadIn)
    }
}

@Test func rhythmChartNeverRepeatsLetterThreeTimes() {
    let source = RhythmNoteSource(mode: .open, letters: ["ф", "ы"])
    for seed in UInt64(1)...5 {
        let chart = RhythmChartBuilder.build(source: source, level: .preset(.expert), fingers: ruFingers, seed: seed)
        let characters = chart.notes.map(\.character)
        #expect(Set(characters) == ["ф", "ы"])
        for i in 2..<characters.count {
            #expect(!(characters[i] == characters[i - 1] && characters[i] == characters[i - 2]))
        }
    }
}

@Test func rhythmChartWordsRunInChainsWithSpaceBetween() throws {
    let source = try make(.words, open: Set(ruHome), words: homeWords())
    let chart = RhythmChartBuilder.build(source: source, level: .preset(.medium), fingers: ruFingers, seed: 11)
    let notes = chart.notes
    #expect(notes.count > 60)   // на 60 ударах в минуту хватает нот на несколько слов
    let allowed = Set(ruHome).union([" "])
    #expect(notes.allSatisfy { allowed.contains($0.character) })
    #expect(notes.allSatisfy { ($0.character == " ") == ($0.lane == .space) })
    #expect(notes.allSatisfy { ($0.character == " ") == ($0.wordIndex == nil) })

    var position = 0
    var expectedIndex = 0
    while position < notes.count {
        let start = position
        while position < notes.count, notes[position].character != " " { position += 1 }
        let word = notes[start..<position]
        #expect(word.allSatisfy { $0.wordIndex == expectedIndex })
        #expect(source.words.contains(String(word.map(\.character))) || position == notes.count)
        if position < notes.count { #expect(notes[position].lane == .space) }
        position += 1
        expectedIndex += 1
    }
    #expect(Set(notes.compactMap(\.wordIndex)).count == expectedIndex || notes.last?.character != " ")
}
