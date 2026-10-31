import Testing
@testable import TypingCore

private let thresholdMs = 300.0

private func reports(presses: [Finger: Int], errors: [Finger: Int] = [:],
                     keyEwma: [Character: (ms: Double, presses: Int)] = [:],
                     fingerOf: [Character: Finger] = [:]) -> [FingerReport] {
    FingerTraining.reports(presses: presses, errors: errors, keyEwma: keyEwma, fingerOf: fingerOf,
                           thresholdMs: thresholdMs)
}

private func report(_ list: [FingerReport], _ finger: Finger) -> FingerReport {
    list.first { $0.finger == finger }!
}

// MARK: - Оценка

@Test func fingerWithFewPressesHasNoData() {
    let list = reports(presses: [.leftIndex: 49, .rightIndex: 0], errors: [.leftIndex: 20])
    #expect(report(list, .leftIndex).kind == .noData)
    #expect(report(list, .rightIndex).kind == .noData)
    #expect(report(list, .rightIndex).accuracy == nil)
    // Нет записи вообще — тоже нет данных.
    #expect(report(list, .leftPinky).kind == .noData)
}

@Test func thumbIsNotEvaluated() {
    let list = reports(presses: [.thumb: 500], errors: [.thumb: 100])
    #expect(!list.contains { $0.finger == .thumb })
    #expect(list.count == Finger.allCases.count - 1)
}

@Test func weakNeedsAccuracyBelow97WithFiftyPresses() {
    let list = reports(presses: [.leftPinky: 100, .leftRing: 100, .leftMiddle: 50],
                       errors: [.leftPinky: 4, .leftRing: 3, .leftMiddle: 2])
    #expect(report(list, .leftPinky).kind == .weak)        // 96%
    #expect(report(list, .leftRing).kind != .weak)         // ровно 97%
    #expect(report(list, .leftMiddle).kind == .weak)       // 96% при 50 нажатиях
    #expect(report(list, .leftPinky).accuracy == 0.96)
}

@Test func strongNeedsAccuracyVolumeAndSpeed() {
    let letters: [Character: Finger] = ["а": .leftIndex, "о": .rightIndex, "в": .leftMiddle, "л": .rightMiddle]
    let ewma: [Character: (ms: Double, presses: Int)] = [
        "а": (250, 100), "о": (250, 100), "в": (250, 100), "л": (350, 100),
    ]
    let list = reports(presses: [.leftIndex: 100, .rightIndex: 99, .leftMiddle: 100, .rightMiddle: 100],
                       errors: [.leftIndex: 1, .rightIndex: 0, .leftMiddle: 2, .rightMiddle: 0],
                       keyEwma: ewma, fingerOf: letters)
    #expect(report(list, .leftIndex).kind == .strong)      // 99%, 100 нажатий, 250 мс
    #expect(report(list, .rightIndex).kind == .normal)     // 99 нажатий
    #expect(report(list, .leftMiddle).kind == .normal)     // 98%
    #expect(report(list, .rightMiddle).kind == .normal)    // медленнее порога
}

@Test func strongNeedsSpeedData() {
    let list = reports(presses: [.leftIndex: 200])
    #expect(report(list, .leftIndex).kind == .normal)
    #expect(report(list, .leftIndex).speedCpm == nil)
}

@Test func speedIsPressWeightedAverageOfKeys() {
    // (200·30 + 400·10) / 40 = 250 мс → 240 зн/мин; клавиша без нажатий и чужой палец не учитываются.
    let list = reports(presses: [.leftIndex: 100],
                       keyEwma: ["а": (200, 30), "п": (400, 10), "р": (900, 0), "о": (100, 50)],
                       fingerOf: ["а": .leftIndex, "п": .leftIndex, "р": .leftIndex, "о": .rightIndex])
    #expect(abs(report(list, .leftIndex).speedCpm! - 240) < 1e-9)
}

@Test func speedAtThresholdCountsAsNotWorse() {
    let list = reports(presses: [.leftIndex: 100], keyEwma: ["а": (thresholdMs, 10)], fingerOf: ["а": .leftIndex])
    #expect(report(list, .leftIndex).kind == .strong)
}

// MARK: - Слабейший и сильнейший

@Test func weakestIsLowestAccuracyAmongWeak() {
    let list = reports(presses: [.leftPinky: 100, .leftRing: 100, .rightPinky: 100],
                       errors: [.leftPinky: 5, .leftRing: 10, .rightPinky: 10])
    // Равенство 90% — по порядку Finger.allCases.
    #expect(FingerTraining.weakest(list) == .leftRing)
}

@Test func weakestFallsBackToWorstBelow99() {
    let list = reports(presses: [.leftPinky: 200, .leftRing: 200, .leftMiddle: 20],
                       errors: [.leftPinky: 4, .leftRing: 3, .leftMiddle: 10])
    // 98% и 98,5%: слабых нет; худший — левый мизинец. Палец с < 50 нажатий не участвует.
    #expect(FingerTraining.weakest(list) == .leftPinky)
}

@Test func weakestIsNilWhenAllAtLeast99OrNoData() {
    #expect(FingerTraining.weakest(reports(presses: [.leftPinky: 200], errors: [.leftPinky: 2])) == nil)
    #expect(FingerTraining.weakest(reports(presses: [:])) == nil)
    #expect(FingerTraining.weakest([]) == nil)
}

@Test func strongestIsFastestAmongStrongWithOrderTieBreak() {
    let letters: [Character: Finger] = ["а": .leftIndex, "о": .rightIndex, "в": .leftMiddle]
    let ewma: [Character: (ms: Double, presses: Int)] = ["а": (200, 100), "о": (200, 100), "в": (100, 100)]
    let list = reports(presses: [.leftIndex: 200, .rightIndex: 200, .leftMiddle: 200],
                       errors: [.leftMiddle: 10], keyEwma: ewma, fingerOf: letters)
    // «Левый средний» быстрее всех, но не сильный (95%); при равных 300 зн/мин — левый указательный.
    #expect(FingerTraining.strongest(list) == .leftIndex)
    #expect(FingerTraining.strongest(reports(presses: [:])) == nil)
}

// MARK: - Тексты и порции

private let pinkyLetters: [Character] = ["й", "ф", "я", "ё"]
private let fingerOf: [Character: Finger] = {
    var map: [Character: Finger] = [:]
    for letter in pinkyLetters { map[letter] = .leftPinky }
    for letter in "аолвдкт" { map[letter] = .rightIndex }
    return map
}()
private let open = Set(fingerOf.keys)
private let drillGenerator: TextGenerator = {
    var words = ["вода", "дело", "ток", "ткал", "ложка", "волокно", "доктор", "олово"]
    for a in pinkyLetters { for b in pinkyLetters { for c in "аол" { words.append("\(a)\(c)\(b)") } } }
    return TextGenerator(wordList: WordList(words: words))
}()

private func share(_ word: Substring) -> Double {
    Double(word.filter { pinkyLetters.contains($0) }.count) / Double(word.count)
}

@Test func accuracyPortionsAreThreeTimes150WithFingerWords() {
    var rng = SeededGenerator(seed: 11)
    let specs = FingerTraining.portions(.accuracy, finger: .leftPinky, open: open, fingerOf: fingerOf,
                                        generator: drillGenerator, rng: &rng)
    #expect(specs.count == 3)
    #expect(Set(specs.map(\.id)).count == 3)
    for spec in specs {
        #expect(spec.kind == .words)
        #expect(spec.title == "Точность пальца")
        #expect(spec.text.count >= 150 && spec.text.count < 170)
        #expect(spec.text.split(separator: " ").allSatisfy { share($0) >= 0.4 })
        #expect(spec.text.allSatisfy { $0 == " " || open.contains($0) })
    }
}

@Test func speedPortionsAreFourTimes100() {
    var rng = SeededGenerator(seed: 12)
    let specs = FingerTraining.portions(.speed, finger: .leftPinky, open: open, fingerOf: fingerOf,
                                        generator: drillGenerator, rng: &rng)
    #expect(specs.count == 4)
    #expect(specs.allSatisfy { $0.title == "Скорость пальца" && $0.text.count >= 100 })
}

@Test func fewMatchingWordsFallBackToFocusedWords() {
    // Подходящих слов меньше 20: остальные берутся из общего пула с упором на буквы пальца.
    let generator = TextGenerator(wordList: WordList(words: ["вода", "дело", "ток", "ткал", "ложка", "яол", "фав"]))
    var rng = SeededGenerator(seed: 13)
    let specs = FingerTraining.portions(.accuracy, finger: .leftPinky, open: open, fingerOf: fingerOf,
                                        generator: generator, rng: &rng)
    #expect(specs.count == 3)
    #expect(specs.allSatisfy { $0.text.count >= 150 })
    #expect(specs.allSatisfy { $0.text.contains("я") || $0.text.contains("ф") })
}

@Test func portionsAreDeterministicForSeed() {
    func make(_ seed: UInt64) -> [String] {
        var rng = SeededGenerator(seed: seed)
        return FingerTraining.portions(.accuracy, finger: .leftPinky, open: open, fingerOf: fingerOf,
                                       generator: drillGenerator, rng: &rng).map(\.text)
    }
    #expect(make(7) == make(7))
    #expect(make(7) != make(8))
}

@Test func speedTargetIsTenPercentAboveRoundedToOne() {
    #expect(FingerTraining.targetCpm(speedCpm: 200) == 220)
    #expect(FingerTraining.targetCpm(speedCpm: 233) == 256)   // 256,3
    #expect(FingerTraining.targetCpm(speedCpm: nil) == nil)
}

@Test func sourceNamesFingerAndDrill() {
    #expect(FingerTraining.source(.leftPinky, .accuracy) == "finger:leftPinky:accuracy")
    #expect(FingerTraining.source(.rightRing, .speed) == "finger:rightRing:speed")
}

@Test func windowIsFourteenDays() {
    #expect(FingerTraining.days == 14)
}

// MARK: - Буквы пальцев по истории клавиш

@Test func letterFingersComeFromKeyHistoryWithoutLayout() {
    // Коды хранятся у каждой буквы; заглавная и строчная — одна клавиша; раскладка не нужна.
    let keys = [(character: "а", keyCode: 3, presses: 90), (character: "А", keyCode: 3, presses: 10),
                (character: "о", keyCode: 38, presses: 50), (character: "й", keyCode: 12, presses: 5)]
    let map = FingerTraining.letterFingers(keys: keys, language: .ru)
    #expect(map == ["а": .leftIndex, "о": .rightIndex, "й": .leftPinky])
}

@Test func letterFingersIgnoreForeignLettersAndUnknownCodes() {
    let keys = [(character: "a", keyCode: 0, presses: 10), (character: "ж", keyCode: 9999, presses: 10),
                (character: "ab", keyCode: 3, presses: 10), (character: "о", keyCode: 38, presses: 10)]
    #expect(FingerTraining.letterFingers(keys: keys, language: .ru) == ["о": .rightIndex])
}

@Test func letterFingersDoNotTreatDefaultCodeZeroAsLeftPinky() {
    // keyCode по умолчанию 0 (старые строки без кода) — это и код клавиши «ф»/«a»: доверяем нулю только им.
    let ru = [(character: "ф", keyCode: 0, presses: 10), (character: "о", keyCode: 0, presses: 10)]
    #expect(FingerTraining.letterFingers(keys: ru, language: .ru) == ["ф": .leftPinky])
    let en = [(character: "a", keyCode: 0, presses: 10), (character: "o", keyCode: 0, presses: 10)]
    #expect(FingerTraining.letterFingers(keys: en, language: .en) == ["a": .leftPinky])
}

@Test func letterFingersUseFallbackOnlyForLettersWithoutHistory() {
    let keys = [(character: "а", keyCode: 3, presses: 10)]
    let fallback: [Character: Finger] = ["а": .rightPinky, "п": .leftIndex]
    #expect(FingerTraining.letterFingers(keys: keys, language: .ru, fallback: fallback)
            == ["а": .leftIndex, "п": .leftIndex])
}

@Test func portionsWithoutFingerLettersAreNotAnExercise() {
    var rng = SeededGenerator(seed: 5)
    #expect(FingerTraining.portions(.accuracy, finger: .leftPinky, open: open, fingerOf: [:],
                                    generator: drillGenerator, rng: &rng).isEmpty)
    // Буквы только другого пальца — тоже нет занятия.
    #expect(FingerTraining.portions(.speed, finger: .rightPinky, open: open, fingerOf: fingerOf,
                                    generator: drillGenerator, rng: &rng).isEmpty)
}

@Test func portionsWithoutOpenFingerLettersAreNotAnExercise() {
    // Буквы пальца известны, но ни одна не открыта: занятия нет.
    var rng = SeededGenerator(seed: 6)
    let openWithoutPinky = open.subtracting(pinkyLetters)
    #expect(FingerTraining.portions(.accuracy, finger: .leftPinky, open: openWithoutPinky, fingerOf: fingerOf,
                                    generator: drillGenerator, rng: &rng).isEmpty)
}
