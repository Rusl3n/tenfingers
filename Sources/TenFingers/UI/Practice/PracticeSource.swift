import Foundation
import TypingCore

/// Откуда берётся текст для практики.
enum PracticeSource: Hashable {
    case frequentWords
    case library(LibraryText)
    case symbols
    case custom(UUID)

    /// Значение `SessionRecord.source`.
    var recordName: String {
        switch self {
        case .frequentWords: "words"
        case .library(let item): "library:\(item.id)"
        case .symbols: "symbols"
        case .custom: "custom"
        }
    }
}

/// Запуск практики: новый `id` на каждый запуск.
struct PracticeRun: Identifiable, Equatable {
    let id = UUID()
    let language: Language
    let source: PracticeSource
}

/// Текст упражнения практики по источнику. Чистая функция: ни UI, ни базы.
enum PracticeTextFactory {
    /// Длина упражнения из частотных слов и из символов.
    static let generatedLength = 300

    /// `custom` — текст пользователя (уже нормализованный) и позиция в нём; нужен только для `.custom`.
    /// `nextOffset` есть только у своего текста: позиция после порции (для пустой порции — конец текста).
    static func text<G: RandomNumberGenerator>(
        for source: PracticeSource, language: Language, allowed: Set<Character>, generator: TextGenerator,
        custom: (body: String, offset: Int)?, rng: inout G
    ) -> (text: String, nextOffset: Int?) {
        switch source {
        case .frequentWords:
            let letters = language.letters.union([" "]).intersection(allowed)
            let text = generator.words(allowed: letters, focus: [], length: generatedLength, capitalRate: 0,
                                       rng: &rng)
            return (text, nil)
        case .library(let item):
            return (TextNormalizer.typeable(item.text, allowed: allowed), nil)
        case .symbols:
            let text = SymbolDrill.text(language: language, allowed: allowed, generator: generator,
                                        length: generatedLength, rng: &rng)
            return (text, nil)
        case .custom:
            guard let custom else { return ("", nil) }
            let chunk = TextChunker.chunk(custom.body, from: custom.offset)
            return (chunk.text, chunk.nextOffset)
        }
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
