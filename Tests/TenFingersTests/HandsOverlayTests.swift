import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

private let frames = HandsOverlayModel.keyFrames(shape: .ansi)
private let layout = HandsOverlayModel.layout(shape: .ansi)

@Test func keyCentersFollowKeyboardViewMetrics() {
    // ряд 0: первая клавиша ширины 1 — центр на unit/2; ряд 2, клавиша F (код 3)
    let u = KeyboardSizing.baseUnit, s = KeyboardSizing.keySpacing
    let row2 = KeyboardGeometry.rows(for: .ansi)[2]
    let index = row2.firstIndex { $0.keyCode == 3 }!
    var x = 0.0
    for slot in row2[..<index] { x += slot.width * u + (slot.width - 1) * s + s }
    let f = frames[3]!
    #expect(abs(f.center.x - (x + u / 2)) < 0.001)
    #expect(abs(f.center.y - (2 * (0.92 * u + s) + 0.46 * u)) < 0.001)
    #expect(abs(f.height - 0.92 * u) < 0.001)
}

@Test func bottomRowIsShiftedByFourPitches() {
    let u = KeyboardSizing.baseUnit, s = KeyboardSizing.keySpacing
    let first = KeyboardGeometry.rows(for: .ansi)[4][0]
    let frame = frames[first.keyCode]!
    #expect(abs(frame.center.x - ((u + s) * 4 + frame.width / 2)) < 0.001)
}

@Test func homeKeysAreFrameCenters() {
    for finger in Finger.allCases where finger != .thumb {
        #expect(layout.home(finger) == frames[finger.homeKeyCode]!.center)
    }
}

@Test func thumbsAreAtThirdsOfSpace() {
    let space = frames[KeyboardGeometry.space]!
    let left = space.center.x - space.width / 2
    #expect(abs(layout.thumbs.left.x - (left + space.width / 3)) < 0.001)
    #expect(abs(layout.thumbs.right.x - (left + space.width * 2 / 3)) < 0.001)
    #expect(layout.thumbs.left.y == space.center.y)
}

@Test func tipsStandStillWithoutMotion() {
    let press = HandsPress(keyCode: 5)
    let tips = HandsOverlayModel.tips(layout: layout, frames: frames, press: press, elapsedMs: 250, moves: false)
    #expect(tips.count == 10)
    for tip in tips where tip.finger != .thumb { #expect(tip.point == layout.home(tip.finger)) }
    #expect(!tips.contains { $0.isDown })
    #expect(HandsOverlayModel.pressedKeys(press: press, elapsedMs: 250, moves: false).isEmpty)
}

@Test func motionRules() {
    #expect(HandsOverlayModel.movesTips(setting: true, reduceMotion: false))
    #expect(!HandsOverlayModel.movesTips(setting: false, reduceMotion: false))
    #expect(!HandsOverlayModel.movesTips(setting: true, reduceMotion: true))
}

@Test func pressedFingerReachesKeyAndReturns() {
    let g = KeyboardGeometry.rows(for: .ansi)[1][4].keyCode  // не домашняя клавиша
    let finger = FingerMap.finger(for: g)!
    let press = HandsPress(keyCode: g)
    func tip(_ ms: Double) -> FingerTip {
        HandsOverlayModel.tips(layout: layout, frames: frames, press: press, elapsedMs: ms, moves: true)
            .first { $0.finger == finger }!
    }
    #expect(tip(0).point == layout.home(finger))
    #expect(tip(250).point == frames[g]!.center)
    #expect(tip(250).isDown)
    #expect(tip(520).point == layout.home(finger))
    #expect(HandsOverlayModel.pressedKeys(press: press, elapsedMs: 250, moves: true) == [g])
}

@Test func shiftSendsOppositePinkyAtOnce() {
    let press = HandsPress(keyCode: 3, shift: true)  // F — левая рука, Shift правый
    let tips = HandsOverlayModel.tips(layout: layout, frames: frames, press: press, elapsedMs: 250, moves: true)
    #expect(tips.first { $0.finger == .rightPinky }!.point == frames[KeyboardGeometry.rightShift]!.center)
    #expect(HandsOverlayModel.pressedKeys(press: press, elapsedMs: 250, moves: true)
        == [3, KeyboardGeometry.rightShift])
}

@Test func spacePulsesThumbInPlace() {
    let press = HandsPress(keyCode: KeyboardGeometry.space, spaceHalf: .left)
    let tips = HandsOverlayModel.tips(layout: layout, frames: frames, press: press, elapsedMs: 250, moves: true)
    let left = tips.first { $0.id == "thumbLeft" }!
    #expect(left.isDown && left.point == layout.thumbs.left)
    #expect(!tips.first { $0.id == "thumbRight" }!.isDown)
}

@Test func overlaySymbolsExist() {
    for name in ["pause.fill", "play.fill"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}
