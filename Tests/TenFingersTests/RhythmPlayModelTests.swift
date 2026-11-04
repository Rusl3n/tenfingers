import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

private let fingers: [Character: Finger] = ["о": .rightIndex, "л": .rightMiddle, "а": .leftIndex]

private func chart() -> RhythmChart {
    let letters: [Character] = ["о", "л", "а"]
    return RhythmChart(notes: letters.enumerated().map { index, letter in
        RhythmNote(index: index, time: 1 + Double(index), character: letter,
                   lane: RhythmLane.lane(for: letter, fingers: fingers)!, wordIndex: nil)
    }, duration: 30, level: .preset(.easy))
}

/// Модель без звука: бит выключен, часы стартуют в `systemUptime` 1000 (нулевое время трека — 1003).
@MainActor private func makeModel(layout: Language? = nil) -> RhythmPlayModel {
    let run = RhythmRun(language: .ru, mode: .open, level: .easy, style: .pulse)
    let model = RhythmPlayModel(run: run, chart: chart(), fingers: fingers,
                                audio: RhythmAudio(style: .pulse, bpm: 80, enabled: false), soundOffset: 0,
                                layoutLanguage: layout)
    model.start(at: 1000)
    return model
}

@Test func noteOffsetPutsNoteOnTheLineAtItsTimeAndAtTheTopOneScrollEarlier() {
    let line: CGFloat = 400
    #expect(RhythmFieldLayout.noteOffset(noteTime: 5, trackTime: 5, scrollSeconds: 2, hitLineY: line) == 400)
    #expect(RhythmFieldLayout.noteOffset(noteTime: 7, trackTime: 5, scrollSeconds: 2, hitLineY: line) == 0)
    #expect(RhythmFieldLayout.noteOffset(noteTime: 6, trackTime: 5, scrollSeconds: 2, hitLineY: line) == 200)
    #expect(RhythmFieldLayout.noteOffset(noteTime: 4, trackTime: 5, scrollSeconds: 2, hitLineY: line) == 600)
}

@Test func geometryKeepsEightLanesInsideTheField() {
    let geometry = RhythmFieldLayout.geometry(in: CGSize(width: 1200, height: 800))
    #expect(geometry.field.width == RhythmFieldLayout.maxWidth)
    #expect(geometry.laneWidth * 8 == geometry.field.width)
    #expect(geometry.laneRect(7).maxX == geometry.field.maxX)
    #expect(geometry.hitLineY > 0 && geometry.hitLineY < geometry.field.height)
    let narrow = RhythmFieldLayout.geometry(in: CGSize(width: 600, height: 500))
    #expect(narrow.field.width == 568)
}

@MainActor @Test func pressesDuringFirstCountdownAreIgnored() {
    let model = makeModel()
    #expect(model.press("о", at: 1001) == nil)
    #expect(model.game.outcomes.isEmpty && model.game.strays == 0)
    #expect(model.frame(at: 1000).countdown == 3)
    #expect(model.frame(at: 1002.5).countdown == 1)
    #expect(model.frame(at: 1003.5).countdown == nil)
}

@MainActor @Test func pressOnBeatIsPerfectAndFlashesLaneWithLabel() {
    let model = makeModel()
    let event = model.press("о", at: 1004)   // время трека 1: нота «о»
    #expect(event?.judgement == .perfect)
    let frame = model.frame(at: 1004.02)
    #expect(frame.laneFlash[4] > 0 && frame.laneFlash[3] == 0)
    #expect(frame.label?.judgement == .perfect && frame.label?.lane == .finger(4))
    #expect(frame.score == 300 && frame.combo == 1)
    #expect(!frame.notes.contains { $0.index == 0 })   // попавшая нота исчезает
    // Вспышка 0,1 с, подпись 0,4 с.
    #expect(model.frame(at: 1004.2).laneFlash[4] == 0 && model.frame(at: 1004.2).label != nil)
    #expect(model.frame(at: 1004.5).label == nil)
}

@MainActor @Test func wrongKeyIsMissAndSkippedNoteStaysDimmed() {
    let model = makeModel()
    #expect(model.press("а", at: 1004)?.judgement == .miss(.wrongKey(pressed: "а")))
    #expect(model.frame(at: 1004.01).notes.first { $0.index == 0 }?.missed == true)
    let events = model.tick(at: 1005.5)   // нота «л» (время 2) прошла линию
    #expect(events.count == 1 && events[0].judgement == .miss(.skipped))
    #expect(model.frame(at: 1005.5).label?.judgement == .miss(.skipped))
}

@MainActor @Test func resumeStartsRecountAndBlocksPressesUntilTrackReachesPause() {
    let model = makeModel()
    model.pause(at: 1004)   // время трека 1
    #expect(model.isPaused)
    #expect(model.press("о", at: 1005) == nil)
    model.resume(at: 1010)   // время трека −2, на отметке 1 — продолжение
    #expect(model.barrier == 1)
    #expect(model.frame(at: 1010).countdown == 3)
    #expect(model.press("о", at: 1012) == nil)   // время 0: ещё отсчёт
    #expect(model.game.outcomes.isEmpty)
    #expect(model.press("о", at: 1013)?.judgement == .perfect)   // время 1: нота «о»
}

@MainActor @Test func pausedClockStopsFramesAndTicks() {
    let model = makeModel()
    model.pause(at: 1006)   // время трека 3
    #expect(model.frame(at: 1100).trackTime == 3)
    #expect(model.tick(at: 1100).isEmpty && model.game.outcomes.isEmpty)
}

@Test func firstIndexFindsFirstNoteNotBeforeTime() {
    let notes = chart().notes
    #expect(RhythmPlayModel.firstIndex(in: notes, notBefore: 0) == 0)
    #expect(RhythmPlayModel.firstIndex(in: notes, notBefore: 2) == 1)
    #expect(RhythmPlayModel.firstIndex(in: notes, notBefore: 2.01) == 2)
    #expect(RhythmPlayModel.firstIndex(in: notes, notBefore: 9) == 3)
}

@MainActor @Test func keyCharactersAreLowercasedAndServiceKeysDropped() {
    #expect(RhythmPlayView.character(of: "О") == "о")
    #expect(RhythmPlayView.character(of: " ") == " ")
    #expect(RhythmPlayView.character(of: "\r") == nil)
    #expect(RhythmPlayView.character(of: "\u{7F}") == nil)
    #expect(RhythmPlayView.character(of: "\u{F700}") == nil)
    #expect(RhythmPlayView.character(of: "ab") == nil)
    #expect(RhythmPlayView.character(of: nil) == nil)
}

@MainActor @Test func summaryComesFromTheGame() {
    var game = RhythmGame(chart: chart())
    for note in chart().notes { _ = game.press(note.character, at: note.time) }
    let run = RhythmRun(language: .ru, mode: .open, level: .easy, style: .pulse)
    let summary = RhythmSummary.make(game: game, chart: chart(), run: run, previous: .empty)
    #expect(summary.cleared && summary.grade == .s && summary.accuracy == 1 && summary.isNewRecord)
    #expect(summary.score == 900 && summary.maxCombo == 3 && summary.counts["perfect"] == 3)
    // 20 пропусков подряд — здоровье кончилось (нот на одну больше).
    let long = RhythmChart(notes: (0...(RhythmGame.startHealth / RhythmGame.missPenalty)).map {
        RhythmNote(index: $0, time: 1 + Double($0), character: "о", lane: .finger(4), wordIndex: nil)
    }, duration: 30, level: .preset(.easy))
    var failed = RhythmGame(chart: long)
    _ = failed.tick(at: 100)
    let lost = RhythmSummary.make(game: failed, chart: long, run: run, previous: .empty)
    #expect(!lost.cleared && lost.grade == .d && !lost.isNewRecord)
}

@Test func savedChoiceFallsBackToFirstAvailableMode() {
    #expect(RhythmSelection.mode("garbage") == .open && RhythmSelection.level("x") == .easy)
    #expect(RhythmSelection.style("x") == .pulse && RhythmSelection.level("expert") == .expert)
    #expect(RhythmSelection.effectiveMode(saved: .closed, unavailable: [:]) == .closed)
    #expect(RhythmSelection.effectiveMode(saved: .closed, unavailable: [.closed: .tooFewLetters]) == .open)
    #expect(RhythmSelection.effectiveMode(saved: .open, unavailable: [.open: .tooFewLetters, .closed: .tooFewLetters])
            == .problem)
    #expect(RhythmSelection.effectiveMode(saved: .words, unavailable: Dictionary(
        uniqueKeysWithValues: RhythmNoteMode.allCases.map { ($0, RhythmNoteSource.Unavailable.noStats) })) == .words)
}

@Test func rhythmSidebarItemFollowsPractice() {
    #expect(SidebarItem.rhythm.icon == "music.note")
    #expect(SidebarItem.allCases.firstIndex(of: .rhythm) == SidebarItem.allCases.firstIndex(of: .practice)! + 1)
}

@Test func rhythmRunReplacesWithItsOwnAlert() {
    let run = RunKind.rhythm(RhythmRun(language: .en, mode: .words, level: .hard, style: .drive))
    #expect(run.language == .en && run.planSlot == nil)
    #expect(run.sidebarTitle != RunKind.practice(PracticeRun(language: .en, source: .frequentWords)).sidebarTitle)
    #expect(run.replaceAlertTitle.hasPrefix("Игра"))
}

@MainActor @Test func secondPauseInsideRecountKeepsBarrierAtOriginalPausePoint() {
    let model = makeModel()
    model.pause(at: 1006)   // время трека 3
    model.resume(at: 1010)   // повторный отсчёт: время −0 → 3 к 1013
    #expect(model.barrier == 3)
    model.pause(at: 1011)   // время трека 1 — внутри повторного отсчёта
    model.resume(at: 1020)
    #expect(model.barrier == 3)   // не опускается до откатанного времени
    #expect(model.press("о", at: 1022) == nil)   // время трека 1 < 3
    #expect(model.game.outcomes.isEmpty)
}

@MainActor @Test func pauseInsideFirstCountdownLeavesBarrierAtZero() {
    let model = makeModel()
    model.pause(at: 1001)   // время трека −2
    model.resume(at: 1005)
    #expect(model.barrier == 0)
    #expect(model.trackTime(at: 1005) == -3)   // первый отсчёт начинается заново
}

@MainActor @Test func pauseReasonIsKeptAndHidingOnlyReplacesFocusLoss() {
    let model = makeModel()
    #expect(model.pauseReason == nil)
    model.pause(at: 1005, reason: .escape)
    model.markHidden()
    #expect(model.pauseReason == .escape)   // Esc остаётся Esc: меню развернётся и свернётся как у упражнений
    #expect(model.resume(at: 1006) == .escape)
    #expect(model.pauseReason == nil)

    model.pause(at: 1007, reason: .focusLoss)
    #expect(model.pauseReason == .focusLoss)
    model.markHidden()
    #expect(model.pauseReason == .hidden)
    #expect(model.resume(at: 1008) == .hidden)
    #expect(model.resume(at: 1009) == nil)   // паузы нет
}

/// Доли петли бита совпадают с нотами при любом BPM: ноты стоят в `leadIn + k · interval`, а кадр петли
/// считается от времени трека `leadIn`.
@Test(arguments: [(RhythmLevelID.easy, 45), (.hard, 80), (.expert, 100)])
func beatLoopFrameIsMultipleOfBeatAtEveryBeatNote(id: RhythmLevelID, bpm: Int) {
    let level = RhythmLevel.preset(id)
    #expect(level.bpm == bpm)
    let beat = 60 / Double(bpm)
    let loopSeconds = Double(BeatSynth.loop(style: .pulse, bpm: bpm).count) / SoundSynth.sampleRate
    let letters: [Character] = ["о", "л", "а"]
    let source = RhythmNoteSource(mode: .open, letters: letters)
    let chart = RhythmChartBuilder.build(source: source, level: level, fingers: fingers, seed: 1)
    #expect(chart.notes.count > 40)
    for note in chart.notes where note.index % level.notesPerBeat == 0 {
        let frame = RhythmBeatPhase.loopPosition(trackTime: note.time, soundOffset: 0, loopSeconds: loopSeconds)
        #expect(frame >= 0 && frame < loopSeconds)
        let beats = frame / beat
        let nearest = beats.rounded()
        let distance = nearest == 4 ? abs(frame - loopSeconds) : abs(frame - nearest * beat)
        #expect(distance < 0.002, "нота \(note.index) при \(bpm) BPM лежит в \(distance) с от доли")
    }
}

@Test func beatLoopPositionIsWrappedAndShiftedBySoundOffset() {
    let loop = 3.0
    // Опорная точка — время трека leadIn; до неё позиция приводится в [0, длина).
    #expect(RhythmBeatPhase.loopPosition(trackTime: RhythmChartBuilder.leadIn, soundOffset: 0, loopSeconds: loop) == 0)
    let before = RhythmBeatPhase.loopPosition(trackTime: -3, soundOffset: 0, loopSeconds: loop)
    #expect(abs(before - 1) < 1e-9)   // −5 mod 3 = 1
    // Плюс — бит позже: в момент ноты звучит ещё конец предыдущей петли.
    let later = RhythmBeatPhase.loopPosition(trackTime: RhythmChartBuilder.leadIn, soundOffset: 0.2, loopSeconds: loop)
    #expect(abs(later - 2.8) < 1e-9)
    // Минус — бит раньше: в момент ноты петля уже прошла 0,2 с.
    let earlier = RhythmBeatPhase.loopPosition(trackTime: RhythmChartBuilder.leadIn, soundOffset: -0.2, loopSeconds: loop)
    #expect(abs(earlier - 0.2) < 1e-9)
    #expect(RhythmBeatPhase.loopPosition(trackTime: 0, soundOffset: 0, loopSeconds: 0) == 0)
}

/// Направление «Сдвига звука»: при −0,1 с доля петли (кадр 0) звучит на 0,1 с раньше ноты, при +0,1 с — на 0,1 с позже.
@Test func negativeSoundOffsetMakesTheBeatSoundEarlierThanTheNote() {
    let loop = 3.0
    let noteTime = RhythmChartBuilder.leadIn + 5 * loop   // нота стоит на доле
    func position(at trackTime: TimeInterval, offset: TimeInterval) -> TimeInterval {
        RhythmBeatPhase.loopPosition(trackTime: trackTime, soundOffset: offset, loopSeconds: loop)
    }
    // Расстояние до начала петли с учётом перехода через границу (0 и длина петли — одна точка).
    func distanceToLoopStart(_ value: TimeInterval) -> TimeInterval { min(value, loop - value) }
    // Кадр 0 — в момент нотной доли минус 0,1 с (раньше) или плюс 0,1 с (позже).
    #expect(distanceToLoopStart(position(at: noteTime - 0.1, offset: -0.1)) < 1e-9)
    #expect(distanceToLoopStart(position(at: noteTime + 0.1, offset: 0.1)) < 1e-9)
    #expect(distanceToLoopStart(position(at: noteTime, offset: 0)) < 1e-9)
    // В момент ноты при −0,1 с доля уже звучит 0,1 с, при +0,1 с ещё не наступила (конец предыдущей петли).
    #expect(abs(position(at: noteTime, offset: -0.1) - 0.1) < 1e-9)
    #expect(abs(position(at: noteTime, offset: 0.1) - 2.9) < 1e-9)
}

// MARK: - Раскладка не совпадает с языком захода

@MainActor @Test func startWaitsWhileLayoutMismatchesThenCountsDownByItself() {
    let model = makeModel(layout: .en)
    #expect(model.isPaused && model.pauseReason == .layout)
    #expect(model.press("о", at: 1004) == nil)
    #expect(model.game.outcomes.isEmpty && model.game.strays == 0)
    #expect(model.wrongLayoutAttempted)
    #expect(model.applyLayout(.ru, at: 1010) == .resumed)
    #expect(!model.isPaused && model.pauseReason == nil)
    #expect(model.trackTime(at: 1010) == -3)
    #expect(model.frame(at: 1010).countdown == 3)
}

@MainActor @Test func matchingLayoutAtStartCountsDownAtOnce() {
    let model = makeModel(layout: .ru)
    #expect(!model.isPaused)
    #expect(!model.wrongLayoutAttempted)
    #expect(makeModel(layout: nil).isPaused == false)
}

@MainActor @Test func layoutChangeDuringPlayPausesAndReturnResumesWithCountdown() {
    let model = makeModel(layout: .ru)
    #expect(model.applyLayout(.en, at: 1005) == .paused)   // время трека 2
    #expect(model.isPaused && model.pauseReason == .layout)
    #expect(model.applyLayout(.ru, at: 1020) == .resumed)
    #expect(model.trackTime(at: 1020) == -1)
    #expect(model.frame(at: 1020).countdown == 3)
    #expect(model.press("о", at: 1021) == nil)   // барьер: время трека 0 < 2
}

@MainActor @Test func pressInWrongLayoutChangesNothingInTheGame() {
    let model = makeModel(layout: .ru)
    model.layoutLanguage = .en   // раскладка сменилась, пауза ещё не поставлена
    #expect(model.press("о", at: 1004) == nil)
    #expect(model.press("z", at: 1004.2) == nil)
    #expect(model.game.outcomes.isEmpty && model.game.strays == 0 && model.game.score == 0)
    #expect(model.wrongLayoutAttempted)
    model.layoutLanguage = .ru
    #expect(model.press("о", at: 1004)?.judgement == .perfect)
}

@MainActor @Test func resumeIsRefusedWhileLayoutMismatchesAndEscapePauseIsKept() {
    let model = makeModel(layout: .ru)
    model.pause(at: 1005, reason: .escape)
    #expect(model.applyLayout(.en, at: 1006) == .none)
    #expect(model.resume(at: 1007) == nil)
    #expect(model.isPaused && model.pauseReason == .escape)
    #expect(model.applyLayout(.ru, at: 1008) == .none)   // пауза по Esc сама не снимается
    #expect(model.isPaused)
    #expect(model.resume(at: 1009) == .escape)
}

@MainActor @Test func unknownLayoutNeverPauses() {
    let model = makeModel(layout: .ru)
    #expect(model.applyLayout(nil, at: 1005) == .none)
    #expect(!model.isPaused)
}

// MARK: - Бесконечный трек: поле с разным полётом нот

/// Бесконечный трек из трёх нот: первые две летят 3,6 с, третья (на быстрой ступени) — 1,6 с.
private func endlessChart() -> RhythmChart {
    let times: [(Double, Double)] = [(10, 3.6), (11, 3.6), (12, 1.6)]
    return RhythmChart(notes: times.enumerated().map { index, entry in
        RhythmNote(index: index, time: entry.0, character: "о", lane: .finger(4), wordIndex: nil,
                   scrollSeconds: entry.1)
    }, duration: 1200, level: .preset(.endless))
}

@MainActor private func makeEndlessModel() -> RhythmPlayModel {
    let run = RhythmRun(language: .ru, mode: .open, level: .endless, style: .pulse)
    let model = RhythmPlayModel(run: run, chart: endlessChart(), fingers: fingers,
                                audio: RhythmAudio(style: .pulse, bpm: 40, enabled: false, endless: true),
                                soundOffset: 0)
    model.start(at: 1000)   // нулевое время трека — 1003
    return model
}

@MainActor @Test func frameShowsEachNoteByItsOwnScrollAndSelectsWindowByTheLongest() {
    let model = makeEndlessModel()
    // Время трека 7: до ноты 0 осталось 3 с (её полёт 3,6 — видна), до ноты 1 — 4 с (ещё нет), до ноты 2 — 5 с.
    let early = model.frame(at: 1010)
    #expect(early.trackTime == 7 && early.scrollSeconds == 3.6)
    #expect(early.notes.map(\.index) == [0])
    #expect(early.notes[0].scrollSeconds == 3.6)
    // Время 10,5: ноты 0 (на 0,5 с позади, не оценена), 1 (0,5 с до линии) и 2 (1,5 с до линии при полёте 1,6).
    let late = model.frame(at: 1013.5)
    #expect(late.notes.map(\.index) == [0, 1, 2])
    #expect(late.notes.map(\.scrollSeconds) == [3.6, 3.6, 1.6])
    // Нота с коротким полётом не видна раньше своего времени полёта, хотя окно кадра — по самому долгому.
    let beforeShort = model.frame(at: 1013.3)   // время 10,3: до ноты 2 — 1,7 с > 1,6
    #expect(beforeShort.notes.map(\.index) == [0, 1])
}

@Test func noteOffsetUsesTheNotesOwnScroll() {
    let line: CGFloat = 400
    // Одна и та же нота за 1,6 с до линии: при полёте 1,6 с она у верха, при 3,6 с — ниже.
    #expect(RhythmFieldLayout.noteOffset(noteTime: 5, trackTime: 3.4, scrollSeconds: 1.6, hitLineY: line) == 0)
    let slow = RhythmFieldLayout.noteOffset(noteTime: 5, trackTime: 3.4, scrollSeconds: 3.6, hitLineY: line)
    #expect(slow > 200 && slow < 250)
}

@MainActor @Test func ordinaryChartFrameUsesLevelScrollForEveryNote() {
    let model = makeModel()
    let frame = model.frame(at: 1004)
    #expect(frame.scrollSeconds == RhythmLevel.preset(.easy).scrollSeconds)
    #expect(frame.notes.allSatisfy { $0.scrollSeconds == RhythmLevel.preset(.easy).scrollSeconds })
}

// MARK: - Бесконечный трек: расписание бита

@Test func endlessBeatSegmentsRunFromTheFirstStepToTheFirstCeilingStep() {
    let segments = RhythmEndlessBeat.segments
    #expect(segments.first?.notesPerMinute == 40 && segments.first?.bpm == 40)
    #expect(segments.last?.notesPerMinute == 300 && segments.last?.bpm == 150)
    #expect(segments.dropLast().allSatisfy { $0.notesPerMinute < 300 })
    #expect(RhythmEndlessBeat.ceilingIndex == 37)
}

@Test func endlessBeatFramesRoundEachStepOnItsOwn() {
    let rate = SoundSynth.sampleRate
    let first = RhythmEndlessBeat.segments[0]      // 16 долей по 40 BPM: 24 с
    #expect(RhythmEndlessBeat.frames(of: first, sampleRate: rate) == Int((24 * rate).rounded()))
    let ceiling = RhythmEndlessBeat.segments[RhythmEndlessBeat.ceilingIndex]   // 8 долей по 150 BPM: 3,2 с
    #expect(RhythmEndlessBeat.frames(of: ceiling, sampleRate: rate) == Int((3.2 * rate).rounded()))
}

@Test func endlessBeatStartFollowsTheSegmentsAndTheSoundOffset() {
    let rate = SoundSynth.sampleRate
    // До первой ноты (отсчёт): петля первой ступени, как у обычной петли.
    let countdown = RhythmEndlessBeat.start(trackTime: -3, soundOffset: 0, sampleRate: rate)
    #expect(countdown.index == 0 && countdown.frame > 0)
    // Первая нота: начало первой ступени.
    #expect(RhythmEndlessBeat.start(trackTime: RhythmChartBuilder.leadIn, soundOffset: 0, sampleRate: rate)
        == (0, 0))
    // Вторая ступень начинается со времени 16-й ноты (по 1,5 с).
    let second = RhythmChartBuilder.leadIn + 24
    #expect(RhythmEndlessBeat.start(trackTime: second, soundOffset: 0, sampleRate: rate) == (1, 0))
    #expect(RhythmEndlessBeat.start(trackTime: second - 0.001, soundOffset: 0, sampleRate: rate).index == 0)
    // Отрицательный сдвиг звука — бит раньше: в тот же момент трека уже вторая ступень.
    #expect(RhythmEndlessBeat.start(trackTime: second - 0.1, soundOffset: -0.2, sampleRate: rate).index == 1)
    // Далеко за потолком — потолочная ступень, кадр внутри её длины.
    let far = RhythmEndlessBeat.start(trackTime: 1100, soundOffset: 0, sampleRate: rate)
    let ceilingFrames = RhythmEndlessBeat.frames(of: RhythmEndlessBeat.segments[37], sampleRate: rate)
    #expect(far.index == 37 && far.frame >= 0 && far.frame < ceilingFrames)
}

@Test func endlessBeatSamplesRepeatTheLoopAcrossTheStep() {
    let loop: [Float] = [1, 2, 3, 4]
    #expect(RhythmEndlessBeat.samples(loop: loop, range: 0..<4) == [1, 2, 3, 4])
    #expect(RhythmEndlessBeat.samples(loop: loop, range: 0..<10) == [1, 2, 3, 4, 1, 2, 3, 4, 1, 2])
    #expect(RhythmEndlessBeat.samples(loop: loop, range: 6..<9) == [3, 4, 1])
    #expect(RhythmEndlessBeat.samples(loop: [], range: 0..<4).isEmpty)
    #expect(RhythmEndlessBeat.samples(loop: loop, range: 5..<5).isEmpty)
}

@Test func endlessBeatStepBufferIsTheLoopRepeatedByItsBars() {
    let rate = SoundSynth.sampleRate
    // Ступень 40 BPM — 4 такта: её буфер — четыре петли (с точностью до кадра округления).
    let segment = RhythmEndlessBeat.segments[0]
    let loop = BeatSynth.loop(style: .pulse, bpm: segment.bpm, sampleRate: rate)
    let frames = RhythmEndlessBeat.frames(of: segment, sampleRate: rate)
    #expect(abs(frames - 4 * loop.count) <= 4)
    let samples = RhythmEndlessBeat.samples(loop: loop, range: 0..<frames)
    #expect(samples.count == frames && samples[loop.count] == loop[0] && samples[loop.count + 7] == loop[7])
}
