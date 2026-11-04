import AVFoundation
import TypingCore

/// Фаза петли бита. Ноты стоят в `leadIn + k · interval`, поэтому опорная точка петли — время трека `leadIn`:
/// там звучит начало петли (кадр 0), и доли совпадают с нотами при любом BPM.
enum RhythmBeatPhase {
    /// Позиция петли (секунды, в `[0, loopSeconds)`) во время трека `trackTime`; `soundOffset` сдвигает бит
    /// относительно нот (на оценку не влияет): отрицательный — бит раньше (доля звучит при `нота + soundOffset`),
    /// положительный — позже.
    static func loopPosition(trackTime: TimeInterval, soundOffset: TimeInterval, loopSeconds: TimeInterval,
                             leadIn: TimeInterval = RhythmChartBuilder.leadIn) -> TimeInterval {
        guard loopSeconds > 0 else { return 0 }
        let wrapped = (trackTime - leadIn - soundOffset).truncatingRemainder(dividingBy: loopSeconds)
        let positive = wrapped < 0 ? wrapped + loopSeconds : wrapped
        // Малое отрицательное значение после приведения может дать ровно длину петли: это снова начало.
        return positive >= loopSeconds ? 0 : positive
    }
}

/// Расписание бита бесконечного трека: ступени подряд, на потолке — петля без конца. Чистые вычисления без звука.
/// Ступень — целое число тактов; её звук — петля бита `BeatSynth.loop`, повторённая на всю ступень.
enum RhythmEndlessBeat {
    /// Сколько буферов держится в очереди плеера: проигравшийся буфер возвращает слот, и очередь пополняется.
    /// Четыре ступени — не меньше девяти секунд запаса даже на потолке (ступень 3,2 с).
    static let queueDepth = 4

    /// Ступени от первой до первой потолочной включительно: индекс ступени — её номер, как у `beatPosition`.
    static let segments: [RhythmEndless.Segment] = {
        let all = RhythmEndless.segments(until: RhythmEndless.trackSeconds)
        let ceiling = all.firstIndex { $0.notesPerMinute == RhythmEndless.ceilingNotesPerMinute } ?? all.count - 1
        return Array(all[...ceiling])
    }()

    static var ceilingIndex: Int { segments.count - 1 }

    /// Кадров в ступени: длина ступени в секундах, округлённая до кадра (ошибка не копится — каждая ступень
    /// округляется сама, не от суммы).
    static func frames(of segment: RhythmEndless.Segment, sampleRate: Double) -> Int {
        max(1, Int((segment.length * sampleRate).rounded()))
    }

    /// Ступень и кадр в ней, с которых звучит бит во время трека `trackTime` (правило — `beatPosition`).
    static func start(trackTime: TimeInterval, soundOffset: TimeInterval, sampleRate: Double)
        -> (index: Int, frame: Int) {
        let position = RhythmEndless.beatPosition(trackTime: trackTime, soundOffset: soundOffset)
        let index = min(max(0, position.segment), ceilingIndex)
        let frames = frames(of: segments[index], sampleRate: sampleRate)
        return (index, min(frames - 1, max(0, Int((position.seconds * sampleRate).rounded()))))
    }

    /// Кадры `range` ступени: петля повторяется по кругу (кадр `i` ступени — `loop[i % loop.count]`).
    static func samples(loop: [Float], range: Range<Int>) -> [Float] {
        guard !loop.isEmpty, !range.isEmpty else { return [] }
        var result: [Float] = []
        result.reserveCapacity(range.count)
        var frame = range.lowerBound
        while frame < range.upperBound {
            let offset = frame % loop.count
            let count = min(loop.count - offset, range.upperBound - frame)
            result.append(contentsOf: loop[offset..<(offset + count)])
            frame += count
        }
        return result
    }
}

/// Бит ритм-игры: своя петля в своём `AVAudioEngine`, расписание по host-time (одна шкала с `ProcessInfo.systemUptime`).
/// Ошибки запуска движка глотаются: игра идёт без звука, без алерта.
///
/// Бесконечный трек (`endless`): вместо одной петли — ступени подряд (`RhythmEndlessBeat`). Буфер ступени собирается
/// из петли её темпа (петли по темпу кешируются) и ставится в очередь плеера; в очереди `queueDepth` буферов, не
/// все ступени сразу. Очередь пополняется по `completionHandler` (`.dataPlayedBack`) проигравшегося буфера; обработчик
/// приходит с потока звука и перескакивает на главный актор, а «поколение» (растёт при каждом запуске, паузе и
/// остановке) отсекает обработчики, которые `node.stop()` вызывает для снятых буферов. Потолочная ступень ставится
/// один раз с `.loops` — после неё пополнять нечего.
@MainActor
final class RhythmAudio {
    private static let volume: Float = 0.5
    /// Запас, с которым петля ставится «в будущее», чтобы время расписания не оказалось уже прошедшим.
    private static let lead: TimeInterval = 0.05

    private let enabled: Bool
    private let samples: [Float]
    private let loopSeconds: TimeInterval
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private var loopBuffer: AVAudioPCMBuffer?
    private var isPrepared = false

    // Бесконечный трек.
    private let endless: Bool
    private let style: RhythmBeatStyle
    /// Петли бита по темпу бита: ступеней много, а разных темпов не больше двух десятков.
    private var endlessLoops: [Int: [Float]] = [:]
    /// Растёт при каждом запуске, паузе и остановке: обработчик чужого поколения ничего не делает.
    private var generation = 0
    /// Буферов в очереди плеера (без бесконечной петли потолка).
    private var queued = 0
    /// Следующая ступень к постановке и кадр, с которого она ставится (больше нуля — только у первой, после запуска
    /// или продолжения).
    private var nextIndex = 0
    private var nextFrame = 0
    /// Потолочная ступень уже стоит в очереди с `.loops`.
    private var ceilingQueued = false

    /// Звук игры выключен кнопкой на поле: петля идёт дальше без громкости, поэтому включение не сбивает доли.
    var isMuted = false {
        didSet { if isPrepared { node.volume = isMuted ? 0 : Self.volume } }
    }

    /// - Parameters:
    ///   - enabled: `false`, когда все звуки приложения выключены — тогда ничего не играет.
    ///   - endless: бесконечный трек — ступени подряд, `bpm` не используется (темп берётся по ступеням).
    init(style: RhythmBeatStyle, bpm: Int, enabled: Bool, endless: Bool = false) {
        self.enabled = enabled
        self.endless = endless
        self.style = style
        let sampleRate = SoundSynth.sampleRate
        samples = enabled && !endless ? BeatSynth.loop(style: style, bpm: bpm, sampleRate: sampleRate) : []
        loopSeconds = Double(samples.count) / sampleRate
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    }

    /// Начало захода: в `uptime` время трека равно `trackTime` (−отсчёт); бит звучит и на отсчёте, и до первой ноты,
    /// а его доли совпадают с нотами (`RhythmBeatPhase`).
    func start(trackTime: TimeInterval, atUptime uptime: TimeInterval, soundOffset: TimeInterval) {
        schedule(trackTime: trackTime, atUptime: uptime, soundOffset: soundOffset)
    }

    func pause() {
        guard isPrepared else { return }
        generation &+= 1
        node.stop()
        engine.pause()
    }

    /// Петля ставится с кадра `(trackTime − leadIn − soundOffset) mod длина` на host-time `atUptime`.
    func resume(trackTime: TimeInterval, atUptime: TimeInterval, soundOffset: TimeInterval) {
        schedule(trackTime: trackTime, atUptime: atUptime, soundOffset: soundOffset)
    }

    func stop() {
        guard isPrepared else { return }
        generation &+= 1
        node.stop()
        engine.stop()
    }

    // MARK: - Внутреннее

    /// Ставит петлю так, чтобы позиция, отвечающая времени трека `trackTime`, прозвучала в `atUptime`.
    private func schedule(trackTime: TimeInterval, atUptime: TimeInterval, soundOffset: TimeInterval) {
        if endless {
            scheduleEndless(trackTime: trackTime, atUptime: atUptime, soundOffset: soundOffset)
            return
        }
        guard enabled, !samples.isEmpty, loopSeconds > 0, prepareIfNeeded(), let loopBuffer else { return }
        guard startEngine() else { return }
        node.stop()

        // Если время уже прошло (или слишком близко), сдвигаем начало вперёд вместе с позицией в петле.
        var shiftedTrackTime = trackTime
        var uptime = atUptime
        let earliest = ProcessInfo.processInfo.systemUptime + Self.lead
        if uptime < earliest {
            shiftedTrackTime += earliest - uptime
            uptime = earliest
        }
        let positive = RhythmBeatPhase.loopPosition(trackTime: shiftedTrackTime, soundOffset: soundOffset,
                                                    loopSeconds: loopSeconds)
        let startFrame = min(samples.count - 1, max(0, Int((positive * SoundSynth.sampleRate).rounded())))

        // Хвост петли с нужного кадра один раз, затем вся петля по кругу.
        if startFrame > 0, let tail = makeBuffer(Array(samples[startFrame...])) {
            node.scheduleBuffer(tail, at: nil)
        }
        node.scheduleBuffer(loopBuffer, at: nil, options: .loops)
        node.volume = isMuted ? 0 : Self.volume
        node.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: uptime)))
    }

    private func prepareIfNeeded() -> Bool {
        if isPrepared { return true }
        guard let format, let buffer = makeBuffer(samples) else { return false }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        loopBuffer = buffer
        isPrepared = true
        return true
    }

    // MARK: - Бесконечный трек

    /// Ставит бит так, чтобы позиция, отвечающая времени трека `trackTime`, прозвучала в `atUptime`: хвост текущей
    /// ступени с нужного кадра, затем следующие ступени (всего `queueDepth` буферов), на потолке — петля.
    private func scheduleEndless(trackTime: TimeInterval, atUptime: TimeInterval, soundOffset: TimeInterval) {
        guard enabled, attachIfNeeded(), startEngine() else { return }
        generation &+= 1
        node.stop()

        // Петли нужных темпов синтезируются до чтения времени (синтез — самая долгая часть); после чтения времени
        // остаётся только копирование в буферы, оно укладывается в запас `lead`.
        let first = RhythmEndlessBeat.start(trackTime: trackTime, soundOffset: soundOffset,
                                            sampleRate: SoundSynth.sampleRate).index
        let last = min(RhythmEndlessBeat.ceilingIndex, first + RhythmEndlessBeat.queueDepth)
        for index in first...last { _ = endlessLoop(bpm: RhythmEndlessBeat.segments[index].bpm) }

        // Если время уже прошло (или слишком близко), сдвигаем начало вперёд вместе с позицией в треке.
        var shiftedTrackTime = trackTime
        var uptime = atUptime
        let earliest = ProcessInfo.processInfo.systemUptime + Self.lead
        if uptime < earliest {
            shiftedTrackTime += earliest - uptime
            uptime = earliest
        }
        let start = RhythmEndlessBeat.start(trackTime: shiftedTrackTime, soundOffset: soundOffset,
                                            sampleRate: SoundSynth.sampleRate)
        queued = 0
        ceilingQueued = false
        nextIndex = start.index
        nextFrame = start.frame
        fillQueue()
        node.volume = isMuted ? 0 : Self.volume
        node.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: uptime)))
    }

    private func attachIfNeeded() -> Bool {
        if isPrepared { return true }
        guard let format else { return false }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        isPrepared = true
        return true
    }

    /// Пополняет очередь до `queueDepth` буферов; потолочная ступень ставится с `.loops` и на этом всё.
    private func fillQueue() {
        while !ceilingQueued, queued < RhythmEndlessBeat.queueDepth {
            let index = nextIndex
            let segment = RhythmEndlessBeat.segments[index]
            let frames = RhythmEndlessBeat.frames(of: segment, sampleRate: SoundSynth.sampleRate)
            let from = min(nextFrame, frames - 1)
            nextFrame = 0
            let loop = endlessLoop(bpm: segment.bpm)
            if index == RhythmEndlessBeat.ceilingIndex {
                if from > 0, let tail = makeBuffer(RhythmEndlessBeat.samples(loop: loop, range: from..<frames)) {
                    enqueue(tail)
                }
                if let whole = makeBuffer(RhythmEndlessBeat.samples(loop: loop, range: 0..<frames)) {
                    node.scheduleBuffer(whole, at: nil, options: .loops)
                }
                ceilingQueued = true
            } else {
                guard let buffer = makeBuffer(RhythmEndlessBeat.samples(loop: loop, range: from..<frames)) else {
                    return   // нет памяти под буфер: без звука дальше, игра идёт
                }
                enqueue(buffer)
                nextIndex += 1
            }
        }
    }

    /// Ставит буфер в очередь; когда он доиграл, слот возвращается и очередь пополняется.
    private func enqueue(_ buffer: AVAudioPCMBuffer) {
        queued += 1
        let token = generation
        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.bufferFinished(generation: token) }
        }
    }

    private func bufferFinished(generation token: Int) {
        guard token == generation else { return }
        queued = max(0, queued - 1)
        fillQueue()
    }

    private func endlessLoop(bpm: Int) -> [Float] {
        if let loop = endlessLoops[bpm] { return loop }
        let loop = BeatSynth.loop(style: style, bpm: bpm, sampleRate: SoundSynth.sampleRate)
        endlessLoops[bpm] = loop
        return loop
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func makeBuffer(_ data: [Float]) -> AVAudioPCMBuffer? {
        guard let format, !data.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        data.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: data.count) }
        buffer.frameLength = AVAudioFrameCount(data.count)
        return buffer
    }
}
