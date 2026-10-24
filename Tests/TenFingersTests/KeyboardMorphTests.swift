import CoreGraphics
import Testing
@testable import TenFingers

private let mini = CGRect(x: 100, y: 300, width: 300, height: 120)
private let full = CGRect(x: 40, y: 500, width: 600, height: 240)

@Test func morphAtStartSitsOnTheMiniature() {
    let t = KeyboardMorph.transform(from: mini, to: full, progress: 0)
    #expect(t.scale == 0.5)
    #expect(t.offset == CGSize(width: 60, height: -200))
}

@Test func morphAtEndIsIdentity() {
    let t = KeyboardMorph.transform(from: mini, to: full, progress: 1)
    #expect(t.scale == 1)
    #expect(t.offset == .zero)
}

@Test func morphHalfwayInterpolatesTheRect() {
    // Прямоугольник посередине: x 70, y 400, ширина 450.
    let t = KeyboardMorph.transform(from: mini, to: full, progress: 0.5)
    #expect(t.scale == 0.75)
    #expect(t.offset == CGSize(width: 30, height: -100))
}

@Test func morphWithoutFramesIsIdentity() {
    #expect(KeyboardMorph.transform(from: nil, to: full, progress: 0) == .identity)
    #expect(KeyboardMorph.transform(from: mini, to: nil, progress: 0) == .identity)
    #expect(KeyboardMorph.transform(from: mini, to: .zero, progress: 0) == .identity)
}
