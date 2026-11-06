import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

private let snapshot = LayoutSnapshot(id: "t", language: .ru, shape: .ansi,
                                      plain: [3: "f", 38: "j", 49: " ", 0: "a"], shifted: [3: "F"])
private let frames = HandsOverlayModel.keyFrames(shape: .ansi)
private let layout = HandsOverlayModel.layout(shape: .ansi)

private func key(_ typed: Character, _ ms: UInt32) -> ReplayKey { ReplayKey(position: 0, typed: typed, offsetMs: ms) }

@Test func replayPressesMapCharactersAndAlternateThumbs() {
    let presses = MeasureReplayModel.presses(keys: [key("f", 0), key(" ", 10), key("j", 20), key(" ", 30), key("я", 40), key("F", 50)],
                                             snapshot: snapshot)
    #expect(presses[0]?.keyCode == 3)
    #expect(presses[1]?.keyCode == 49 && presses[1]?.spaceHalf == .right)  // после левой буквы жмёт правый
    #expect(presses[3]?.spaceHalf == .left)  // после правой буквы — левый
    #expect(presses[4] == nil)
    #expect(presses[5]?.shift == true)
}

@Test func twoFingersMoveAtOnceAndSameFingerIsReplaced() {
    let f = HandsPress(keyCode: 3), j = HandsPress(keyCode: 38)
    let tips = HandsOverlayModel.tips(layout: layout, frames: frames, active: [
        ActiveHandsPress(press: f, elapsedMs: 50, durationMs: 100),
        ActiveHandsPress(press: j, elapsedMs: 30, durationMs: 100),
    ], moves: true)
    #expect(tips.first { $0.id == Finger.leftIndex.rawValue }!.isDown)
    #expect(tips.first { $0.id == Finger.rightIndex.rawValue }!.isDown)
    // у левого указательного сначала f (вниз), потом g (старт): побеждает позднее нажатие
    let g = HandsPress(keyCode: 5)
    let replaced = HandsOverlayModel.tips(layout: layout, frames: frames, active: [
        ActiveHandsPress(press: f, elapsedMs: 50, durationMs: 100),
        ActiveHandsPress(press: g, elapsedMs: 0, durationMs: 100),
    ], moves: true)
    let finger = replaced.first { $0.id == Finger.leftIndex.rawValue }!
    #expect(!finger.isDown)
}

@Test func singlePressWrapperMatchesActiveForm() {
    let press = HandsPress(keyCode: 38)
    for ms in [0.0, 100, 250, 400, 600] {
        let a = HandsOverlayModel.tips(layout: layout, frames: frames, press: press, elapsedMs: ms, moves: true)
        let b = HandsOverlayModel.tips(layout: layout, frames: frames,
                                       active: [ActiveHandsPress(press: press, elapsedMs: ms)], moves: true)
        #expect(a == b)
    }
}

@Test func stillModeKeepsTipsHomeButHighlightsKeys() {
    let active = [ActiveHandsPress(press: HandsPress(keyCode: 38), elapsedMs: 50, durationMs: 100)]
    let tips = HandsOverlayModel.tips(layout: layout, frames: frames, active: active, moves: false)
    #expect(tips.first { $0.id == Finger.rightIndex.rawValue }!.point == layout.home(.rightIndex))
    #expect(HandsOverlayModel.pressedKeys(active: active) == [38])
}

@Test func sequenceFreezesAtMoment() {
    let playback = ReplayPlayback(text: "f", keys: [ReplayKey(position: 0, typed: "f", offsetMs: 0)])
    var sequence = HandsSequence(id: UUID(), playback: playback, presses: [HandsPress(keyCode: 3)], startedAt: Date(timeIntervalSince1970: 0))
    #expect(sequence.isRunning)
    #expect(sequence.elapsedMs(now: Date(timeIntervalSince1970: 2)) == 2000)
    sequence.frozenAtMs = 100
    #expect(!sequence.isRunning && sequence.elapsedMs(now: .now) == 100)
    #expect(sequence.active(atMs: 100).count == 1)
    #expect(sequence.active(atMs: 600).isEmpty)
}

@Test func replayTitlesAndIcons() {
    #expect(ReplayTempo.allCases.map(MeasureReplayModel.title) == ["Как было", "×1,5", "×2", "×3", "Мастер"])
    for name in ["play.fill", "pause.fill", "backward.end.fill", "play.slash"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }
}
