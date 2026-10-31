import Foundation
import TypingCore

/// Откуда берётся текст для практики.
enum PracticeSource: Hashable {
    case frequentWords
    case library(LibraryText)
    case symbols
    case custom(UUID)
    /// «Текст» плана дня (§10.1, решение 12 фазы 6c): `text`-шаг в стиле этапа `stageIndex` (с 0); `nil` — фразы
    /// из изученных букв (до этапа 4).
    case planText(stageIndex: Int?, chars: Int)
    /// «Повтор» разминки плана: слова из открытых букв с упором на буквы `focus`.
    case planReview(focus: [Character], chars: Int)

    /// Значение `SessionRecord.source`.
    var recordName: String {
        switch self {
        case .frequentWords: "words"
        case .library(let item): "library:\(item.id)"
        case .symbols: "symbols"
        case .custom: "custom"
        case .planText: "plan:text"
        case .planReview: "plan:review"
        }
    }
}

/// Запуск практики: новый `id` на каждый запуск.
struct PracticeRun: Identifiable, Equatable {
    let id = UUID()
    let language: Language
    let source: PracticeSource
    /// Пункт плана дня, из которого запущена практика; `nil` — запуск не из плана.
    var planSlot: PlanSlot? = nil
    /// Порций у запуска из плана: после последней — выход (`PlanPortions`); `nil` — без предела.
    var portions: Int? = nil
}

/// Основа «Текста» плана: урок, чьи изученные символы и стиль этапа берёт текст (`PracticeTextFactory.planContext`).
struct PlanTextBasis {
    let planner: LessonPlanner
    let context: LessonContext
}

/// Текст упражнения практики по источнику. Чистая функция: ни UI, ни базы.
enum PracticeTextFactory {
    /// Длина упражнения из частотных слов и из символов.
    static let generatedLength = 300

    /// `custom` — текст пользователя (уже нормализованный) и позиция в нём; нужен только для `.custom`.
    /// `plan` — основа «Текста» плана, нужна только для `.planText` (без неё текст пустой). У `.planReview`
    /// `allowed` — открытые буквы (с пробелом).
    /// `nextOffset` есть только у своего текста: позиция после порции (для пустой порции — конец текста).
    /// `connected` — связный текст шага плана (`ExerciseSpec.connected`); у остальных источников признак
    /// даёт `SessionRecord.source` при записи.
    static func text<G: RandomNumberGenerator>(
        for source: PracticeSource, language: Language, allowed: Set<Character>, generator: TextGenerator,
        custom: (body: String, offset: Int)?, plan: PlanTextBasis? = nil, rng: inout G
    ) -> (text: String, nextOffset: Int?, connected: Bool) {
        switch source {
        case .frequentWords:
            let letters = language.letters.union([" "]).intersection(allowed)
            let text = generator.words(allowed: letters, focus: [], length: generatedLength, capitalRate: 0,
                                       rng: &rng)
            return (text, nil, false)
        case .library(let item):
            return (TextNormalizer.typeable(item.text, allowed: allowed), nil, false)
        case .symbols:
            let text = SymbolDrill.text(language: language, allowed: allowed, generator: generator,
                                        length: generatedLength, rng: &rng)
            return (text, nil, false)
        case .custom:
            guard let custom else { return ("", nil, false) }
            let chunk = TextChunker.chunk(custom.body, from: custom.offset)
            return (chunk.text, chunk.nextOffset, false)
        case let .planText(stageIndex, chars):
            guard let plan else { return ("", nil, false) }
            let spec = plan.planner.prepare(plan.context, learner: .empty)
                .exercise(stageIndex == nil ? .phrases : .text, length: chars, rng: &rng)
            return (spec.text, nil, spec.connected)
        case let .planReview(focus, chars):
            let letters = allowed.filter { $0.isLetter && !$0.isUppercase }
            let text = generator.focusedWords(letters: letters, focusKeys: focus, focusBigrams: [], length: chars,
                                              rng: &rng)
            if !text.isEmpty { return (text, nil, false) }
            // В словаре нет слов из открытых букв: псевдослова с упором на те же буквы.
            return (generator.words(allowed: letters.union([" "]), focus: Set(focus), length: chars, capitalRate: 0,
                                    rng: &rng), nil, false)
        }
    }

    /// Урок — основа «Текста» плана: последний пройденный урок этапа `stageIndex` (`nil` — всего курса); ничего
    /// не пройдено — первый урок этапа (курса). Его символы до него включительно — изученные.
    static func planContext(course: Course, passed: Set<String>, stageIndex: Int?) -> LessonContext? {
        let lessons = stageIndex.map { course.stages.indices.contains($0) ? course.stages[$0].lessons : [] }
            ?? course.lessons
        return (lessons.last { passed.contains($0.id) } ?? lessons.first).flatMap { course.context(for: $0.id) }
    }
}

/// Свой текст, подготовленный к сохранению.
enum CustomTextDraft {
    /// Меньше стольких набираемых символов в тексте не сохраняем.
    static let minimumLength = 20
    /// Длина названия, взятого из начала текста.
    static let titleLength = 40

    struct Draft: Equatable {
        let title: String
        let body: String
        let language: Language
    }

    enum Failure: Error, Equatable {
        case tooShort
    }

    /// Язык по преобладающим буквам (иначе `fallback`), нормализация под раскладку этого языка.
    static func make(title: String, raw: String, fallback: Language,
                     allowed: (Language) -> Set<Character>) -> Result<Draft, Failure> {
        let language = TextNormalizer.dominantLanguage(raw) ?? fallback
        let body = TextNormalizer.typeable(raw, allowed: allowed(language))
        guard body.count >= minimumLength else { return .failure(.tooShort) }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty
            ? String(body.prefix(titleLength)).trimmingCharacters(in: .whitespaces)
            : trimmed
        return .success(Draft(title: name, body: body, language: language))
    }

    /// Доля пройденного текста; позиция за пределами текста обрезается.
    static func progress(offset: Int, length: Int) -> Double {
        guard length > 0 else { return 0 }
        return Double(min(max(offset, 0), length)) / Double(length)
    }
}

/// Ссылка на страницу произведения для человека. В данных хранятся адреса для скачивания
/// (`action=raw` Викитеки, `pgNNN.txt` Gutenberg), а читать по ним нечего.
enum SourceLink {
    static func pageURL(for source: String) -> URL? {
        guard let components = URLComponents(string: source), let host = components.host else { return nil }
        if host.hasSuffix("wikisource.org"),
           let title = components.queryItems?.first(where: { $0.name == "title" })?.value, !title.isEmpty {
            let name = title.replacingOccurrences(of: " ", with: "_")
            let path = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return URL(string: "https://\(host)/wiki/\(path)")
        }
        if host.hasSuffix("gutenberg.org") {
            let parts = components.path.split(separator: "/")
            if parts.count == 4, parts[0] == "cache", parts[1] == "epub", Int(parts[2]) != nil {
                return URL(string: "https://www.gutenberg.org/ebooks/\(parts[2])")
            }
        }
        return URL(string: source)
    }
}
