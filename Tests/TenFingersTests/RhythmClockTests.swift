import Foundation
import Testing
@testable import TenFingers

@Test func clockCountsDownBeforeTrackStarts() {
    var clock = RhythmClock()
    clock.start(at: 100)
    #expect(clock.trackTime(at: 100) == -3)
    #expect(clock.trackTime(at: 101.5) == -1.5)
    #expect(clock.trackTime(at: 103) == 0)
}

@Test func clockRunsOneToOneAfterCountdown() {
    var clock = RhythmClock()
    clock.start(at: 100)
    #expect(clock.trackTime(at: 110) == 7)
    #expect(!clock.isPaused)
}

@Test func pauseFreezesTrackTime() {
    var clock = RhythmClock()
    clock.start(at: 100)
    clock.pause(at: 110)
    #expect(clock.isPaused)
    #expect(clock.trackTime(at: 110) == 7)
    #expect(clock.trackTime(at: 500) == 7)
}

@Test func resumeAddsCountdownAndContinuesFromFrozenValue() {
    var clock = RhythmClock()
    clock.start(at: 100)
    clock.pause(at: 110)
    clock.resume(at: 200)
    #expect(!clock.isPaused)
    #expect(clock.trackTime(at: 200) == 4)
    #expect(clock.trackTime(at: 203) == 7)
    #expect(clock.trackTime(at: 205) == 9)
}

@Test func pauseDuringCountdownRestartsCountdownOnResume() {
    var clock = RhythmClock()
    clock.start(at: 100)
    clock.pause(at: 101)
    #expect(clock.trackTime(at: 150) == -2)
    clock.resume(at: 150)
    #expect(clock.trackTime(at: 150) == -3)
    #expect(clock.trackTime(at: 153) == 0)
}

@Test func activeSecondsExcludeCountdownsAndPauses() {
    var clock = RhythmClock()
    #expect(clock.activeSeconds(at: 0) == 0)
    clock.start(at: 100)
    #expect(clock.activeSeconds(at: 102) == 0)
    #expect(clock.activeSeconds(at: 110) == 7)
    clock.pause(at: 110)
    #expect(clock.activeSeconds(at: 300) == 7)
    clock.resume(at: 300)
    #expect(clock.activeSeconds(at: 302) == 7)      // повторный отсчёт
    #expect(clock.activeSeconds(at: 305) == 9)
}

@Test func repeatedPauseAndResumeWithoutPairAreIgnored() {
    var clock = RhythmClock()
    clock.start(at: 100)
    clock.resume(at: 105)                            // без паузы — без эффекта
    #expect(clock.trackTime(at: 110) == 7)
    clock.pause(at: 110)
    clock.pause(at: 150)                             // вторая пауза не двигает кадр заморозки
    #expect(clock.trackTime(at: 160) == 7)
    clock.resume(at: 200)
    clock.resume(at: 201)
    #expect(clock.trackTime(at: 203) == 7)
}
