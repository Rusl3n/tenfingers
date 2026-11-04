import Foundation
import Testing
@testable import TypingCore

@Suite struct RhythmJudgeTests {
    @Test func windowsInBothDirections() {
        for sign in [1.0, -1.0] {
            let late: RhythmJudgement = sign > 0 ? .late : .early
            #expect(RhythmJudge.timing(offset: sign * 0.070) == .perfect)
            #expect(RhythmJudge.timing(offset: sign * 0.071) == .good)
            #expect(RhythmJudge.timing(offset: sign * 0.130) == .good)
            #expect(RhythmJudge.timing(offset: sign * 0.131) == late)
            #expect(RhythmJudge.timing(offset: sign * 0.200) == late)
            #expect(RhythmJudge.timing(offset: sign * 0.201) == nil)
        }
        #expect(RhythmJudge.timing(offset: 0) == .perfect)
    }

    @Test func scaledWindows() {
        for sign in [1.0, -1.0] {
            let late: RhythmJudgement = sign > 0 ? .late : .early
            #expect(RhythmJudge.timing(offset: sign * 0.035, scale: 0.5) == .perfect)
            #expect(RhythmJudge.timing(offset: sign * 0.036, scale: 0.5) == .good)
            #expect(RhythmJudge.timing(offset: sign * 0.065, scale: 0.5) == .good)
            #expect(RhythmJudge.timing(offset: sign * 0.066, scale: 0.5) == late)
            #expect(RhythmJudge.timing(offset: sign * 0.100, scale: 0.5) == late)
            #expect(RhythmJudge.timing(offset: sign * 0.101, scale: 0.5) == nil)
        }
        #expect(RhythmJudge.timing(offset: 0.2, scale: 1) == RhythmJudge.timing(offset: 0.2))
    }

    @Test func boundariesSurviveDoubleError() {
        #expect(RhythmJudge.timing(offset: 10.070 - 10.0) == .perfect)
        #expect(RhythmJudge.timing(offset: 10.200 - 10.0) == .late)
        #expect(RhythmJudge.timing(offset: 10.0 - 10.200) == .early)
    }

    @Test func pointsAndHits() {
        #expect(RhythmJudgement.perfect.points == 300)
        #expect(RhythmJudgement.good.points == 200)
        #expect(RhythmJudgement.early.points == 100)
        #expect(RhythmJudgement.late.points == 100)
        #expect(RhythmJudgement.miss(.skipped).points == 0)
        #expect(RhythmJudgement.late.isHit)
        #expect(!RhythmJudgement.miss(.wrongKey(pressed: "x")).isHit)
    }
}
