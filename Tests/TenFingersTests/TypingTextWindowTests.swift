import Testing
@testable import TenFingers

// Узкое окно: текст не обрезается многоточием, а показывает строки вокруг курсора.

@Test func wrapKeepsWordsWholeAndSpacesAtLineEnd() {
    let lines = TypingTextView.wrap(Array("цена продажу продал упал"), width: 12)
    #expect(lines == [0..<13, 13..<24])  // «цена продажу », «продал упал»
}

@Test func wrapBreaksWordLongerThanLine() {
    let lines = TypingTextView.wrap(Array("абвгдежзик ок"), width: 4)
    #expect(lines == [0..<4, 4..<8, 8..<11, 11..<13])  // «абвг», «дежз», «ик », «ок»
}

@Test func wrapOfEmptyTextIsOneEmptyLine() {
    #expect(TypingTextView.wrap([], width: 10) == [0..<0])
}

@Test func visibleLinesShowAllWhenTheyFit() {
    #expect(TypingTextView.visibleLines(total: 3, cursorLine: 2, capacity: 5) == 0..<3)
}

@Test func visibleLinesKeepOnePreviousLineAndFollowCursor() {
    #expect(TypingTextView.visibleLines(total: 10, cursorLine: 0, capacity: 3) == 0..<3)
    #expect(TypingTextView.visibleLines(total: 10, cursorLine: 4, capacity: 3) == 3..<6)
    #expect(TypingTextView.visibleLines(total: 10, cursorLine: 9, capacity: 3) == 7..<10)
}

@Test func visibleLinesWithRoomForTwoOrOneStartAtCursor() {
    #expect(TypingTextView.visibleLines(total: 10, cursorLine: 4, capacity: 2) == 4..<6)
    #expect(TypingTextView.visibleLines(total: 10, cursorLine: 4, capacity: 1) == 4..<5)
    #expect(TypingTextView.visibleLines(total: 10, cursorLine: 4, capacity: 0) == 4..<5)
}

@Test func cursorLineIsLineContainingPositionOrLastAtEnd() {
    let lines = [0..<13, 13..<24]
    #expect(TypingTextView.lineIndex(of: 12, in: lines) == 0)
    #expect(TypingTextView.lineIndex(of: 13, in: lines) == 1)
    #expect(TypingTextView.lineIndex(of: 24, in: lines) == 1)
}
