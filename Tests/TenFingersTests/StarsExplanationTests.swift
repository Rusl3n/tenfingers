import Foundation
import Testing
import TypingCore
@testable import TenFingers

@Test func speedUnitRoundsInRequestedDirection() {
    #expect(SpeedUnit.cpm.format(59.9, rounding: .down) == "59 зн/мин")
    #expect(SpeedUnit.cpm.format(58.1, rounding: .up) == "59 зн/мин")
    #expect(SpeedUnit.wpm.format(59, rounding: .down) == "11 WPM")
    #expect(SpeedUnit.wpm.format(78, rounding: .up) == "16 WPM")
    #expect(SpeedUnit.cpm.format(142.4) == "142 зн/мин")
}

@Test func compactPercentDropsZeroFraction() {
    let ru = Locale(identifier: "ru_RU"), en = Locale(identifier: "en_US")
    #expect(Formatting.compactPercent(0.96, locale: ru) == "96%")
    #expect(Formatting.compactPercent(0.98, locale: ru) == "98%")
    #expect(Formatting.compactPercent(0.995, locale: ru) == "99,5%")
    #expect(Formatting.compactPercent(0.995, locale: en) == "99.5%")
}

@Test func percentCanRoundDown() {
    let ru = Locale(identifier: "ru_RU")
    // 99,49% не показываем как 99,5%: иначе «нужно от 99,5% (у вас 99,5%)».
    #expect(Formatting.percent(0.9949, rounding: .down, locale: ru) == "99,4%")
    #expect(Formatting.percent(0.989, rounding: .down, locale: ru) == "98,9%")
    #expect(Formatting.percent(1, rounding: .down, locale: ru) == "100,0%")
    #expect(Formatting.percent(0.9949, locale: ru) == "99,5%")
}

@Test func nextStarRequirementsTextNamesMissingConditions() {
    let ru = Locale(identifier: "ru_RU")
    #expect(StarHintText.requirements(needCpm: nil, needAccuracy: 0.995, cpm: 80, accuracy: 0.989,
                                      unit: .cpm, locale: ru)
            == "точность от 99,5% (у вас 98,9%)")
    #expect(StarHintText.requirements(needCpm: 60, needAccuracy: nil, cpm: 52.7, accuracy: 0.99,
                                      unit: .cpm, locale: ru)
            == "скорость от 60 зн/мин (у вас 52 зн/мин)")
    #expect(StarHintText.requirements(needCpm: 78, needAccuracy: 0.995, cpm: 60, accuracy: 0.98,
                                      unit: .cpm, locale: ru)
            == "скорость от 78 зн/мин (у вас 60 зн/мин) и точность от 99,5% (у вас 98,0%)")
    #expect(StarHintText.requirements(needCpm: nil, needAccuracy: nil, cpm: 60, accuracy: 0.98,
                                      unit: .cpm, locale: ru) == "")
}

@Test func starsExplanationGoalsFollowStageTarget() {
    #expect(StarHintText.twoStarGoal(targetCpm: 60, unit: .cpm) == "60 зн/мин")
    #expect(StarHintText.threeStarGoal(targetCpm: 60, unit: .cpm) == "78 зн/мин")
    // 45 × 1,3 = 58,5: округляем вверх, чтобы названная скорость точно давала звезду.
    #expect(StarHintText.threeStarGoal(targetCpm: 45, unit: .cpm) == "59 зн/мин")
    #expect(StarHintText.threeStarGoal(targetCpm: 100, unit: .wpm) == "26 WPM")
}

/// Цель этапа неизвестна (урока нет в курсе): условие скорости не показывается как «0 зн/мин».
@Test func starRulesWithoutStageGoalOmitSpeed() {
    let ru = Locale(identifier: "ru_RU")
    let two = StarHintText.twoStarRule(targetCpm: 0, unit: .cpm, locale: ru)
    let three = StarHintText.threeStarRule(targetCpm: 0, unit: .cpm, locale: ru)
    #expect(!two.contains("зн/мин") && two.contains("98%"))
    #expect(!three.contains("зн/мин") && three.contains("99,5%"))
    #expect(StarHintText.twoStarRule(targetCpm: 60, unit: .cpm, locale: ru).contains("60 зн/мин"))
    #expect(StarHintText.threeStarRule(targetCpm: 60, unit: .cpm, locale: ru).contains("78 зн/мин"))
    #expect(StarHintText.requirements(needCpm: 0, needAccuracy: 0.995, cpm: 50, accuracy: 0.98, unit: .cpm, locale: ru)
        == "точность от 99,5% (у вас 98,0%)")
}
