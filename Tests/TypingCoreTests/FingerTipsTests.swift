import Testing
@testable import TypingCore

private func pt(_ x: Double, _ y: Double) -> PlanePoint { PlanePoint(x: x, y: y) }

private let layout = FingerTipsLayout(
    homeKeys: [
        .leftPinky: pt(1.5, 2), .leftRing: pt(2.5, 2), .leftMiddle: pt(3.5, 2), .leftIndex: pt(4.5, 2),
        .rightIndex: pt(7.5, 2), .rightMiddle: pt(8.5, 2), .rightRing: pt(9.5, 2), .rightPinky: pt(10.5, 2),
    ],
    space: (left: pt(5, 4), right: pt(7, 4)),
    keyPitch: 3,
    keyboardCenterX: 6
)

@Test func homeIsKeyCentersAndThumbsAtSpace() {
    #expect(layout.home(.leftIndex) == pt(4.5, 2))
    #expect(layout.home(.rightPinky) == pt(10.5, 2))
    #expect(layout.home(.thumb) == pt(7, 4))
    #expect(layout.thumbs.left == pt(5, 4))
    #expect(layout.thumbs.right == pt(7, 4))
}

@Test func arcBendsOutwardByThirdOfPitch() {
    let left = layout.arc(finger: .leftIndex, to: pt(3.5, 1))
    #expect(left.start == pt(4.5, 2) && left.end == pt(3.5, 1))
    #expect(left.control == pt(4.0 - 1, 1.5))
    let right = layout.arc(finger: .rightMiddle, to: pt(9.5, 1))
    #expect(right.control == pt(9.0 + 1, 1.5))
}

@Test func arcToHomeKeyIsDegenerate() {
    let arc = layout.arc(finger: .leftIndex, to: pt(4.5, 2))
    #expect(arc.start == arc.control && arc.control == arc.end)
}

@Test func positionFollowsBezier() {
    let target = pt(3.5, 1)
    #expect(layout.position(finger: .leftIndex, target: target, progress: 0) == pt(4.5, 2))
    #expect(layout.position(finger: .leftIndex, target: target, progress: 1) == target)
    #expect(layout.position(finger: .leftIndex, target: target, progress: -3) == pt(4.5, 2))
    let mid = layout.position(finger: .leftIndex, target: target, progress: 0.5)
    #expect(mid == pt(0.25 * 4.5 + 0.5 * 3.0 + 0.25 * 3.5, 0.25 * 2 + 0.5 * 1.5 + 0.25 * 1))
}

@Test func progressTiming() {
    #expect(FingerPress.progress(elapsedMs: 0) == 0)
    #expect(FingerPress.progress(elapsedMs: 85) == 0.5)
    #expect(FingerPress.progress(elapsedMs: 170) == 1)
    #expect(FingerPress.progress(elapsedMs: 330) == 1)
    #expect(FingerPress.progress(elapsedMs: 425) == 0.5)
    #expect(FingerPress.progress(elapsedMs: 520) == 0)
    #expect(FingerPress.progress(elapsedMs: 900) == 0)
}

@Test func isDownWindow() {
    #expect(!FingerPress.isDown(elapsedMs: 139))
    #expect(FingerPress.isDown(elapsedMs: 140))
    #expect(!FingerPress.isDown(elapsedMs: 361))
}

@Test func diameterScalesWithPitch() {
    #expect(abs(layout.diameter(pressing: false) - 1.2) < 1e-9)
    #expect(abs(layout.diameter(pressing: true) - 1.5) < 1e-9)
}
