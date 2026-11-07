import Foundation
import Testing
@testable import TypingCore

private let ruWords = (try? WordList.load(.ru)) ?? WordList(words: [])
private let generator = TextGenerator(wordList: ruWords)
private let ruLetters = Set("оеаинтсрвлкмдпуяыьгзбчйхжшюцщэфъё")
private let someLetters = Set("оеаинтсрвлкм")

private func variant(_ d: MeasureDuration, _ k: MeasureTextKind = .plain) -> MeasureVariant {
    MeasureVariant(duration: d, kind: k, language: .ru)
}

// MARK: - Текст

@Test func plainUsesOnlyOpenLettersAndSpace() {
    for seed in 1...5 {
        let text = MeasureText.make(variant: variant(.seconds(60)), open: someLetters, capitalsLearned: false,
                                    generator: generator, seed: UInt64(seed))!
        #expect(text.allSatisfy { $0 == " " || someLetters.contains($0) })
    }
}

@Test func capsPunctuationNeedsCapitalsAndPunctuation() {
    let v = variant(.seconds(60), .capsPunctuation)
    #expect(MeasureText.make(variant: v, open: someLetters.union(".,"), capitalsLearned: false,
                             generator: generator, seed: 1) == nil)
    #expect(MeasureText.make(variant: v, open: someLetters, capitalsLearned: true, generator: generator, seed: 1) == nil)
    #expect(MeasureText.availability(kind: .capsPunctuation, language: .ru, open: someLetters,
                                     capitalsLearned: false) == .needsCapitals)
    #expect(MeasureText.availability(kind: .capsPunctuation, language: .ru, open: someLetters,
                                     capitalsLearned: true) == .needsPunctuation)
    let text = MeasureText.make(variant: v, open: someLetters.union(".,"), capitalsLearned: true,
                                generator: generator, seed: 1)!
    #expect(text.first!.isUppercase && text.contains(".") && text.contains(","))
    let allowed = someLetters.union(Set(someLetters.map { Character($0.uppercased()) })).union(" .,")
    #expect(text.allSatisfy(allowed.contains))
}

@Test func digitsNeedAnOpenDigit() {
    let v = variant(.seconds(60), .digits)
    #expect(MeasureText.make(variant: v, open: someLetters, capitalsLearned: true, generator: generator, seed: 1) == nil)
    #expect(MeasureText.availability(kind: .digits, language: .ru, open: someLetters,
                                     capitalsLearned: true) == .needsDigits)
    let text = MeasureText.make(variant: v, open: someLetters.union("12"), capitalsLearned: false,
                                generator: generator, seed: 1)!
    #expect(text.contains { $0.isNumber })
    #expect(text.allSatisfy { $0 == " " || someLetters.union("12").contains($0) })
}

@Test func noLettersMeansNoText() {
    #expect(MeasureText.make(variant: variant(.seconds(60)), open: [], capitalsLearned: false,
                             generator: generator, seed: 1) == nil)
}

@Test func text300HasAbout300Chars() {
    for kind in MeasureTextKind.allCases {
        for seed in 1...20 {
            let text = MeasureText.make(variant: variant(.text300, kind), open: ruLetters.union(".,0123456789"),
                                        capitalsLearned: true, generator: generator, seed: UInt64(seed))!
            #expect((285...315).contains(text.count), "\(kind) \(text.count)")
            #expect(!text.hasSuffix(" "))
        }
    }
}

@Test func timerTextsHaveReserve() {
    for (seconds, minutes) in [(60, 1), (120, 2), (300, 5)] {
        for kind in MeasureTextKind.allCases {
            let text = MeasureText.make(variant: variant(.seconds(seconds), kind), open: ruLetters.union(".,0123456789"),
                                        capitalsLearned: true, generator: generator, seed: 7)!
            #expect(text.count >= 1500 * minutes, "\(kind) \(seconds)")
        }
    }
}

@Test func sameSeedSameText() {
    let a = MeasureText.make(variant: variant(.text300), open: ruLetters, capitalsLearned: false, generator: generator, seed: 9)
    let b = MeasureText.make(variant: variant(.text300), open: ruLetters, capitalsLearned: false, generator: generator, seed: 9)
    #expect(a == b)
}

// MARK: - Вариант

@Test func variantKeyRoundTrips() {
    for d in MeasureDuration.allCases {
        for k in MeasureTextKind.allCases {
            let v = MeasureVariant(duration: d, kind: k, language: .en)
            #expect(MeasureVariant(key: v.key) == v)
            let data = try! JSONEncoder().encode(v)
            #expect(try! JSONDecoder().decode(MeasureVariant.self, from: data) == v)
        }
    }
    #expect(variant(.text300).key == "text300:plain:ru")
    #expect(MeasureDuration.seconds(120).rawValue == "120")
    #expect(MeasureDuration(rawValue: "90") == nil)
}

// MARK: - Отбор

private struct Item { let v: MeasureVariant; let day: Int }
private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: Double(day) * 86400) }

@Test func retentionKeepsFirstAndLastFive() {
    let items = (1...8).map { Item(v: variant(.seconds(60)), day: $0) }.shuffled()
    let kept = MeasureRetention.keep(items, variant: \.v, date: { date($0.day) })
    #expect(Set(kept.map(\.day)) == [1, 4, 5, 6, 7, 8])
    let dropped = MeasureRetention.discard(items, variant: \.v, date: { date($0.day) })
    #expect(Set(dropped.map(\.day)) == [2, 3])
}

@Test func retentionKeepsVariantsApart() {
    let a = (1...7).map { Item(v: variant(.seconds(60)), day: $0) }
    let b = (1...3).map { Item(v: variant(.seconds(120)), day: $0) }
    let c = (1...7).map { Item(v: MeasureVariant(duration: .seconds(60), kind: .plain, language: .en), day: $0) }
    let kept = MeasureRetention.keep(a + b + c, variant: \.v, date: { date($0.day) })
    #expect(kept.filter { $0.v == a[0].v }.count == 6)
    #expect(kept.filter { $0.v == b[0].v }.count == 3)
    #expect(kept.filter { $0.v == c[0].v }.count == 6)
}

// MARK: - Повтор

private func recorded(text: String, count: Int, errorEvery: Int, seed: UInt64) -> MeasureReplay {
    var rng = SeededGenerator(seed: seed)
    let chars = Array(text)
    var keys: [ReplayKey] = []
    var t: UInt32 = 0
    let wrong = Array("оеаинтс")
    for i in 0..<min(count, chars.count) {
        t += UInt32(Int.random(in: 30...100, using: &rng))
        if Int.random(in: 0..<400, using: &rng) == 0 { t += UInt32(Int.random(in: 500...3000, using: &rng)) }
        let typed = errorEvery > 0 && Int.random(in: 0..<errorEvery, using: &rng) == 0
            ? wrong.randomElement(using: &rng)! : chars[i]
        keys.append(ReplayKey(position: i, typed: typed, offsetMs: t))
    }
    return MeasureReplay(text: text, keys: keys)
}

@Test func replayRoundTrips() {
    let replay = recorded(text: "Привет, мир! Как дела? 123", count: 100, errorEvery: 4, seed: 1)
    #expect(replay.keys.count == 26)
    #expect(MeasureReplay(data: replay.encoded()) == replay)
    // Пропуск позиции и нестандартные символы.
    let odd = MeasureReplay(text: "abcdef", keys: [
        ReplayKey(position: 0, typed: "a", offsetMs: 0), ReplayKey(position: 3, typed: "é", offsetMs: 5),
        ReplayKey(position: 4, typed: "e", offsetMs: 5), ReplayKey(position: 9, typed: "x", offsetMs: 4_000_000_000),
    ])
    #expect(MeasureReplay(data: odd.encoded()) == odd)
    #expect(MeasureReplay(data: Data()) == nil)
    #expect(MeasureReplay(data: Data([9, 1, 2])) == nil)
    #expect(MeasureReplay(data: Data([1, 5, 3])) == nil)
    let empty = MeasureReplay(text: "abc", keys: [])
    #expect(MeasureReplay(data: empty.encoded()) == empty)
}

@Test func replayDecoderRejectsCorruptData() {
    func varint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while v >= 0x80 { out.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        out.append(UInt8(v))
        return out
    }
    func cat(_ parts: Data...) -> Data { parts.reduce(Data(), +) }
    let one = Data([1])
    let max = UInt64.max
    #expect(MeasureReplay(data: cat(one, varint(max))) == nil)
    #expect(MeasureReplay(data: cat(one, varint(3), varint(max))) == nil)
    #expect(MeasureReplay(data: cat(one, varint(3), varint(UInt64(Int.max)))) == nil)
    // Огромный разрыв и огромная длина символа в исключениях.
    #expect(MeasureReplay(data: cat(one, varint(0), varint(0), varint(1), varint(0), varint(1), varint(max))) == nil)
    #expect(MeasureReplay(data: cat(one, varint(1), varint(1), Data("a".utf8), varint(1), varint(0),
                                    varint(1), varint(0), Data([2]), varint(max))) == nil)
    // Каждый строгий префикс валидного кодирования — nil, без падения.
    let valid = MeasureReplay(text: "abc", keys: [
        ReplayKey(position: 0, typed: "a", offsetMs: 0), ReplayKey(position: 2, typed: "é", offsetMs: 7),
    ])
    let head = cat(one, varint(3), varint(3), Data("abc".utf8), varint(2), varint(0), varint(7))
    let tail = cat(varint(1), varint(1), Data([3]), varint(2), varint(2), Data("é".utf8))
    let full = cat(head, tail)
    #expect(MeasureReplay(data: full) == valid)
    for n in 0..<full.count { #expect(MeasureReplay(data: full.prefix(n)) == nil) }
    // Мусор.
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<300 {
        let bytes = (0..<Int.random(in: 1...40, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
        _ = MeasureReplay(data: Data([1]) + Data(bytes))
        _ = MeasureReplay(data: Data([2]) + Data(bytes))
    }
    // Крайние значения и длинный кластер.
    _ = MeasureReplay(text: "abc", keys: [ReplayKey(position: Int.max, typed: "a", offsetMs: 0)])
    let cluster = Character("e" + String(repeating: "\u{0301}", count: 200))
    let long = MeasureReplay(text: "e", keys: [ReplayKey(position: 0, typed: cluster, offsetMs: 0)])
    #expect(MeasureReplay(data: long.encoded()) == long)
}

@Test func fiveMinutesAt1000CpmFitsTenKilobytes() {
    let text = MeasureText.make(variant: variant(.seconds(300)), open: ruLetters, capitalsLearned: false,
                                generator: generator, seed: 3)!
    let replay = recorded(text: text, count: 5000, errorEvery: 33, seed: 4)
    let data = replay.encoded()
    #expect(replay.keys.count == 5000)
    #expect(data.count <= 10 * 1024, "\(data.count) байт")
    #expect(MeasureReplay(data: data) == replay)
    let textPacked = try! (Data(replay.text.utf8) as NSData).compressed(using: .lzfse) as Data
    print("replay bytes total:", data.count, "text utf8:", replay.text.utf8.count, "text lzfse:", textPacked.count)
}

@Test func timelineIsEvenAndErrorFree() {
    let replay = recorded(text: "привет мир", count: 10, errorEvery: 2, seed: 5)
    let line = replay.timeline(cpm: 1000)
    #expect(line.count == 10)
    #expect(line.map(\.typed) == Array("привет мир"))
    #expect(line.map(\.position) == Array(0..<10))
    for i in 1..<line.count { #expect(line[i].offsetMs - line[i - 1].offsetMs == 60) }
    #expect(replay.timeline(cpm: 0).isEmpty)
}

@Test func asRecordedKeepsOffsetsAndChars() {
    let replay = recorded(text: "привет мир", count: 10, errorEvery: 2, seed: 6)
    #expect(replay.asRecorded == replay.keys)
    let back = MeasureReplay(data: replay.encoded())!
    #expect(back.asRecorded.map(\.offsetMs) == replay.keys.map(\.offsetMs))
    #expect(back.asRecorded.map(\.typed) == replay.keys.map(\.typed))
}

// MARK: - Скорость замера по полному времени

private func keyRun(_ offsetsMs: [UInt32]) -> [ReplayKey] {
    offsetsMs.enumerated().map { ReplayKey(position: $0.offset, typed: "а", offsetMs: $0.element) }
}

@Test func measureSpeedMatchesOldFormulaWithoutPauses() {
    // 121 знак за 60 с: 120 знаков с учётом первого -> 120 в минуту.
    let keys = keyRun((0..<121).map { UInt32($0 * 500) })
    let cpm = MeasureSpeed.cpm(chars: 121, keys: keys, limit: 60, stoppedByTimer: true)
    #expect(abs(cpm - 120) < 0.5)
    var engine = TypingEngine(text: String(repeating: "а", count: 121))
    for k in keys { _ = engine.handle(Keystroke(character: "а", keyCode: 0, timestamp: Double(k.offsetMs) / 1000)) }
    #expect(abs(engine.cpm - cpm) < 1.5)
}

@Test func measureSpeedDropsWithTenSecondPause() {
    let steady = keyRun((0..<101).map { UInt32($0 * 500) })
    let paused = keyRun((0..<101).map { UInt32($0 * 500 + ($0 >= 50 ? 10_000 : 0)) })
    // Остановка таймером: время — весь лимит, знаков стало меньше из-за паузы.
    let fast = MeasureSpeed.cpm(chars: 101, keys: steady, limit: 60, stoppedByTimer: true)
    let slow = MeasureSpeed.cpm(chars: 81, keys: paused, limit: 60, stoppedByTimer: true)
    #expect(slow < fast)
    // Конец текста: от первого нажатия до последнего, паузу не выкидываем.
    let text300 = MeasureSpeed.cpm(chars: 101, keys: paused, limit: nil, stoppedByTimer: false)
    #expect(abs(text300 - 100.0 / 60 * 60) < 0.5)
    #expect(text300 < MeasureSpeed.cpm(chars: 101, keys: steady, limit: nil, stoppedByTimer: false))
}

@Test func measureSpeedIsZeroWithoutProgress() {
    #expect(MeasureSpeed.cpm(chars: 1, keys: keyRun([0]), limit: 60, stoppedByTimer: true) == 0)
    #expect(MeasureSpeed.cpm(chars: 5, keys: [], limit: nil, stoppedByTimer: false) == 0)
}

@Test func allKeysGiveTextWithLettersOfEveryFinger() {
    for language in [Language.ru, .en] {
        let keys = MeasureText.allKeys(language: language)
        let gen = TextGenerator(wordList: (try? WordList.load(language)) ?? WordList(words: []))
        let v = MeasureVariant(duration: .seconds(300), kind: .plain, language: language)
        let text = MeasureText.make(variant: v, open: keys.open, capitalsLearned: keys.capitalsLearned,
                                    generator: gen, seed: 4)
        let used = Set((text ?? "").lowercased().filter { $0 != " " })
        // Слова из частотного словаря: используется почти весь алфавит, а не только «домашний ряд».
        #expect(used.count > language.letters.count * 2 / 3)
        #expect(used.isSubset(of: language.letters))
    }
}
