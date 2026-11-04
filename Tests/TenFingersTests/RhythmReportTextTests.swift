import Foundation
import Testing
import TypingCore
@testable import TenFingers

/// В тестах нет переводов приложения: `String(localized:)` отдаёт русский исходный текст.
@Test func timingFollowsTheSignOfTheMeanOffset() {
    #expect(RhythmReportText.timing(-150) == "рано на 150 мс")
    #expect(RhythmReportText.timing(42.4) == "поздно на 42 мс")
    #expect(RhythmReportText.timing(-10) == "рано на 10 мс")
    #expect(RhythmReportText.timing(-9.6) == "рано на 10 мс")
}

@Test func timingNearTheBeatIsOnBeat() {
    #expect(RhythmReportText.timing(0) == "в такт")
    #expect(RhythmReportText.timing(9.4) == "в такт")
    #expect(RhythmReportText.timing(-9.4) == "в такт")
}

@Test func confusionNamesPressedAndExpectedLetters() {
    let line = RhythmReport.Confusion(expected: "ж", pressed: "д", count: 3)
    #expect(RhythmReportText.confusion(line) == "нажато Д вместо Ж ×3")
}

@Test func focusOfRunDefaultsToNothing() {
    #expect(TrainingRun(language: .ru).focus == nil)
    #expect(TrainingRun(language: .ru, focus: ["ж"]).focus == ["ж"])
}

@MainActor @Test func weakLettersOfSummaryComeFromTheReportWithoutSpace() {
    // Три точные буквы заполняют «сильные»; «ж» (все промахи) — слабая, пробел в разбор не входит.
    let characters: [Character] = ["ж", "ж", "ж", "ж", "а", "а", "а", "о", "о", "о", "е", "е", "е", " "]
    let notes = characters.enumerated().map { index, character in
        RhythmNote(index: index, time: 1 + Double(index), character: character,
                   lane: character == " " ? .space : .finger(7), wordIndex: nil)
    }
    let chart = RhythmChart(notes: notes, duration: 30, level: .preset(.easy))
    var game = RhythmGame(chart: chart)
    for note in chart.notes {
        _ = game.press(note.character == "ж" ? "щ" : note.character, at: note.time)
    }
    _ = game.tick(at: 100)
    let run = RhythmRun(language: .ru, mode: .open, level: .easy, style: .pulse)
    let summary = RhythmSummary.make(game: game, chart: chart, run: run, previous: .empty)
    #expect(summary.weakLetters == ["ж"])
}

@MainActor @Test func cleanRunHasNoWeakLettersInSummary() {
    let notes = (0..<4).map { index in
        RhythmNote(index: index, time: 1 + Double(index), character: "ж", lane: .finger(7), wordIndex: nil)
    }
    let chart = RhythmChart(notes: notes, duration: 30, level: .preset(.easy))
    var game = RhythmGame(chart: chart)
    for note in chart.notes { _ = game.press("ж", at: note.time) }
    _ = game.tick(at: 100)
    let run = RhythmRun(language: .ru, mode: .open, level: .easy, style: .pulse)
    #expect(RhythmSummary.make(game: game, chart: chart, run: run, previous: .empty).weakLetters.isEmpty)
}

@Test func minutesSecondsHasNoLeadingZeroInMinutes() {
    #expect(Formatting.minutesSeconds(0) == "0:00")
    #expect(Formatting.minutesSeconds(222) == "3:42")
    #expect(Formatting.minutesSeconds(59.9) == "0:59")
    #expect(Formatting.minutesSeconds(1200) == "20:00")
    #expect(Formatting.minutesSeconds(-3) == "0:00")
}

@MainActor @Test func endlessSummaryTakesSurvivalFromTheReportAndRecordsByTime() {
    // Две точные ноты, дальше сплошные пропуски — здоровье кончается; продержались до ноты, на которой кончилось здоровье.
    let notes = (0..<40).map {
        RhythmNote(index: $0, time: 1 + Double($0), character: "о", lane: .finger(4), wordIndex: nil)
    }
    let chart = RhythmChart(notes: notes, duration: 60, level: .preset(.endless))
    var game = RhythmGame(chart: chart)
    _ = game.press("о", at: 1)
    _ = game.press("о", at: 2)
    _ = game.tick(at: 100)
    let run = RhythmRun(language: .ru, mode: .open, level: .endless, style: .pulse)
    let first = RhythmSummary.make(game: game, chart: chart, run: run, previous: .empty)
    #expect(first.isEndless && !first.cleared)
    #expect(first.survivedSeconds != nil && (first.peakNotesPerMinute ?? 0) >= RhythmEndless.startNotesPerMinute)
    #expect(first.isNewRecord)
    let seconds = first.survivedSeconds ?? 0
    // Прежнее лучшее не меньше — не рекорд; меньше — рекорд (даже у проигранного захода).
    let better = RhythmEndlessRecords(bestSeconds: seconds, bestScore: 1)
    #expect(!RhythmSummary.make(game: game, chart: chart, run: run, previous: .empty, previousEndless: better).isNewRecord)
    let worse = RhythmEndlessRecords(bestSeconds: seconds - 1, bestScore: 1)
    #expect(RhythmSummary.make(game: game, chart: chart, run: run, previous: .empty, previousEndless: worse).isNewRecord)
    // Обычный уровень по-прежнему ничего не знает о бесконечных рекордах и времени.
    let easyRun = RhythmRun(language: .ru, mode: .open, level: .easy, style: .pulse)
    let easy = RhythmSummary.make(game: game, chart: chart, run: easyRun, previous: .empty)
    #expect(!easy.isEndless && !easy.isNewRecord)
}
