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

@Test func percentCanRoundDown() {
    let ru = Locale(identifier: "ru_RU")
    // 99,49% не показываем как 99,5%: иначе «нужно от 99,5% (у вас 99,5%)».
    #expect(Formatting.percent(0.9949, rounding: .down, locale: ru) == "99,4%")
    #expect(Formatting.percent(0.989, rounding: .down, locale: ru) == "98,9%")
    #expect(Formatting.percent(1, rounding: .down, locale: ru) == "100,0%")
    #expect(Formatting.percent(0.9949, locale: ru) == "99,5%")
}

@Test func nextStarRequirementsTextNamesSpeedAndErrors() {
    #expect(StarHintText.requirements(needCpm: nil, maxErrors: 0, cpm: 80, errors: 1, unit: .cpm)
            == "без ошибок (у вас 1)")
    #expect(StarHintText.requirements(needCpm: 60, maxErrors: nil, cpm: 52.7, errors: 0, unit: .cpm)
            == "скорость от 60 зн/мин (у вас 52 зн/мин)")
    #expect(StarHintText.requirements(needCpm: 78, maxErrors: 1, cpm: 60, errors: 3, unit: .cpm)
            == "скорость от 78 зн/мин (у вас 60 зн/мин) и не больше 1 ошибки (у вас 3)")
    #expect(StarHintText.requirements(needCpm: nil, maxErrors: nil, cpm: 60, errors: 1, unit: .cpm) == "")
    // Цель неизвестна (0): условие скорости не показывается как «0 зн/мин».
    #expect(StarHintText.requirements(needCpm: 0, maxErrors: 2, cpm: 50, errors: 3, unit: .cpm)
            == "не больше 2 ошибок (у вас 3)")
}

@Test func starsExplanationSpeedGoalsFollowStageTarget() {
    #expect(StarHintText.speedGoal(targetCpm: 60, factor: 0.8, unit: .cpm) == "48 зн/мин")
    #expect(StarHintText.speedGoal(targetCpm: 60, factor: 1.3, unit: .cpm) == "78 зн/мин")
    #expect(StarHintText.speedGoal(targetCpm: 60, factor: 1.5, unit: .cpm) == "90 зн/мин")
    // 45 × 1,3 = 58,5: округляем вверх, чтобы названная скорость точно давала звезду.
    #expect(StarHintText.speedGoal(targetCpm: 45, factor: 1.3, unit: .cpm) == "59 зн/мин")
    #expect(StarHintText.speedGoal(targetCpm: 100, factor: 1.3, unit: .wpm) == "26 WPM")
}

/// Попап называет пороги в ошибках на 100 знаков (длины проверки он не знает).
@Test func errorsRuleNamesErrorsPerHundredChars() {
    #expect(StarHintText.errorsRule(accuracy: 0.96) == "не больше 4 ошибок на 100 знаков")
    #expect(StarHintText.errorsRule(accuracy: 0.97) == "не больше 3 ошибок на 100 знаков")
    #expect(StarHintText.errorsRule(accuracy: 0.98) == "не больше 2 ошибок на 100 знаков")
    #expect(StarHintText.errorsRule(accuracy: 0.995) == "не больше 1 ошибки на 200 знаков")
    #expect(StarHintText.errorsRule(accuracy: 1) == "без ошибок")
}

@Test func starRulesFollowThresholds() throws {
    let ru = Locale(identifier: "ru_RU")
    let two = try #require(LessonScoring.threshold(for: 2)), three = try #require(LessonScoring.threshold(for: 3))
    let twoRule = StarHintText.rule(two, targetCpm: 60, unit: .cpm, locale: ru)
    #expect(twoRule.contains("48 зн/мин") && twoRule.contains("0,8"), "«\(twoRule)»")
    let threeRule = StarHintText.rule(three, targetCpm: 60, unit: .cpm, locale: ru)
    #expect(threeRule.hasPrefix("скорость не ниже цели (60 зн/мин)"), "«\(threeRule)»")
}

/// Цель этапа неизвестна (урока нет в курсе): условие скорости не показывается как «0 зн/мин».
@Test func starRulesWithoutStageGoalOmitSpeed() {
    let ru = Locale(identifier: "ru_RU")
    for threshold in LessonScoring.thresholds {
        let rule = StarHintText.rule(threshold, targetCpm: 0, unit: .cpm, locale: ru)
        #expect(!rule.contains("зн/мин"), "«\(rule)»")
    }
}

// MARK: - ★★★★★ — только за чистый урок

private func stepStat(_ kind: ExerciseKind, index: Int? = nil) -> StepStat {
    StepStat(kind: kind, bestAccuracy: 0.9, errorsInBest: 12, cpmInBest: 80, stepIndex: index)
}

/// Подсказка называет мешающий шаг и порог в ошибках на 100 знаков (язык интерфейса — по умолчанию).
@Test func cleanStepRuleNamesTheStepAndErrorLimit() {
    let words = ExerciseKind.words.localizedTitle
    let wordsStep = stepStat(.words), combosStep = stepStat(.combos)
    #expect(StarHintText.cleanStep(wordsStep) == "пройдите шаг «\(words)» не больше чем с 2 ошибками на 100 знаков")
    #expect(StarHintText.requirements(needCpm: nil, maxErrors: nil, cpm: 100, errors: 0, unit: .cpm,
                                      blockingStep: wordsStep) == StarHintText.cleanStep(wordsStep))
    // Скорость и шаг вместе.
    #expect(StarHintText.requirements(needCpm: 90, maxErrors: nil, cpm: 80, errors: 0, unit: .cpm, blockingStep: wordsStep)
            == "скорость от 90 зн/мин (у вас 80 зн/мин) и \(StarHintText.cleanStep(wordsStep))")
    // Скорость, ошибки и шаг: через запятую и «и».
    #expect(StarHintText.requirements(needCpm: 90, maxErrors: 0, cpm: 80, errors: 1, unit: .cpm, blockingStep: combosStep)
            == "скорость от 90 зн/мин (у вас 80 зн/мин), без ошибок (у вас 1) и \(StarHintText.cleanStep(combosStep))")
}

/// Шаги издания 2 одного вида различаются номером: «пройдите шаг 4 «Слова» …» (номер — с единицы).
@Test func cleanStepRuleNamesTheStepNumber() {
    let words = ExerciseKind.words.localizedTitle
    #expect(StarHintText.cleanStep(stepStat(.words, index: 3))
            == "пройдите шаг 4 «\(words)» не больше чем с 2 ошибками на 100 знаков")
}

/// Строка ★★★★★ в попапе: проверка и остальные шаги — в ошибках на 100 знаков, без процентов.
@Test func fiveStarRuleSeparatesCheckFromOtherSteps() throws {
    let ru = Locale(identifier: "ru_RU")
    let five = try #require(LessonScoring.threshold(for: LessonScoring.maxStars))
    let rule = StarHintText.topRule(five, targetCpm: 60, unit: .cpm, locale: ru)
    #expect(rule == "скорость от 1,5 × цели (90 зн/мин), без ошибок на проверке, а на остальных шагах — "
            + "не больше 2 ошибок на 100 знаков", "«\(rule)»")
    #expect(!rule.contains("%"))
}

/// Множитель в попапе следует языку интерфейса, а не региону системы: русский набор даёт «1,3», английский — «1.3».
@Test func starRuleMultiplierFollowsInterfaceLanguage() throws {
    let ru = try interfaceBundle("ru"), en = try interfaceBundle("en")
    let four = try #require(LessonScoring.threshold(for: 4))
    #expect(StarHintText.rule(four, targetCpm: 60, unit: .cpm, bundle: ru).contains("1,3"))
    #expect(StarHintText.rule(four, targetCpm: 60, unit: .cpm, bundle: en).contains("1.3"))
    let five = try #require(LessonScoring.threshold(for: LessonScoring.maxStars))
    #expect(StarHintText.topRule(five, targetCpm: 60, unit: .cpm, bundle: ru).contains("1,5"))
}
