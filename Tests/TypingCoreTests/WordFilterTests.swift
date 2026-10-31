import Foundation
import Testing
@testable import TypingCore

// Список-исключение грубой лексики (blocklist.txt): те же примеры — в `prepare-sentences.py --check`.

private let blocked = [
    "нахуй", "похуй", "охуеть", "спиздил", "распиздяй", "наебал", "поебать", "проебал", "ебёт", "ебля",
    "выблядок", "блядь", "бля", "сука", "срал", "сраный", "ублюдок", "дерьмо", "задницу", "секс", "педик",
    "motherfucker", "bullshit", "goddamn", "jackass", "dumbass", "dickhead", "fuck", "shit", "damn", "ass",
    "bitch", "bastard", "asshole", "dick", "cunts",
    "сукин", "насрать", "засранец", "обосрался", "сиськи", "херня", "гондон", "пидр", "педераст", "долбоёб",
    "долбоеб", "уёбок", "ебошить", "наёбка", "порно", "порнографический", "гей", "геи", "геев",
    "cocksucker", "blowjob", "dildo", "skank", "prostitute", "hooker", "stripper", "prick", "pricks", "bugger",
    "buggered", "pimp", "pimps", "penis", "vaginas", "sperm", "nude", "nudes",
]
private let clean = [
    "корабля", "хлеб", "сравнить", "срам", "колебать", "небо", "ребус", "убедить", "обедать", "набег", "сук",
    "педикюр", "трахея", "класс", "sushi", "essex", "scunthorpe", "assist", "class", "grass", "dickens",
    "cocktail", "grape", "swanky", "sniggering", "сражение", "упорно", "упорный", "гейзер", "гейша", "сергей", "precious", "primp", "stripe",
]

@Test func wordFilterBlocksRudeWordsOnly() {
    for word in blocked { #expect(WordFilter.isBlocked(word), "\(word)") }
    for word in clean { #expect(!WordFilter.isBlocked(word), "\(word)") }
    #expect(WordFilter.isBlocked("Он сказал: Нахуй!"))
    #expect(!WordFilter.isBlocked("Свежий хлеб лежит на столе."))
}

@Test func wordFilterPatternKinds() {
    let pattern = WordFilter.pattern(fromList: "# комментарий\nany ab\nstart cd\nword ef\nчто-то непонятное\n")
    let regex = try! NSRegularExpression(pattern: pattern)
    func matches(_ s: String) -> Bool { regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
    #expect(matches("xaby") && matches("cdx") && !matches("xcd") && matches("ef") && !matches("efx"))
}

@Test(arguments: Language.allCases)
func generatorPoolsHaveNoRudeWords(language: Language) throws {
    let raw = try WordList.load(language)
    // Словари из субтитров: грубые слова в них есть — фильтру есть что отсеять.
    #expect(raw.words.prefix(2000).contains(where: WordFilter.isBlocked))
    let generator = TextGenerator(wordList: raw)
    #expect(!generator.wordList.words.contains(where: WordFilter.isBlocked))
    for kind in [WordPool.all, .frequent, .long] {
        let pool = generator.pool(letters: language.letters, kind: kind)
        #expect(!pool.contains(where: WordFilter.isBlocked), "\(kind)")
    }
    // Были в словарях и проходили до правки списка.
    let rude = language == .ru ? ["сукин", "насрать", "засранец", "сиськи", "херня"]
        : ["cocksucker", "prostitute", "penis", "prick", "pimp"]
    for word in rude { #expect(raw.words.contains(word) && !generator.wordList.words.contains(word), "\(word)") }
    let normal = language == .ru ? ["корабля", "хлеб", "класс", "небо", "сражение", "сравнить"]
        : ["assist", "class", "grass", "sushi", "precious", "stripe"]
    for word in normal { #expect(generator.wordList.words.contains(word), "\(word)") }
    var rng = SeededGenerator(seed: 1)
    let errorText = generator.errorWords(letters: language.letters, targets: Array(language.letters), length: 300,
                                         rng: &rng)
    #expect(!errorText.split(separator: " ").contains { WordFilter.isBlocked(String($0)) })
}
