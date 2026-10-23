import Testing
@testable import TypingCore

@Test(arguments: SoundEvent.allCases)
func soundsAreShortCleanAndBounded(event: SoundEvent) {
    let samples = SoundSynth.samples(for: event)
    let seconds = Double(samples.count) / SoundSynth.sampleRate
    #expect(seconds > 0.005 && seconds < 1.0, "\(event): \(seconds) с")
    #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
    #expect(samples.map(abs).max()! > 0.1, "\(event) слишком тихий")
    #expect(abs(samples.first!) < 0.01 && abs(samples.last!) < 0.01, "\(event): щелчки на краях")
}

@Test func soundsAreDeterministic() {
    #expect(SoundSynth.samples(for: .keyClick) == SoundSynth.samples(for: .keyClick))
}

@Test func expectedDurations() {
    func ms(_ e: SoundEvent) -> Int { Int((Double(SoundSynth.samples(for: e).count) / SoundSynth.sampleRate * 1000).rounded()) }
    #expect(ms(.keyClick) == 18)
    #expect(ms(.error) == 140)
    #expect(ms(.exerciseDone) == 230)
    #expect(ms(.lessonDone) == 480)
    #expect(ms(.achievement) == 430)
    #expect(ms(.streak) == 320)
}
