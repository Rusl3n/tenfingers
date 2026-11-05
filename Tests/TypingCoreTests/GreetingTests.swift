import Testing
@testable import TypingCore

// Приветствие на «Главной» (спецификация фазы 8, §5a, решение 7): часть суток по часу.

@Test func greetingPartBoundaries() {
    #expect(Greeting.part(hour: 4) == .night)
    #expect(Greeting.part(hour: 5) == .morning)
    #expect(Greeting.part(hour: 11) == .morning)
    #expect(Greeting.part(hour: 12) == .day)
    #expect(Greeting.part(hour: 16) == .day)
    #expect(Greeting.part(hour: 17) == .evening)
    #expect(Greeting.part(hour: 22) == .evening)
    #expect(Greeting.part(hour: 23) == .night)
    #expect(Greeting.part(hour: 0) == .night)
}

@Test func greetingPartCoversEveryHour() {
    for hour in 0..<24 { _ = Greeting.part(hour: hour) }
    #expect(GreetingPart.allCases.count == 4)
}
