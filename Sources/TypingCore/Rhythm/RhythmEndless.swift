import Foundation

/// Расписание темпа бесконечного режима: темп в нотах в минуту растёт ступенями, ноты летят всё быстрее,
/// окна оценки сужаются на быстрых ступенях (спека бесконечного режима, §2–§5).
public enum RhythmEndless {
    public static let startNotesPerMinute = 40
    public static let ceilingNotesPerMinute = 300
    /// Нот в ступени.
    public static let stepNotes = 16
    /// Нот заготовлено на столько секунд трека.
    public static let trackSeconds: TimeInterval = 1200

    /// Темп, с которого шаг растёт с +5 до +10.
    private static let fastFrom = 150
    private static let slowSteps = (fastFrom - startNotesPerMinute) / 5
    private static let startScroll = 3.6
    private static let ceilingScroll = 1.6
    /// Ноты чаще чем через столько секунд сужают окна оценки.
    private static let comfortableInterval = 0.4

    /// Темп ступени: 40, 45 … 150, 160 … 300 и дальше 300.
    public static func notesPerMinute(step: Int) -> Int {
        let step = max(0, step)
        if step <= slowSteps { return startNotesPerMinute + 5 * step }
        return min(ceilingNotesPerMinute, fastFrom + 10 * (step - slowSteps))
    }

    /// Темп ступени, в которой стоит нота с номером `noteIndex`.
    public static func notesPerMinute(noteIndex: Int) -> Int {
        notesPerMinute(step: max(0, noteIndex) / stepNotes)
    }

    /// Темп бита: `n` при `n ≤ 150`, иначе `n / 2` (нот на долю 2).
    /// Доля пути темпа от старта до потолка для ноты с номером `noteIndex`: 0 на старте, 1 на потолке.
    public static func tempoProgress(noteIndex: Int) -> Double {
        let span = Double(ceilingNotesPerMinute - startNotesPerMinute)
        return Double(notesPerMinute(noteIndex: noteIndex) - startNotesPerMinute) / span
    }

    public static func beatBPM(notesPerMinute n: Int) -> Int {
        n <= fastFrom ? n : n / 2
    }

    /// Время полёта ноты: 3,6 с при 40 нотах в минуту, 1,6 с при 300, линейно между ними.
    public static func scrollSeconds(notesPerMinute n: Int) -> Double {
        let clamped = min(ceilingNotesPerMinute, max(startNotesPerMinute, n))
        let progress = Double(clamped - startNotesPerMinute) / Double(ceilingNotesPerMinute - startNotesPerMinute)
        return startScroll + (ceilingScroll - startScroll) * progress
    }

    /// Множитель окон оценки: `min(1, (60 / n) / 0,4)`.
    public static func windowScale(notesPerMinute n: Int) -> Double {
        min(1, (60 / Double(max(1, n))) / comfortableInterval)
    }

    // MARK: - Ступени: разбор трека и фаза бита

    /// Ступень трека: с какого времени идёт, темп нот и бита, долей в ней. Целое число тактов 4/4:
    /// 16 долей при плотности 1 (`n ≤ 150`), 8 при плотности 2.
    public struct Segment: Equatable, Sendable {
        public let startTime: TimeInterval
        public let notesPerMinute: Int
        public let bpm: Int
        public let beats: Int

        public init(startTime: TimeInterval, notesPerMinute: Int, bpm: Int, beats: Int) {
            self.startTime = startTime
            self.notesPerMinute = notesPerMinute
            self.bpm = bpm
            self.beats = beats
        }

        /// Длина ступени (она же длина петли бита), секунды.
        public var length: TimeInterval { Double(beats) * 60 / Double(bpm) }
    }

    /// Первая ступень с потолочным темпом: дальше все ступени одинаковы, петля бита крутится по кругу.
    private static let ceilingStep: Int = {
        var step = 0
        while notesPerMinute(step: step) < ceilingNotesPerMinute { step += 1 }
        return step
    }()

    /// Время начала каждой ступени до потолочной включительно. Набирается теми же сложениями, что и время нот
    /// в `RhythmChartBuilder`, поэтому начало ступени `k` равно времени ноты `k · 16` до последнего бита.
    private static let starts: [TimeInterval] = {
        var result = [RhythmChartBuilder.leadIn]
        for step in 0..<ceilingStep { result.append(advance(result[step], step: step)) }
        return result
    }()

    /// Время начала следующей ступени: шаг в одну ноту, `stepNotes` раз.
    private static func advance(_ start: TimeInterval, step: Int) -> TimeInterval {
        let interval = 60 / Double(notesPerMinute(step: step))
        var time = start
        for _ in 0..<stepNotes { time += interval }
        return time
    }

    private static func segment(step: Int, startTime: TimeInterval) -> Segment {
        let n = notesPerMinute(step: step)
        let bpm = beatBPM(notesPerMinute: n)
        return Segment(startTime: startTime, notesPerMinute: n, bpm: bpm, beats: bpm == n ? 16 : 8)
    }

    /// Ступени, начавшиеся раньше `until` (время трека), по порядку: первая — со времени первой ноты.
    /// После потолка ступени одинаковые и идут дальше сколько нужно.
    public static func segments(until: TimeInterval) -> [Segment] {
        var result: [Segment] = []
        var step = 0
        var start = RhythmChartBuilder.leadIn
        while start < until {
            result.append(segment(step: step, startTime: start))
            start = advance(start, step: step)
            step += 1
        }
        return result
    }

    /// Какая ступень звучит во время трека `trackTime` и сколько секунд прошло от её начала. Правило то же, что
    /// у обычных уровней (`RhythmBeatPhase.loopPosition`): позиция — `(trackTime − leadIn − soundOffset)` по модулю
    /// длины петли; `soundOffset` сдвигает бит относительно нот, отрицательный — бит раньше. До первой ноты
    /// (отсчёт) крутится петля первой ступени, на потолке — петля потолочной; позиция в `[0, длина ступени)`.
    public static func beatPosition(trackTime: TimeInterval, soundOffset: TimeInterval)
        -> (segment: Int, seconds: TimeInterval) {
        let time = trackTime - soundOffset
        var step = 0
        while step < ceilingStep, time >= starts[step + 1] { step += 1 }
        let current = segment(step: step, startTime: starts[step])
        // Перед первой нотой и на потолке время отсчитывается по кругу, как у обычной петли.
        let wrapped = (time - current.startTime).truncatingRemainder(dividingBy: current.length)
        let positive = wrapped < 0 ? wrapped + current.length : wrapped
        // Малое отрицательное значение после приведения может дать ровно длину петли: это снова начало.
        return (step, positive >= current.length ? 0 : positive)
    }
}
