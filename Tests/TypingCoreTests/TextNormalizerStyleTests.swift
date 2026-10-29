import Testing
@testable import TypingCore

// Нормализация корпуса и библиотеки по стилю этапа (решение 9) и разрез отрывка на предложения.

private let ru = Set("абвгдеёжзийклмнопрстуфхцчшщъыьэюя .,-!?:;\"()")
private let stage4 = TextStyle(case: .lower, punctuation: .none, digits: false)
private let stage5 = TextStyle(case: .mixed, punctuation: .all, digits: false)
private let stage6 = TextStyle(case: .mixed, punctuation: .all, digits: true)

@Test func styledLowercasesAndStripsPunctuationOnStageFour() {
    #expect(TextNormalizer.styled("Отец мой, Андрей Петрович — служил.", style: stage4, allowed: ru, capitals: false)
            == "отец мой андрей петрович служил")
    #expect(TextNormalizer.styled("Ёлка стоит.", style: stage4, allowed: ru, capitals: false) == "елка стоит")
    #expect(TextNormalizer.styled("В 1812 году.", style: stage4, allowed: ru, capitals: false) == nil)
}

@Test func styledKeepsCaseAndPunctuationOnStageFive() {
    #expect(TextNormalizer.styled("«Да», — сказал он.", style: stage5, allowed: ru, capitals: true) == "\"Да\", - сказал он.")
    #expect(TextNormalizer.styled("Да.", style: stage5, allowed: ru, capitals: false) == nil)     // заглавные не изучены
    #expect(TextNormalizer.styled("Ура; да.", style: stage5, allowed: ru.subtracting([";"]), capitals: true) == nil)
    #expect(TextNormalizer.styled("Ёж спит.", style: stage5, allowed: ru, capitals: true) == "Еж спит.")
}

@Test func styledKeepsDigitsOnStageSixOnlyWhenOpen() {
    #expect(TextNormalizer.styled("В 1812 году.", style: stage6, allowed: ru.union("0123456789"), capitals: true)
            == "В 1812 году.")
    #expect(TextNormalizer.styled("В 1812 году.", style: stage6, allowed: ru, capitals: true) == nil)
}

@Test func styledApostropheSurvivesOnlyBetweenLetters() {
    let en = Set("abcdefghijklmnopqrstuvwxyz '")
    #expect(TextNormalizer.styled("Don't stop, 'Tom'.", style: stage4, allowed: en, capitals: false) == "don't stop tom")
    #expect(TextNormalizer.styled("Don't stop.", style: stage4, allowed: Set("abcdefghijklmnopqrstuvwxyz "), capitals: false)
            == "dont stop")
}

@Test func styledTurnsHyphenBetweenLettersIntoSpaceWithoutPunctuation() {
    // «ктото» — не слово; без знаков дефис между буквами становится пробелом.
    #expect(TextNormalizer.styled("Кто-то пришёл.", style: stage4, allowed: ru, capitals: false) == "кто то пришёл")
    #expect(TextNormalizer.styled("Кто-то пришёл.", style: stage5, allowed: ru, capitals: true) == "Кто-то пришёл.")
}

@Test func sentencesSplitAfterTerminalPunctuation() {
    #expect(TextNormalizer.sentences("Да. Нет! Почему?  «Так»… Ладно")
            == ["Да.", "Нет!", "Почему?", "«Так»…", "Ладно"])
    #expect(TextNormalizer.sentences("  Что?! \"Нет.\"\nДа...  ") == ["Что?!", "\"Нет.\"", "Да..."])
}
