import Foundation
import Testing
@testable import TenFingers

private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

@Test func engineStartIsAllowedUntilItFails() {
    var policy = SoundEnginePolicy()
    #expect(policy.canStart(at: t0))
    policy.startFailed(at: t0)
    #expect(!policy.canStart(at: t0.addingTimeInterval(4.9)))
    #expect(policy.canStart(at: t0.addingTimeInterval(5)))
}

@Test func successfulStartClearsFailure() {
    var policy = SoundEnginePolicy()
    policy.startFailed(at: t0)
    policy.startSucceeded()
    #expect(policy.canStart(at: t0.addingTimeInterval(1)))
}

@Test func engineStopsOnlyAfterFifteenSecondsOfSilence() {
    var policy = SoundEnginePolicy()
    #expect(policy.idleDelay(at: t0) == nil)  // не было активности: ждать нечего
    policy.noteActivity(at: t0)
    #expect(policy.idleDelay(at: t0) == 15)
    #expect(policy.idleDelay(at: t0.addingTimeInterval(10)) == 5)
    #expect(policy.idleDelay(at: t0.addingTimeInterval(15)) == 0)
    // Новый звук сдвигает срок.
    policy.noteActivity(at: t0.addingTimeInterval(14))
    #expect(policy.idleDelay(at: t0.addingTimeInterval(15)) == 14)
}

@Test func stoppingForgetsActivity() {
    var policy = SoundEnginePolicy()
    policy.noteActivity(at: t0)
    policy.engineStopped()
    #expect(policy.idleDelay(at: t0.addingTimeInterval(100)) == nil)
}
