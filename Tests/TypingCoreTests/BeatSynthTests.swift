import Foundation
import Testing
@testable import TypingCore

@Suite struct BeatSynthTests {
    @Test func lengthIsOneBar() {
        for style in RhythmBeatStyle.allCases {
            for bpm in [70, 140] {
                let expected = Int((4 * 60.0 / Double(bpm) * SoundSynth.sampleRate).rounded())
                #expect(BeatSynth.loop(style: style, bpm: bpm).count == expected)
            }
        }
    }

    @Test func samplesAreBoundedAndNotSilent() {
        for style in RhythmBeatStyle.allCases {
            let loop = BeatSynth.loop(style: style, bpm: 100)
            #expect(loop.allSatisfy { $0 >= -1 && $0 <= 1 })
            #expect(loop.contains { abs($0) > 0.1 })
        }
    }

    @Test func stylesDiffer() {
        let loops = RhythmBeatStyle.allCases.map { BeatSynth.loop(style: $0, bpm: 100) }
        #expect(loops[0] != loops[1])
        #expect(loops[1] != loops[2])
        #expect(loops[0] != loops[2])
    }

    @Test func deterministic() {
        for style in RhythmBeatStyle.allCases {
            #expect(BeatSynth.loop(style: style, bpm: 90) == BeatSynth.loop(style: style, bpm: 90))
        }
    }
}
