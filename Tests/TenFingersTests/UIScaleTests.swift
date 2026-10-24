import CoreGraphics
import Testing
@testable import TenFingers

@Test func uiScaleOptionsAreSortedAndIncludeDefault() {
    #expect(UIScale.options == [0.8, 0.9, 1.0, 1.1, 1.25, 1.5])
    #expect(UIScale.options.contains(UIScale.defaultValue))
    #expect(UIScale.defaultValue == 1)
}

@Test func uiScaleClampsToNearestOption() {
    #expect(UIScale.clamped(1.25) == 1.25)
    #expect(UIScale.clamped(0.1) == 0.8)
    #expect(UIScale.clamped(3) == 1.5)
    #expect(UIScale.clamped(1.2) == 1.25)
    #expect(UIScale.clamped(1.04) == 1.0)
    #expect(UIScale.clamped(0.86) == 0.9)
    #expect(UIScale.clamped(.nan) == 1)
    #expect(UIScale.clamped(.infinity) == 1)
}

@Test func uiScaleTitleIsPercent() {
    #expect(UIScale.title(1.25) == "125%")
    #expect(UIScale.title(0.8) == "80%")
    #expect(UIScale.title(1) == "100%")
}

@Test func logicalSizeDividesByScale() {
    #expect(UIScale.logicalSize(CGSize(width: 1500, height: 900), scale: 1.5) == CGSize(width: 1000, height: 600))
    #expect(UIScale.logicalSize(CGSize(width: 800, height: 400), scale: 0.8) == CGSize(width: 1000, height: 500))
    #expect(UIScale.logicalSize(CGSize(width: 800, height: 400), scale: 1) == CGSize(width: 800, height: 400))
    // Неверный масштаб в настройках не ломает разметку.
    #expect(UIScale.logicalSize(CGSize(width: 800, height: 400), scale: 0) == CGSize(width: 1000, height: 500))
}

@Test func minimumWindowGrowsWithScaleButFitsScreen() {
    let base = UIScale.baseMinimumWindowSize
    #expect(base == CGSize(width: 960, height: 640))
    #expect(UIScale.minimumWindowSize(scale: 1, visible: nil) == base)
    #expect(UIScale.minimumWindowSize(scale: 0.8, visible: nil) == base)
    #expect(UIScale.minimumWindowSize(scale: 1.25, visible: CGSize(width: 2560, height: 1400))
            == CGSize(width: 1200, height: 800))
    // Экран меньше: не больше видимой области, но и не меньше обычного минимума.
    #expect(UIScale.minimumWindowSize(scale: 1.5, visible: CGSize(width: 1440, height: 875))
            == CGSize(width: 1440, height: 875))
    #expect(UIScale.minimumWindowSize(scale: 1.5, visible: CGSize(width: 900, height: 600)) == base)
}
