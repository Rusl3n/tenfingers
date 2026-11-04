import Foundation
import Testing
@testable import TypingCore

private let fingers: [Character: Finger] = [
    "ф": .leftPinky, "ы": .leftRing, "в": .leftMiddle, "а": .leftIndex,
    "о": .rightIndex, "л": .rightMiddle, "д": .rightRing, "ж": .rightPinky,
]

private func endlessChart(words: Bool = false, seed: UInt64 = 7) -> RhythmChart {
    let source = words
        ? RhythmNoteSource(mode: .words, letters: [], words: ["фыв", "оал", "дж"])
        : RhythmNoteSource(mode: .open, letters: Array("фываолдж"))
    return RhythmChartBuilder.build(source: source, level: .preset(.endless), fingers: fingers, seed: seed)
}

@Suite struct RhythmEndlessTests {
    @Test func scheduleSteps() {
        let expected = Array(stride(from: 40, through: 150, by: 5)) + Array(stride(from: 160, through: 300, by: 10))
        #expect(expected.count == 38)
        for (step, n) in expected.enumerated() { #expect(RhythmEndless.notesPerMinute(step: step) == n) }
        for step in 38...80 { #expect(RhythmEndless.notesPerMinute(step: step) == 300) }
        #expect(RhythmEndless.notesPerMinute(step: -3) == 40)
    }

    @Test func stepIsSixteenNotes() {
        for i in 0..<16 { #expect(RhythmEndless.notesPerMinute(noteIndex: i) == 40) }
        for i in 16..<32 { #expect(RhythmEndless.notesPerMinute(noteIndex: i) == 45) }
        #expect(RhythmEndless.notesPerMinute(noteIndex: 32) == 50)
        #expect(RhythmEndless.notesPerMinute(noteIndex: 10_000) == 300)
        #expect(RhythmEndless.notesPerMinute(noteIndex: -1) == 40)
    }

    @Test func tempoProgressRunsFromStartToCeiling() {
        #expect(RhythmEndless.tempoProgress(noteIndex: 0) == 0)
        #expect(RhythmEndless.tempoProgress(noteIndex: 16) == 5.0 / 260)
        #expect(RhythmEndless.tempoProgress(noteIndex: 10_000) == 1)
    }

    @Test func beatTempo() {
        #expect(RhythmEndless.beatBPM(notesPerMinute: 40) == 40)
        #expect(RhythmEndless.beatBPM(notesPerMinute: 150) == 150)
        #expect(RhythmEndless.beatBPM(notesPerMinute: 160) == 80)
        #expect(RhythmEndless.beatBPM(notesPerMinute: 300) == 150)
    }

    @Test func scrollSecondsLinearAndMonotonic() {
        #expect(abs(RhythmEndless.scrollSeconds(notesPerMinute: 40) - 3.6) < 1e-9)
        #expect(abs(RhythmEndless.scrollSeconds(notesPerMinute: 300) - 1.6) < 1e-9)
        #expect(abs(RhythmEndless.scrollSeconds(notesPerMinute: 170) - 2.6) < 1e-9)
        var previous = Double.infinity
        for step in 0...40 {
            let value = RhythmEndless.scrollSeconds(notesPerMinute: RhythmEndless.notesPerMinute(step: step))
            #expect(value <= previous)
            previous = value
        }
    }

    @Test func windowScale() {
        #expect(RhythmEndless.windowScale(notesPerMinute: 40) == 1)
        #expect(RhythmEndless.windowScale(notesPerMinute: 150) == 1)
        #expect(abs(RhythmEndless.windowScale(notesPerMinute: 160) - 0.9375) < 1e-9)
        #expect(abs(RhythmEndless.windowScale(notesPerMinute: 300) - 0.5) < 1e-9)
    }

    @Test func presetIsStartOfSchedule() {
        let level = RhythmLevel.preset(.endless)
        #expect(level.id == .endless && level.bpm == 40 && level.notesPerBeat == 1 && level.scrollSeconds == 3.6)
        #expect(RhythmLevelID.allCases.last == .endless)
    }

    @Test func chartTimesFollowSteps() {
        let chart = endlessChart()
        #expect(chart.duration == RhythmEndless.trackSeconds)
        #expect(chart.notes[0].time == RhythmChartBuilder.leadIn)
        var expected = RhythmChartBuilder.leadIn
        for note in chart.notes {
            #expect(abs(note.time - expected) < 1e-6)
            expected += 60 / Double(RhythmEndless.notesPerMinute(noteIndex: note.index))
        }
        // Шаг внутри ступени и на границе ступеней.
        #expect(abs(chart.notes[1].time - chart.notes[0].time - 1.5) < 1e-9)
        #expect(abs(chart.notes[16].time - chart.notes[15].time - 1.5) < 1e-9)
        #expect(abs(chart.notes[17].time - chart.notes[16].time - 60.0 / 45) < 1e-9)
        // Трек заполнен до конца: последняя нота внутри, следующая уже за пределом.
        #expect(chart.notes.last!.time < RhythmEndless.trackSeconds)
        #expect(expected >= RhythmEndless.trackSeconds)
    }

    @Test func notesCarryTheirStepFlightAndWindows() {
        let chart = endlessChart()
        for note in chart.notes {
            let n = RhythmEndless.notesPerMinute(noteIndex: note.index)
            #expect(note.scrollSeconds == RhythmEndless.scrollSeconds(notesPerMinute: n))
            #expect(note.windowScale == RhythmEndless.windowScale(notesPerMinute: n))
            #expect(chart.scrollSeconds(of: note) == note.scrollSeconds)
        }
        #expect(chart.notes.last!.windowScale == 0.5)
    }

    @Test func laterNoteIsAlwaysAboveEarlier() {
        let chart = endlessChart()
        // Высота ноты в момент `t`: 1 — линия, 0 — верх. Нота видна, пока t в [время − полёт, время].
        func height(_ note: RhythmNote, at t: TimeInterval) -> Double {
            1 - (note.time - t) / chart.scrollSeconds(of: note)
        }
        for i in 1..<chart.notes.count {
            let early = chart.notes[i - 1], late = chart.notes[i]
            #expect(late.time > early.time)
            #expect(late.scrollSeconds! <= early.scrollSeconds!)
            // Проверяем, пока обе на поле: от появления поздней до прихода ранней.
            let start = late.time - late.scrollSeconds!
            let end = early.time
            guard start < end else { continue }
            for k in 0...4 {
                let t = start + (end - start) * Double(k) / 4
                #expect(height(late, at: t) <= height(early, at: t) + 1e-9)
            }
        }
    }

    @Test func wordsModeFillsEndlessTrack() {
        let chart = endlessChart(words: true)
        #expect(chart.notes.count == endlessChart().notes.count)
        #expect(chart.notes.contains { $0.lane == .space })
    }

    @Test func regularLevelsAreUnchanged() {
        let source = RhythmNoteSource(mode: .open, letters: Array("фываолдж"))
        let chart = RhythmChartBuilder.build(source: source, level: .preset(.medium), fingers: fingers, seed: 3)
        #expect(chart.duration == RhythmChartBuilder.trackSeconds)
        for note in chart.notes {
            #expect(note.scrollSeconds == nil && note.windowScale == 1)
            #expect(chart.scrollSeconds(of: note) == 3.0)
        }
    }

    // MARK: - Ступени и фаза бита

    @Test func segmentsStartAtStepFirstNotes() {
        let chart = endlessChart()
        let segments = RhythmEndless.segments(until: RhythmEndless.trackSeconds)
        #expect(segments.count > 38)
        for (k, segment) in segments.enumerated() {
            let note = chart.notes[k * RhythmEndless.stepNotes]
            #expect(abs(segment.startTime - note.time) < 1e-9)
            #expect(segment.notesPerMinute == RhythmEndless.notesPerMinute(step: k))
            #expect(segment.bpm == RhythmEndless.beatBPM(notesPerMinute: segment.notesPerMinute))
        }
        #expect(segments[0].startTime == RhythmChartBuilder.leadIn)
        // Все ступени, начавшиеся раньше предела, и только они.
        #expect(segments.last!.startTime < RhythmEndless.trackSeconds)
        #expect(RhythmEndless.segments(until: RhythmEndless.trackSeconds + 1).count >= segments.count)
        #expect(RhythmEndless.segments(until: RhythmChartBuilder.leadIn).isEmpty)
    }

    @Test func segmentBeatsMatchItsNotes() {
        let chart = endlessChart()
        let segments = RhythmEndless.segments(until: RhythmEndless.trackSeconds)
        for (k, segment) in segments.enumerated() {
            #expect(segment.beats == (segment.notesPerMinute <= 150 ? 16 : 8))
            // Доли ступени (с учётом плотности) совпадают с её нотами: 16 нот — 16 долей или 8 долей по две ноты.
            let notesPerBeat = segment.bpm == segment.notesPerMinute ? 1 : 2
            #expect(segment.beats * notesPerBeat == RhythmEndless.stepNotes)
            let beatSeconds = 60 / Double(segment.bpm)
            #expect(abs(segment.length - Double(segment.beats) * beatSeconds) < 1e-9)
            // Следующая ступень начинается ровно через длину этой, как и по времени нот.
            if k + 1 < segments.count {
                #expect(abs(segments[k + 1].startTime - segment.startTime - segment.length) < 1e-9)
            }
            // Каждая нота ступени стоит на доле или полудоле.
            for i in 0..<RhythmEndless.stepNotes where k * RhythmEndless.stepNotes + i < chart.notes.count {
                let note = chart.notes[k * RhythmEndless.stepNotes + i]
                let slot = (note.time - segment.startTime) / (beatSeconds / Double(notesPerBeat))
                #expect(abs(slot - Double(i)) < 1e-6)
            }
        }
    }

    @Test func beatPositionInsideStepMatchesLoopRule() {
        // Внутри одной ступени — позиция петли `(trackTime − leadIn − сдвиг)` по модулю её длины,
        // отсчитанная от начала ступени (как RhythmBeatPhase.loopPosition у обычных уровней).
        let segments = RhythmEndless.segments(until: RhythmEndless.trackSeconds)
        for k in [0, 1, 5, 22, 23, 30] {
            let segment = segments[k]
            for offset in [0.0, 0.05, -0.05] {
                for fraction in [0.0, 0.1, 0.5, 0.97] {
                    let time = segment.startTime + segment.length * fraction
                    let position = RhythmEndless.beatPosition(trackTime: time, soundOffset: offset)
                    // Сдвиг двигает бит: при сдвиге -0.05 в тот же момент звучит позиция на 0,05 с дальше.
                    let shifted = segment.length * fraction - offset
                    guard shifted >= 0, shifted < segment.length else { continue }
                    #expect(position.segment == k)
                    #expect(abs(position.seconds - shifted) < 1e-9)
                }
            }
        }
    }

    @Test func beatPositionAtStepBoundary() {
        let segments = RhythmEndless.segments(until: 60)
        let boundary = segments[1].startTime
        let at = RhythmEndless.beatPosition(trackTime: boundary, soundOffset: 0)
        #expect(at.segment == 1 && at.seconds == 0)
        let before = RhythmEndless.beatPosition(trackTime: boundary - 0.01, soundOffset: 0)
        #expect(before.segment == 0)
        #expect(abs(before.seconds - (segments[0].length - 0.01)) < 1e-9)
        // Сдвиг переносит границу: бит раньше на 0,25 с — ступень 1 звучит за 0,25 с до границы нот.
        let early = RhythmEndless.beatPosition(trackTime: boundary - 0.25, soundOffset: -0.25)
        #expect(early.segment == 1 && abs(early.seconds) < 1e-9)
        let late = RhythmEndless.beatPosition(trackTime: boundary + 0.25, soundOffset: 0.25)
        #expect(late.segment == 1 && abs(late.seconds) < 1e-9)
    }

    @Test func beatPositionDuringCountdownLoopsFirstStep() {
        let length = RhythmEndless.segments(until: 3)[0].length   // 24 с при 40 нотах в минуту
        #expect(abs(length - 24) < 1e-9)
        // Первая нота — начало петли, нажатие в отсчёте — хвост петли.
        let start = RhythmEndless.beatPosition(trackTime: RhythmChartBuilder.leadIn, soundOffset: 0)
        #expect(start.segment == 0 && start.seconds == 0)
        let countdown = RhythmEndless.beatPosition(trackTime: 0.5, soundOffset: 0)
        #expect(countdown.segment == 0 && abs(countdown.seconds - (length - 1.5)) < 1e-9)
        let negative = RhythmEndless.beatPosition(trackTime: -1, soundOffset: 0)
        #expect(negative.segment == 0 && abs(negative.seconds - (length - 3)) < 1e-9)
        // Сдвиг в отсчёте: бит раньше на 0,25 с.
        let shifted = RhythmEndless.beatPosition(trackTime: 1, soundOffset: -0.25)
        #expect(shifted.segment == 0 && abs(shifted.seconds - (length - 0.75)) < 1e-9)
    }

    @Test func beatPositionAtCeilingLoopsForever() {
        let segments = RhythmEndless.segments(until: RhythmEndless.trackSeconds)
        let ceiling = segments.first { $0.notesPerMinute == RhythmEndless.ceilingNotesPerMinute }!
        let ceilingIndex = segments.firstIndex(of: ceiling)!
        #expect(ceiling.bpm == 150 && ceiling.beats == 8 && abs(ceiling.length - 3.2) < 1e-9)
        for turns in [0, 1, 7, 300] {
            let time = ceiling.startTime + Double(turns) * ceiling.length + 1.1
            let position = RhythmEndless.beatPosition(trackTime: time, soundOffset: 0)
            #expect(position.segment == ceilingIndex)
            #expect(abs(position.seconds - 1.1) < 1e-6)
            #expect(position.seconds >= 0 && position.seconds < ceiling.length)
        }
        // Сдвиг на потолке: бит раньше на 0,5 с.
        let shifted = RhythmEndless.beatPosition(trackTime: ceiling.startTime + 10 * ceiling.length + 1, soundOffset: -0.5)
        #expect(abs(shifted.seconds - 1.5) < 1e-6)
    }

    @Test func beatPositionStaysInsideLoopForAnyTime() {
        let segments = RhythmEndless.segments(until: 100_000)
        for time in stride(from: -5.0, through: 4000.0, by: 7.31) {
            for offset in [0.0, 0.2, -0.2] {
                let position = RhythmEndless.beatPosition(trackTime: time, soundOffset: offset)
                let length = segments[min(position.segment, segments.count - 1)].length
                #expect(position.seconds >= 0 && position.seconds < length)
            }
        }
    }

    // MARK: - Разбор и итог захода

    /// Бесконечный заход: первые `hits` нот нажаты вовремя, следующая пропущена (`tick` после неё).
    private func playEndless(hits: Int, skipsAfter: Int = 0) -> (RhythmGame, RhythmChart) {
        let chart = endlessChart()
        var game = RhythmGame(chart: chart)
        for note in chart.notes.prefix(hits) { _ = game.press(note.character, at: note.time) }
        if skipsAfter > 0 {
            let last = chart.notes[hits + skipsAfter - 1]
            _ = game.tick(at: last.time + 1)
        }
        return (game, chart)
    }

    @Test func reportSurvivedAndPeakForEndless() {
        // 20 нот сыграны (ступени 0 и 1), потом промахи до конца здоровья.
        let (game, chart) = playEndless(hits: 20, skipsAfter: 20)
        let report = RhythmReport.make(game: game, chart: chart)
        let lastIndex = game.outcomes.keys.max()!
        #expect(game.state == .failed)
        let expectedSurvived = chart.notes[lastIndex].time - chart.notes[0].time
        #expect(abs(report.survivedSeconds! - expectedSurvived) < 1e-9)
        #expect(report.peakNotesPerMinute == RhythmEndless.notesPerMinute(noteIndex: lastIndex))
    }

    @Test func reportPeakIsStepOfLastEvaluatedNote() {
        let (game, chart) = playEndless(hits: 16)       // ноты 0–15: вся ступень 40 нот в минуту
        let first = RhythmReport.make(game: game, chart: chart)
        #expect(first.peakNotesPerMinute == 40)
        #expect(abs(first.survivedSeconds! - 15 * 1.5) < 1e-9)
        let (next, nextChart) = playEndless(hits: 17)   // нота 16 — первая ступени 45
        let second = RhythmReport.make(game: next, chart: nextChart)
        #expect(second.peakNotesPerMinute == 45)
        #expect(abs(second.survivedSeconds! - 16 * 1.5) < 1e-9)
    }

    @Test func reportEndlessWithoutEvaluatedNotes() {
        let chart = endlessChart()
        let report = RhythmReport.make(game: RhythmGame(chart: chart), chart: chart)
        #expect(report.survivedSeconds == 0 && report.peakNotesPerMinute == RhythmEndless.startNotesPerMinute)
    }

    @Test func outcomeCompletedWhenEndlessHealthRunsOut() {
        let (game, chart) = playEndless(hits: 3, skipsAfter: 25)
        #expect(game.state == .failed)
        let result = makeOutcome(game: game, chart: chart)
        #expect(result.completed)
        #expect(!result.cleared)
    }

    @Test func outcomeNotCompletedWhenEndlessLeftEarly() {
        let (game, chart) = playEndless(hits: 5)
        #expect(game.state == .playing)
        let result = makeOutcome(game: game, chart: chart)
        #expect(!result.completed && !result.cleared)
    }

    private func makeOutcome(game: RhythmGame, chart: RhythmChart) -> RhythmOutcome {
        RhythmOutcome.make(
            game: game, chart: chart, source: RhythmNoteSource(mode: .open, letters: Array("фываолдж")), language: .ru,
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60), activeSeconds: 50,
            fingers: fingers)
    }
}
