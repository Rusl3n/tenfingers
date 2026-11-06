import Foundation
import TypingCore

/// Частотный словарь языка как множество слов; загружается один раз на язык и кэшируется.
enum ErrorWordVocabulary {
    private static let ru: Set<String> = load(.ru)
    private static let en: Set<String> = load(.en)

    static func words(_ language: Language) -> Set<String> {
        switch language {
        case .ru: return ru
        case .en: return en
        }
    }

    private static let enCourses: [Course] = courses(of: .en)
    private static let ruCourses: [Course] = courses(of: .ru)

    /// Курсы языка (текущий и архив издания 1): по ним решается, знаком ли апостроф.
    static func courses(_ language: Language) -> [Course] {
        switch language {
        case .ru: return ruCourses
        case .en: return enCourses
        }
    }

    private static func courses(of language: Language) -> [Course] {
        [try? CourseCatalog.load(language), try? CourseCatalog.legacy(language)].compactMap { $0 }
    }

    private static func load(_ language: Language) -> Set<String> {
        Set((try? WordList.load(language).words) ?? [])
    }
}
