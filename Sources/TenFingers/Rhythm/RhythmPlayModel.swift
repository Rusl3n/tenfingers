import Foundation
import TypingCore

/// Состояние одного захода на экране: игра, часы, бит, вспышки и подписи. Вне SwiftUI, чтобы ввод и кадры
/// работали по одним часам (`systemUptime` и `NSEvent.timestamp` — одна шкала), а оценка не зависела от кадров.
@MainActor
final class RhythmPlayModel {
    let run: RhythmRun
    let chart: RhythmChart
    let fingers: [Character: Finger]
    let startedAt: Date
    private(set) var game: RhythmGame
    private(set) var clock = RhythmClock()
    /// Время трека, раньше которого нажатия не засчитываются: первый отсчёт и повторный отсчёт после паузы.
    private(set) var barrier: TimeInterval = 0
    /// Причина текущей паузы; `nil`, если паузы нет. От неё зависит реакция боковой панели (`SidebarPolicy`).
    private(set) var pauseReason: PauseReason?
    /// Заход записан (или записывать нечего): при уходе с экрана ничего больше не пишется.
    var isRecorded = false
    /// Язык текущей раскладки; `nil` — не определён (тогда несовпадения нет, как у `ExerciseSession`).
    var layoutLanguage: Language?
    /// В заходе была попытка ввода в чужой раскладке: счётчик `wrongLayoutStarts`, как у упражнений.
    private(set) var wrongLayoutAttempted = false

    private let audio: RhythmAudio
    private let soundOffset: TimeInterval
    /// Самое долгое время полёта нот трека: по нему отбираются ноты кадра (у бесконечного трека полёт у нот разный).
    private let longestScroll: Double
    private var laneFlashUntil = [TimeInterval](repeating: 0, count: RhythmFieldLayout.laneCount)
    private var spaceFlashUntil: TimeInterval = 0
    private var label: (judgement: RhythmJudgement, lane: RhythmLane, until: TimeInterval)?

    init(run: RhythmRun, chart: RhythmChart, fingers: [Character: Finger], audio: RhythmAudio,
         soundOffset: TimeInterval, startedAt: Date = .now, layoutLanguage: Language? = nil) {
        self.run = run
        self.chart = chart
        self.fingers = fingers
        self.audio = audio
        self.soundOffset = soundOffset
        self.startedAt = startedAt
        self.layoutLanguage = layoutLanguage
        longestScroll = chart.notes.reduce(chart.level.scrollSeconds) { max($0, chart.scrollSeconds(of: $1)) }
        game = RhythmGame(chart: chart)
    }

    var isPaused: Bool { clock.isPaused }
    var isEnded: Bool { game.state != .playing }

    var layoutMismatch: Bool { Self.mismatch(layoutLanguage, run.language) }

    nonisolated static func mismatch(_ layoutLanguage: Language?, _ language: Language) -> Bool {
        guard let layoutLanguage else { return false }
        return layoutLanguage != language
    }

    /// Что сделала смена раскладки с заходом.
    enum LayoutTransition: Equatable {
        case none, paused, resumed
    }

    /// Раскладка сменилась: чужая ставит паузу `.layout`, возврат снимает только её (с повторным отсчётом 3-2-1);
    /// пауза по Esc, потере фокуса или скрытию остаётся как есть.
    func applyLayout(_ language: Language?, at uptime: TimeInterval) -> LayoutTransition {
        layoutLanguage = language
        if layoutMismatch {
            guard !clock.isPaused, !isEnded else { return .none }
            pause(at: uptime, reason: .layout)
            return .paused
        }
        guard clock.isPaused, pauseReason == .layout else { return .none }
        resume(at: uptime)
        return .resumed
    }

    // MARK: - Часы и бит

    /// Начало захода: отсчёт 3-2-1; бит звучит с отсчёта, его доли совпадают с нотами (опорная точка — `leadIn`).
    /// Раскладка чужая — отсчёт не идёт: заход стоит на паузе `.layout` и стартует сам, когда раскладка совпала.
    func start(at uptime: TimeInterval) {
        clock.start(at: uptime)
        if layoutMismatch {
            clock.pause(at: uptime)
            pauseReason = .layout
            return
        }
        audio.start(trackTime: -clock.countdown, atUptime: uptime, soundOffset: soundOffset)
    }

    func pause(at uptime: TimeInterval, reason: PauseReason = .escape) {
        guard !clock.isPaused, !isEnded else { return }
        clock.pause(at: uptime)
        pauseReason = reason
        audio.pause()
    }

    /// Запуск скрыт другим разделом: пауза из-за потери фокуса становится «скрытой», пауза по Esc остаётся Esc
    /// (как у `ExerciseSession.pauseForHiding`).
    func markHidden() {
        if clock.isPaused, pauseReason == .focusLoss { pauseReason = .hidden }
    }

    /// Продолжение с повторным отсчётом: пока время трека не дойдёт до места паузы, нажатия не засчитываются.
    /// Возвращает причину снятой паузы (`nil` — паузы не было или раскладка чужая: тогда пауза остаётся).
    @discardableResult
    func resume(at uptime: TimeInterval) -> PauseReason? {
        guard clock.isPaused, !isEnded, !layoutMismatch else { return nil }
        // Барьер — самое дальнее время трека, до которого дошёл заход (`highWater` часов): пауза внутри повторного
        // отсчёта не опускает его до откатанного времени, пауза внутри первого отсчёта даёт 0.
        barrier = max(barrier, clock.activeSeconds(at: uptime))
        clock.resume(at: uptime)
        let reason = pauseReason
        pauseReason = nil
        audio.resume(trackTime: clock.trackTime(at: uptime), atUptime: uptime, soundOffset: soundOffset)
        return reason
    }

    /// Кнопка звука на поле: бит без громкости, доли не сбиваются.
    func setMuted(_ muted: Bool) { audio.isMuted = muted }

    /// Конец захода: часы замирают, бит стоит.
    func stop(at uptime: TimeInterval) {
        clock.pause(at: uptime)
        audio.stop()
    }

    func trackTime(at uptime: TimeInterval) -> TimeInterval { clock.trackTime(at: uptime) }

    // MARK: - Ввод и кадры

    /// Нажатие в момент `timestamp` (шкала `systemUptime`). Во время отсчёта и на паузе — `nil` (ничего не было).
    /// В чужой раскладке нажатие не засчитывается вообще (ни нота, ни лишнее, ни статистика) — только отмечается.
    func press(_ character: Character, at timestamp: TimeInterval) -> RhythmEvent? {
        guard !isEnded else { return nil }
        if layoutMismatch {
            wrongLayoutAttempted = true
            return nil
        }
        guard !clock.isPaused else { return nil }
        let time = clock.trackTime(at: timestamp)
        guard time >= barrier else { return nil }
        let event = game.press(character, at: time)
        let pressedLane = RhythmLane.lane(for: character, fingers: fingers)
        if let index = event.noteIndex, let judgement = event.judgement {
            let noteLane = chart.notes[index].lane
            flash(judgement.isHit ? noteLane : (pressedLane ?? noteLane), at: timestamp)
            label = (judgement, noteLane, timestamp + RhythmFieldLayout.labelSeconds)
        } else if let pressedLane {
            flash(pressedLane, at: timestamp)
        }
        return event
    }

    /// Кадр: пропущенные ноты получают «Мимо».
    @discardableResult
    func tick(at uptime: TimeInterval) -> [RhythmEvent] {
        guard !clock.isPaused, !isEnded else { return [] }
        let events = game.tick(at: clock.trackTime(at: uptime))
        if let last = events.last, let index = last.noteIndex, let judgement = last.judgement {
            label = (judgement, chart.notes[index].lane, uptime + RhythmFieldLayout.labelSeconds)
        }
        return events
    }

    private func flash(_ lane: RhythmLane, at uptime: TimeInterval) {
        let until = uptime + RhythmFieldLayout.flashSeconds
        switch lane {
        case .space: spaceFlashUntil = until
        case .finger(let index): laneFlashUntil[index] = until
        }
    }

    // MARK: - Кадр для рисования

    func frame(at uptime: TimeInterval) -> RhythmFieldFrame {
        let time = clock.trackTime(at: uptime)
        var frame = RhythmFieldFrame()
        frame.trackTime = time
        frame.scrollSeconds = longestScroll
        // Окно отбора — по самому долгому полёту; сама нота показывается, когда до неё остался её полёт.
        let upper = time + longestScroll + 0.1
        var index = Self.firstIndex(in: chart.notes, notBefore: time - 0.7)
        while index < chart.notes.count, chart.notes[index].time <= upper {
            let note = chart.notes[index]
            let scroll = chart.scrollSeconds(of: note)
            let outcome = game.outcomes[index]
            if note.time <= time + scroll + 0.1, outcome == nil || outcome?.isHit == false {
                frame.notes.append(.init(index: index, time: note.time, scrollSeconds: scroll,
                                         character: note.character, lane: note.lane, missed: outcome != nil))
            }
            index += 1
        }
        for lane in 0..<laneFlashUntil.count {
            frame.laneFlash[lane] = Self.intensity(until: laneFlashUntil[lane], now: uptime,
                                                    span: RhythmFieldLayout.flashSeconds)
        }
        frame.spaceFlash = Self.intensity(until: spaceFlashUntil, now: uptime, span: RhythmFieldLayout.flashSeconds)
        if let label, label.until > uptime {
            frame.label = .init(judgement: label.judgement, lane: label.lane,
                                age: 1 - (label.until - uptime) / RhythmFieldLayout.labelSeconds)
        }
        if time < barrier { frame.countdown = Int(ceil(barrier - time)) }
        frame.score = game.score
        frame.combo = game.combo
        frame.multiplier = game.multiplier
        frame.health = max(0, game.health)
        if chart.level.id == .endless {
            // У бесконечного трека конца не видно: полоса показывает путь темпа от старта до потолка.
            let index = Self.firstIndex(in: chart.notes, notBefore: time)
            frame.progress = RhythmEndless.tempoProgress(noteIndex: index)
        } else {
            let last = chart.notes.last?.time ?? chart.duration
            frame.progress = last > 0 ? min(1, max(0, time / last)) : 0
        }
        return frame
    }

    private static func intensity(until: TimeInterval, now: TimeInterval, span: TimeInterval) -> Double {
        until > now ? min(1, (until - now) / span) : 0
    }

    /// Первая нота со временем не раньше `time` (ноты идут по возрастанию времени).
    nonisolated static func firstIndex(in notes: [RhythmNote], notBefore time: TimeInterval) -> Int {
        var low = 0, high = notes.count
        while low < high {
            let middle = (low + high) / 2
            if notes[middle].time < time { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
