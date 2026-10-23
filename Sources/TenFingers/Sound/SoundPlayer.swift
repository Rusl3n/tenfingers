import AVFoundation
import Observation
import TypingCore

/// Проигрывает синтезированные звуки через `AVAudioEngine`. Буферы и движок можно подготовить заранее через `prewarm()`; иначе всё готовится при первом `play`.
/// `@Observable` нужен только для передачи через `environment`; наблюдаемых свойств нет.
@MainActor @Observable
final class SoundPlayer {
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var nodes: [SoundEvent: AVAudioPlayerNode] = [:]
    @ObservationIgnored private var buffers: [SoundEvent: AVAudioPCMBuffer] = [:]
    @ObservationIgnored private var isPrepared = false
    @ObservationIgnored private var policy = SoundEnginePolicy()
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    /// Готовит буферы и запускает движок, чтобы первое нажатие не вызывало задержку.
    /// Если все звуки выключены, ничего не делает.
    func prewarm() {
        guard SoundSettings.activeEvents.contains(where: { SoundSettings.isEnabled($0) }) else { return }
        prepareIfNeeded()
        if startEngineIfNeeded() { noteActivity() }
    }

    func play(_ event: SoundEvent) {
        guard SoundSettings.isEnabled(event) else { return }
        prepareIfNeeded()
        guard let node = nodes[event], let buffer = buffers[event] else { return }
        guard startEngineIfNeeded() else { return }
        node.volume = Float(SoundSettings.volume(event))
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
        noteActivity()
    }

    /// Останавливает движок: работающий движок не даёт Mac уйти в сон по бездействию.
    func stop() {
        idleTask?.cancel()
        idleTask = nil
        guard engine.isRunning else { return }
        for node in nodes.values { node.stop() }
        engine.stop()
        policy.engineStopped()
    }

    /// Возвращает `true`, если движок работает. После ошибки запуска следующая попытка не раньше чем через 5 секунд.
    @discardableResult
    private func startEngineIfNeeded() -> Bool {
        if engine.isRunning { return true }
        guard policy.canStart(at: .now) else { return false }
        do {
            try engine.start()
            policy.startSucceeded()
            return true
        } catch {
            policy.startFailed(at: .now)
            return false
        }
    }

    /// Каждый звук сдвигает срок остановки: движок гаснет через 15 секунд тишины.
    private func noteActivity() {
        policy.noteActivity(at: .now)
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while let delay = self?.policy.idleDelay(at: .now) {
                if delay <= 0 {
                    self?.stop()
                    return
                }
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
        }
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: SoundSynth.sampleRate,
                                         channels: 1, interleaved: false) else { return }
        for event in SoundEvent.allCases {
            let samples = SoundSynth.samples(for: event)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { continue }
            for (index, sample) in samples.enumerated() { channel[index] = sample }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes[event] = node
            buffers[event] = buffer
        }
        isPrepared = true
    }
}
