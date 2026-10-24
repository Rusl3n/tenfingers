import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private let firstSix = Set(Language.ru.adaptiveOrder.prefix(6))  // о е а и н т

@Test func openLettersFromCourseOnly() throws {
    let course = try CourseCatalog.load(.ru)
    // Пройдены 1.1 и 1.2 (а о в л); адаптивная тренировка не начиналась — в ней открыты стартовые 6 букв.
    let letters = OpenLetters.combine(language: .ru, course: course, passedLessonIds: ["ru.1.1", "ru.1.2"],
                                      adaptiveCount: AdaptiveTrainer.initialLetters)
    #expect(letters == firstSix.union("аовл"))
    #expect(!letters.contains(" "))
}

@Test func openLettersFromAdaptiveOnly() throws {
    let course = try CourseCatalog.load(.ru)
    let letters = OpenLetters.combine(language: .ru, course: course, passedLessonIds: [], adaptiveCount: 9)
    #expect(letters == Set(Language.ru.adaptiveOrder.prefix(9)))
    #expect(OpenLetters.combine(language: .ru, course: nil, passedLessonIds: ["ru.1.1"], adaptiveCount: 6) == firstSix)
}

@Test func openLettersUnionUsesLastPassedLessonInCourseOrder() throws {
    let course = try CourseCatalog.load(.ru)
    // Порядок в наборе не важен: берётся последний пройденный урок по курсу (1.3) со всеми буквами до него.
    let letters = OpenLetters.combine(language: .ru, course: course, passedLessonIds: ["ru.1.3", "ru.1.1"],
                                      adaptiveCount: 7)
    #expect(letters == Set(Language.ru.adaptiveOrder.prefix(7)).union("аовлыд"))
}

@MainActor @Test func openLettersReadFromStore() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let passed = LessonProgress(lessonId: "ru.1.2", language: "ru")
    passed.passedAt = Date()
    context.insert(passed)
    context.insert(LessonProgress(lessonId: "ru.1.3", language: "ru"))  // начат, но не пройден
    let english = LessonProgress(lessonId: "en.1.5", language: "en")
    english.passedAt = Date()
    context.insert(english)
    context.insert(AdaptiveState(language: "ru", unlockedCount: 8))
    try context.save()
    let course = try CourseCatalog.load(.ru)
    let letters = try StatsReader(context: context).openLetters(language: .ru, course: course)
    #expect(letters == Set(Language.ru.adaptiveOrder.prefix(8)).union("аовл"))
}

@Test func weakSpotsNeedEnoughOpenLetters() {
    let weak = KeyMastery(ewmaMs: 900, errorRate: 0.2, presses: 50)
    let stats: [Character: KeyMastery] = ["о": weak, "е": weak, "щ": weak]
    let few = TrainingSnapshot.make(language: .ru, unlockedCount: 6, keyMastery: stats, bigramMastery: [:],
                                    targetCpm: 175, openLetters: firstSix)
    #expect(few.weakKeys.sorted() == ["е", "о"])  // «щ» ещё не открыта
    #expect(few.needsMoreLetters)
    #expect(!few.canStartWeakSpots)
    let enough = TrainingSnapshot.make(language: .ru, unlockedCount: 8, keyMastery: stats, bigramMastery: [:],
                                       targetCpm: 175, openLetters: Set(Language.ru.adaptiveOrder.prefix(8)))
    #expect(!enough.needsMoreLetters)
    #expect(enough.canStartWeakSpots)
}

@Test func weakSpotsFocusKeepsOnlyOpenLetters() {
    let weak = KeyMastery(ewmaMs: 900, errorRate: 0.2, presses: 50)
    #expect(WeakSpotsFocus.keys(["о": weak, "щ": weak, " ": weak], letters: firstSix, thresholdMs: 343) == ["о"])
    #expect(WeakSpotsFocus.bigrams(["то": weak, "щи": weak], letters: firstSix, thresholdMs: 343) == ["то"])
}
