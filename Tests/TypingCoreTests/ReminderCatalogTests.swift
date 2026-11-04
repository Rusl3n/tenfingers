import Foundation
import Testing
@testable import TypingCore

private func hasCyrillic(_ s: String) -> Bool { s.unicodeScalars.contains { (0x400...0x4FF).contains($0.value) } }

private let contexts: [ReminderCatalog.Context] = [.atRisk(streak: 5), .fresh, .almost(minutes: 7), .later, .repair(streak: 34, minutes: 12)]

@Test func catalogHasFortyEightUniquePhrases() {
    #expect(ReminderCatalog.phrases.count == 48)
    #expect(Set(ReminderCatalog.phrases.map(\.key)).count == 48)
    // Тон фразы — только обычный или шуточный.
    #expect(ReminderCatalog.phrases.allSatisfy { $0.tone != .mixed })
}

@Test func everyToneStageAndContextHasANonAdultCandidate() {
    for tone in [ReminderTone.normal, .funny] {
        for stage in ReminderStage.allCases {
            for context in contexts {
                let found = ReminderCatalog.candidates(tone: tone, stage: stage, adultHumor: false, context: context)
                #expect(!found.isEmpty, "нет кандидатов: \(tone) \(stage) \(context)")
                #expect(found.allSatisfy { !$0.adult })
            }
        }
    }
}

@Test func adultPhrasesAreFunnyAndHiddenWithoutAdultHumor() {
    let adult = ReminderCatalog.phrases.filter(\.adult)
    #expect(adult.count == 6)
    #expect(adult.allSatisfy { $0.tone == .funny })
    for stage in ReminderStage.allCases {
        for context in contexts {
            for tone in ReminderTone.allCases {
                let off = ReminderCatalog.candidates(tone: tone, stage: stage, adultHumor: false, context: context)
                #expect(off.allSatisfy { !$0.adult })
            }
        }
    }
    // Обычный тон «взрослых» не получает даже при включённом юморе.
    let normal = ReminderCatalog.candidates(tone: .normal, stage: .drama, adultHumor: true, context: .later)
    #expect(normal.allSatisfy { $0.tone == .normal && !$0.adult })
    // Шуточный с юмором видит «взрослую» фразу ступени.
    let funny = ReminderCatalog.candidates(tone: .funny, stage: .soft, adultHumor: true, context: .later)
    #expect(funny.contains { $0.adult })
}

@Test func mixedIsUnionOfNormalAndFunny() {
    for stage in ReminderStage.allCases {
        for context in contexts {
            let mixed = Set(ReminderCatalog.candidates(tone: .mixed, stage: stage, adultHumor: true, context: context).map(\.key))
            let both = Set(ReminderCatalog.candidates(tone: .normal, stage: stage, adultHumor: true, context: context).map(\.key))
                .union(ReminderCatalog.candidates(tone: .funny, stage: stage, adultHumor: true, context: context).map(\.key))
            #expect(mixed == both)
        }
    }
}

@Test func candidatesMatchContextNeeds() {
    func needs(_ context: ReminderCatalog.Context) -> Set<ReminderCatalog.Need> {
        var result: Set<ReminderCatalog.Need> = []
        for stage in ReminderStage.allCases {
            result.formUnion(ReminderCatalog.candidates(tone: .mixed, stage: stage, adultHumor: true, context: context).map(\.need))
        }
        return result
    }
    #expect(needs(.atRisk(streak: 3)) == [.none, .streak])
    #expect(needs(.fresh) == [.none])
    #expect(needs(.almost(minutes: 4)) == [.none, .minutes])
    #expect(needs(.later) == [.none])
    #expect(needs(.repair(streak: 3, minutes: 4)) == [.repair])
}

@Test func repairSetHasThreePhrasesPerToneAndIgnoresStage() {
    let repair = ReminderCatalog.phrases.filter { $0.need == .repair }
    #expect(repair.count == 6)
    #expect(repair.filter { $0.tone == .normal }.count == 3 && repair.filter { $0.tone == .funny }.count == 3)
    #expect(repair.allSatisfy { !$0.adult && ($0.key.contains("{streak}") || $0.key.contains("{minutes}")) })
    let context = ReminderCatalog.Context.repair(streak: 34, minutes: 12)
    for stage in ReminderStage.allCases {
        #expect(ReminderCatalog.candidates(tone: .normal, stage: stage, adultHumor: true, context: context).count == 3)
        #expect(ReminderCatalog.candidates(tone: .funny, stage: stage, adultHumor: true, context: context).count == 3)
        #expect(ReminderCatalog.candidates(tone: .mixed, stage: stage, adultHumor: false, context: context).count == 6)
    }
    // Фразы починки не попадают в другие контексты.
    for other in [ReminderCatalog.Context.atRisk(streak: 5), .fresh, .almost(minutes: 3), .later] {
        for stage in ReminderStage.allCases {
            #expect(ReminderCatalog.candidates(tone: .mixed, stage: stage, adultHumor: true, context: other)
                .allSatisfy { $0.need != .repair })
        }
    }
}

@Test func repairPickFillsStreakAndMinutes() throws {
    for slot in 0..<12 {
        let line = try #require(ReminderCatalog.pick(context: .repair(streak: 34, minutes: 12), stage: .soft, tone: .mixed,
                                                     adultHumor: true, dayKey: "2026-03-10", slot: slot))
        #expect(line.streak == 34 && line.minutes == 12)
        let text = ReminderCatalog.render(line, localization: "ru")
        #expect(!text.contains("{"))
    }
}

@Test func needMatchesPlaceholdersInKey() {
    for phrase in ReminderCatalog.phrases where phrase.need != .repair {
        #expect((phrase.need == .streak) == phrase.key.contains("{streak}"), "\(phrase.key)")
        #expect((phrase.need == .minutes) == phrase.key.contains("{minutes}"), "\(phrase.key)")
    }
}

@Test func renderSubstitutesNumbersInBothLanguages() {
    let streak = ReminderLine(key: "Серия {streak} дн. ждёт продолжения", streak: 5, minutes: 0)
    #expect(ReminderCatalog.render(streak, localization: "ru") == "Серия 5 дн. ждёт продолжения")
    #expect(!ReminderCatalog.render(streak, localization: "en").contains("{"))
    #expect(ReminderCatalog.render(streak, localization: "en").contains("5"))
    let minutes = ReminderLine(key: "До полного огня осталось {minutes} мин", streak: 0, minutes: 7)
    #expect(ReminderCatalog.render(minutes, localization: "ru") == "До полного огня осталось 7 мин")
    #expect(ReminderCatalog.render(minutes, localization: "en").contains("7"))
    let plain = ReminderLine(key: "Самое время для короткой тренировки", streak: 9, minutes: 9)
    #expect(ReminderCatalog.render(plain, localization: "ru") == "Самое время для короткой тренировки")
}

@Test func everyPhraseHasEnglishWithoutCyrillicAndWithSamePlaceholders() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/TypingCore/Resources/en.lproj/Localizable.strings")
    let en = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    for phrase in ReminderCatalog.phrases {
        let english = try #require(en[phrase.key], "нет перевода: \(phrase.key)")
        #expect(english != phrase.key)
        #expect(!hasCyrillic(english), "en: \(english)")
        #expect(english.contains("{streak}") == phrase.key.contains("{streak}"), "en: \(english)")
        #expect(english.contains("{minutes}") == phrase.key.contains("{minutes}"), "en: \(english)")
        #expect(ReminderCatalog.render(ReminderLine(key: phrase.key, streak: 3, minutes: 4), localization: "en") == english
            .replacingOccurrences(of: "{streak}", with: "3").replacingOccurrences(of: "{minutes}", with: "4"))
    }
}

@Test func fnv1aMatchesReferenceVectors() {
    #expect(ReminderCatalog.fnv1a("") == 0xcbf29ce484222325)
    #expect(ReminderCatalog.fnv1a("a") == 0xaf63dc4c8601ec8c)
}

@Test func pickIsDeterministicAndFillsNumbers() throws {
    let a = ReminderCatalog.pick(context: .atRisk(streak: 6), stage: .insistent, tone: .mixed, adultHumor: true,
                                 dayKey: "2026-03-10", slot: 1)
    let b = ReminderCatalog.pick(context: .atRisk(streak: 6), stage: .insistent, tone: .mixed, adultHumor: true,
                                 dayKey: "2026-03-10", slot: 1)
    #expect(a == b)
    #expect(a != nil)
    let candidates = ReminderCatalog.candidates(tone: .mixed, stage: .insistent, adultHumor: true, context: .atRisk(streak: 6))
    let expected = candidates[Int(ReminderCatalog.fnv1a("2026-03-10#1") % UInt64(candidates.count))]
    #expect(a?.key == expected.key)
    #expect(a?.streak == (expected.need == .streak ? 6 : 0))
    // Во всех слотах дня выбор не падает и возвращает подходящую фразу.
    for slot in 0..<12 {
        let line = try #require(ReminderCatalog.pick(context: .almost(minutes: 4), stage: .drama, tone: .funny,
                                                     adultHumor: false, dayKey: "2026-03-11", slot: slot))
        let phrase = try #require(ReminderCatalog.phrases.first { $0.key == line.key })
        #expect(phrase.need != .streak && !phrase.adult && phrase.stage == .drama)
        #expect(line.minutes == (phrase.need == .minutes ? 4 : 0))
    }
}
