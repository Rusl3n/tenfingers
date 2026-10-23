import Foundation
import Testing
import TypingCore
@testable import TenFingers

@Test func hintModeAutoUsesLessonHint() {
    #expect(HintMode.auto.resolve(.onError) == .onError)
    #expect(HintMode.full.resolve(.hidden) == .full)
    #expect(HintMode.hidden.resolve(.full) == .hidden)
}

@Test func speedUnitFormatting() {
    #expect(SpeedUnit.cpm.format(142.4) == "142 зн/мин")
    #expect(SpeedUnit.wpm.format(142.4) == "28 WPM")
}

@Test func durationFormatting() {
    #expect(Formatting.duration(42_000) == "11 ч 40 мин")
    #expect(Formatting.duration(125) == "2 мин")
    #expect(Formatting.clock(72) == "01:12")
    #expect(Formatting.percent(0.9741, locale: Locale(identifier: "ru_RU")) == "97,4%")
}

@Test func percentFollowsLocale() {
    #expect(Formatting.percent(0.9741, locale: Locale(identifier: "en_US")) == "97.4%")
}
